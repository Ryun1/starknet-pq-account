//! `HybridDormantAccount`: ECDSA day to day, a committed PQ key for emergency takeover (ARCH-02).
//!
//! The account stores a Poseidon commitment to a PQ key and the verifier class that will check it,
//! and validates with ECDSA alone. When quantum attacks on ECDSA become credible, the owner
//! reveals the key (`activate`) and the account becomes a hybrid account, with storage identical
//! to a registered `HybridMigratableAccountV2`: ECDSA alone is refused from then on.
//!
//! States:
//! - Unregistered (no commitment, no key): ECDSA-only, a single self-call to `commit`.
//! - Dormant (commitment, no key): ECDSA-only. No call to the account itself except
//!   `propose_commitment` and `activate`, so a forged ECDSA signature cannot upgrade the class or
//!   replace the key the owner will activate with. It can still move anything ECDSA reaches until
//!   the owner activates (see contracts/docs/dormant-pq-key.md).
//! - Active (key stored): hybrid, through the committed verifier. `upgrade` (for example to V2,
//!   for key rotation and scheme switches) is a hybrid-signed self-call.
//!
//! The commitment binds the verifier and setup classes: if activation could pick them, an
//! attacker holding the ECDSA key could activate with a verifier that accepts anything.
//!
//! Changing the commitment with ECDSA alone takes `DORMANT_DELAY`: `propose_commitment`, then
//! `apply_commitment` (anyone) once the delay has passed. The owner vetoes a hostile proposal by
//! activating, which clears it.
//!
//! `activate` can be called by anyone (the caller pays, so a bad proof costs the account nothing)
//! and checks the proof in execution, so `__validate__` stays at ECDSA cost while dormant. The
//! proof is a hybrid signature by the current ECDSA key and the revealed PQ key over
//! `activation_hash`, which binds the chain and the account address.
//!
//! EXPERIMENTAL AND UNAUDITED. Testnet / demo use only.

use starknet::{ClassHash, ContractAddress};

pub const COMMIT_DOMAIN: felt252 = 'starknet-pq-dormant-commit-v1';
pub const ACTIVATE_DOMAIN: felt252 = 'starknet-pq-dormant-activate-v1';

/// How long an ECDSA-only commitment change waits before `apply_commitment` accepts it.
pub const DORMANT_DELAY: u64 = 7 * 24 * 60 * 60;

/// The value stored while dormant: the PQ key and the classes that will verify it.
pub fn commitment_hash(
    verifier_class_hash: ClassHash, setup_class_hash: ClassHash, pq_public_key: Span<felt252>,
) -> felt252 {
    let mut data = array![COMMIT_DOMAIN, verifier_class_hash.into(), setup_class_hash.into()];
    for felt in pq_public_key {
        data.append(*felt);
    }
    core::poseidon::poseidon_hash_span(data.span())
}

/// Message the activation proof signs.
pub fn activation_hash(
    chain_id: felt252,
    account: ContractAddress,
    ecdsa_public_key: felt252,
    pq_public_key: Span<felt252>,
) -> felt252 {
    let mut data = array![ACTIVATE_DOMAIN, chain_id, account.into(), ecdsa_public_key];
    for felt in pq_public_key {
        data.append(*felt);
    }
    core::poseidon::poseidon_hash_span(data.span())
}

#[starknet::interface]
pub trait IDormant<TState> {
    fn commit(ref self: TState, commitment: felt252);
    fn propose_commitment(ref self: TState, commitment: felt252);
    fn apply_commitment(ref self: TState);
    fn activate(
        ref self: TState,
        pq_public_key: Array<felt252>,
        verifier_class_hash: ClassHash,
        setup_class_hash: ClassHash,
        proof: Array<felt252>,
    );
    fn upgrade(ref self: TState, new_class_hash: ClassHash);
    fn get_commitment(self: @TState) -> felt252;
    /// The pending commitment and the time from which it can be applied; (0, 0) if none.
    fn get_pending_commitment(self: @TState) -> (felt252, u64);
    fn is_dormant(self: @TState) -> bool;
    fn get_ecdsa_public_key(self: @TState) -> felt252;
    fn get_falcon_public_key(self: @TState) -> Array<felt252>;
    fn get_verifier_class_hash(self: @TState) -> ClassHash;
    fn is_falcon_registered(self: @TState) -> bool;
}

#[starknet::contract(account)]
pub mod HybridDormantAccount {
    use core::num::traits::Zero;
    use pqbench_ecdsa_stark::EcdsaStarkVerifier;
    use starknet::account::Call;
    use starknet::storage::{
        MutableVecTrait, StoragePointerReadAccess, StoragePointerWriteAccess, Vec, VecTrait,
    };
    use starknet::{
        ClassHash, SyscallResultTrait, get_block_timestamp, get_caller_address,
        get_contract_address,
    };
    use crate::utils::execution;
    use crate::utils::interface::IHybridAccount;
    use super::{DORMANT_DELAY, activation_hash, commitment_hash};

    pub const ONLY_SELF: felt252 = 'Dormant: only self';
    pub const NOT_DORMANT: felt252 = 'Dormant: not dormant';
    pub const NOT_REGISTERED: felt252 = 'Dormant: not registered';
    pub const ALREADY_COMMITTED: felt252 = 'Dormant: already committed';
    pub const ZERO_COMMITMENT: felt252 = 'Dormant: zero commitment';
    pub const WRONG_KEY: felt252 = 'Dormant: key not committed';
    pub const SELF_CALL_BLOCKED: felt252 = 'Dormant: self-call blocked';
    pub const NOTHING_PENDING: felt252 = 'Dormant: nothing pending';
    pub const TOO_EARLY: felt252 = 'Dormant: delay not over';
    pub const INVALID_PROOF: felt252 = 'Dormant: invalid key proof';
    pub const INVALID_PQ_KEY: felt252 = 'Dormant: empty pq key';
    pub const INVALID_VERIFIER: felt252 = 'Dormant: invalid verifier';
    pub const STATE_CHANGED: felt252 = 'Dormant: state changed';
    pub const NO_ECDSA_KEY: felt252 = 'Dormant: no ecdsa key';

    #[storage]
    struct Storage {
        // `HybridMigratableAccountV2`'s fields, same names and types, so an active account can
        // `upgrade` to V2 and keep its keys and verifier.
        Account_public_key: felt252,
        ecdsa_public_key: felt252,
        falcon_public_key: Vec<felt252>,
        Migratable_verifier_class_hash: ClassHash,
        Dormant_commitment: felt252,
        Dormant_pending: felt252,
        Dormant_ready_at: u64,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        CommitmentSet: CommitmentSet,
        CommitmentProposed: CommitmentProposed,
        Activated: Activated,
    }

    #[derive(Drop, starknet::Event)]
    struct CommitmentSet {
        commitment: felt252,
    }

    /// Wallets should alert the owner on this event: a proposal the owner did not make means the
    /// ECDSA key is compromised, and the answer is to activate before `ready_at`.
    #[derive(Drop, starknet::Event)]
    struct CommitmentProposed {
        commitment: felt252,
        ready_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct Activated {
        verifier_class_hash: ClassHash,
    }

    /// Fresh deployment, dormant from the start.
    #[constructor]
    fn constructor(ref self: ContractState, ecdsa_public_key: felt252, commitment: felt252) {
        assert(ecdsa_public_key != 0, NO_ECDSA_KEY);
        self.Account_public_key.write(ecdsa_public_key);
        self._set_commitment(commitment);
    }

    #[abi(embed_v0)]
    impl AccountImpl of IHybridAccount<ContractState> {
        fn __execute__(self: @ContractState, calls: Array<Call>) {
            execution::assert_protocol_caller();
            execution::assert_valid_tx_version();
            execution::execute_calls(calls.span());
        }

        fn __validate__(self: @ContractState, calls: Array<Call>) -> felt252 {
            let tx_info = starknet::get_tx_info().unbox();
            if self._registered() {
                return execution::assert_valid_signature(
                    self._verify(tx_info.transaction_hash, tx_info.signature),
                );
            }
            let this = get_contract_address();
            if self._dormant() {
                for call in calls.span() {
                    if *call.to == this {
                        let selector = *call.selector;
                        assert(
                            selector == selector!("propose_commitment")
                                || selector == selector!("activate"),
                            SELF_CALL_BLOCKED,
                        );
                    }
                }
            } else {
                // Unregistered: only a single self-call to `commit`.
                assert(calls.len() == 1, NOT_REGISTERED);
                let call = calls.at(0);
                assert(*call.to == this, NOT_REGISTERED);
                assert(*call.selector == selector!("commit"), NOT_REGISTERED);
            }
            execution::assert_valid_signature(
                self._verify_ecdsa(tx_info.transaction_hash, tx_info.signature),
            )
        }

        fn __validate_declare__(self: @ContractState, class_hash: felt252) -> felt252 {
            let _ = class_hash;
            let tx_info = starknet::get_tx_info().unbox();
            if self._registered() {
                return execution::assert_valid_signature(
                    self._verify(tx_info.transaction_hash, tx_info.signature),
                );
            }
            assert(self._dormant(), NOT_REGISTERED);
            execution::assert_valid_signature(
                self._verify_ecdsa(tx_info.transaction_hash, tx_info.signature),
            )
        }

        /// Hybrid once active; ECDSA alone while dormant, so dapps keep working (these
        /// off-chain signatures are as forgeable after Q-day as any ECDSA account's).
        fn is_valid_signature(
            self: @ContractState, hash: felt252, signature: Array<felt252>,
        ) -> felt252 {
            if self._registered() {
                return execution::signature_result(self._verify(hash, signature.span()));
            }
            if self._dormant() {
                return execution::signature_result(self._verify_ecdsa(hash, signature.span()));
            }
            0
        }

        fn supports_interface(self: @ContractState, interface_id: felt252) -> bool {
            execution::supports_account_interface(interface_id)
        }
    }

    #[abi(embed_v0)]
    impl DormantImpl of super::IDormant<ContractState> {
        /// Unregistered → dormant, after a self-only `upgrade` from an account whose ECDSA key is
        /// already in `Account_public_key` (OpenZeppelin-style), in the same multicall.
        fn commit(ref self: ContractState, commitment: felt252) {
            self._assert_only_self();
            assert(!self._registered(), ALREADY_COMMITTED);
            assert(!self._dormant(), ALREADY_COMMITTED);
            assert(self.Account_public_key.read() != 0, NO_ECDSA_KEY);
            self._set_commitment(commitment);
        }

        /// Starts the delay for a new commitment. Replaces any pending proposal and restarts its
        /// clock.
        fn propose_commitment(ref self: ContractState, commitment: felt252) {
            self._assert_only_self();
            assert(self._dormant(), NOT_DORMANT);
            assert(commitment != 0, ZERO_COMMITMENT);
            let ready_at = get_block_timestamp() + DORMANT_DELAY;
            self.Dormant_pending.write(commitment);
            self.Dormant_ready_at.write(ready_at);
            self.emit(CommitmentProposed { commitment, ready_at });
        }

        /// Anyone, once the delay has passed.
        fn apply_commitment(ref self: ContractState) {
            assert(self._dormant(), NOT_DORMANT);
            let pending = self.Dormant_pending.read();
            assert(pending != 0, NOTHING_PENDING);
            assert(get_block_timestamp() >= self.Dormant_ready_at.read(), TOO_EARLY);
            self._clear_pending();
            self._set_commitment(pending);
        }

        /// Reveals the committed key and switches the account to hybrid validation. Anyone can
        /// call it; `proof` is a hybrid signature by the account's ECDSA key and `pq_public_key`
        /// over `activation_hash`, checked by the committed verifier after the key is written.
        fn activate(
            ref self: ContractState,
            pq_public_key: Array<felt252>,
            verifier_class_hash: ClassHash,
            setup_class_hash: ClassHash,
            proof: Array<felt252>,
        ) {
            assert(self._dormant(), NOT_DORMANT);
            let pq_key = pq_public_key.span();
            assert(
                commitment_hash(verifier_class_hash, setup_class_hash, pq_key) == self
                    .Dormant_commitment
                    .read(),
                WRONG_KEY,
            );
            let account_key = self.Account_public_key.read();
            let message = activation_hash(
                starknet::get_tx_info().unbox().chain_id, get_contract_address(), account_key, pq_key,
            );
            self.Dormant_commitment.write(0);
            self._clear_pending();
            self.ecdsa_public_key.write(account_key);
            self._write_pq_key(pq_public_key, verifier_class_hash, setup_class_hash);
            assert(self._verify(message, proof.span()), INVALID_PROOF);
            self._assert_state(account_key, pq_key, verifier_class_hash);
            self.emit(Activated { verifier_class_hash });
        }

        /// Class upgrade, once active (hybrid-signed self-call). Not checked: the class it
        /// installs is trusted. Blocked while dormant by `__validate__`.
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self._assert_only_self();
            assert(self._registered(), NOT_REGISTERED);
            starknet::syscalls::replace_class_syscall(new_class_hash).unwrap_syscall();
        }

        fn get_commitment(self: @ContractState) -> felt252 {
            self.Dormant_commitment.read()
        }

        fn get_pending_commitment(self: @ContractState) -> (felt252, u64) {
            (self.Dormant_pending.read(), self.Dormant_ready_at.read())
        }

        fn is_dormant(self: @ContractState) -> bool {
            self._dormant()
        }

        fn get_ecdsa_public_key(self: @ContractState) -> felt252 {
            self.Account_public_key.read()
        }

        fn get_falcon_public_key(self: @ContractState) -> Array<felt252> {
            self._read_pq_key()
        }

        fn get_verifier_class_hash(self: @ContractState) -> ClassHash {
            self.Migratable_verifier_class_hash.read()
        }

        fn is_falcon_registered(self: @ContractState) -> bool {
            self._registered()
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _assert_only_self(self: @ContractState) {
            assert(get_caller_address() == get_contract_address(), ONLY_SELF);
        }

        fn _registered(self: @ContractState) -> bool {
            self.falcon_public_key.len() != 0
        }

        fn _dormant(self: @ContractState) -> bool {
            !self._registered() && self.Dormant_commitment.read() != 0
        }

        fn _set_commitment(ref self: ContractState, commitment: felt252) {
            assert(commitment != 0, ZERO_COMMITMENT);
            self.Dormant_commitment.write(commitment);
            self.emit(CommitmentSet { commitment });
        }

        fn _clear_pending(ref self: ContractState) {
            self.Dormant_pending.write(0);
            self.Dormant_ready_at.write(0);
        }

        fn _read_pq_key(self: @ContractState) -> Array<felt252> {
            let mut key = array![];
            let len = self.falcon_public_key.len();
            let mut i = 0;
            while i != len {
                key.append(self.falcon_public_key.at(i).read());
                i += 1;
            }
            key
        }

        /// As V2's: writes the key and verifier, then runs the setup class, if any.
        fn _write_pq_key(
            ref self: ContractState,
            pq_public_key: Array<felt252>,
            verifier_class_hash: ClassHash,
            setup_class_hash: ClassHash,
        ) {
            assert(!pq_public_key.is_empty(), INVALID_PQ_KEY);
            assert(verifier_class_hash.is_non_zero(), INVALID_VERIFIER);
            for felt in pq_public_key {
                self.falcon_public_key.push(felt);
            }
            self.Migratable_verifier_class_hash.write(verifier_class_hash);
            if setup_class_hash.is_non_zero() {
                starknet::syscalls::library_call_syscall(
                    setup_class_hash, selector!("setup_pq_key"), array![].span(),
                )
                    .unwrap_syscall();
            }
        }

        /// The verifier and setup classes ran in this account's storage: the keys, the verifier
        /// pointer and the cleared commitment must still be what activation wrote.
        fn _assert_state(
            self: @ContractState,
            account_key: felt252,
            pq_key: Span<felt252>,
            verifier_class_hash: ClassHash,
        ) {
            assert(self.Migratable_verifier_class_hash.read() == verifier_class_hash, STATE_CHANGED);
            assert(self.Account_public_key.read() == account_key, STATE_CHANGED);
            assert(self.ecdsa_public_key.read() == account_key, STATE_CHANGED);
            assert(self._read_pq_key().span() == pq_key, STATE_CHANGED);
            assert(self.Dormant_commitment.read() == 0, STATE_CHANGED);
            assert(self.Dormant_pending.read() == 0, STATE_CHANGED);
        }

        fn _verify_ecdsa(self: @ContractState, hash: felt252, signature: Span<felt252>) -> bool {
            EcdsaStarkVerifier::verify(hash, array![self.Account_public_key.read()].span(), signature)
        }

        /// Library-calls the verifier class's `is_valid_signature` (ECDSA AND the PQ signature).
        fn _verify(self: @ContractState, hash: felt252, signature: Span<felt252>) -> bool {
            let mut calldata: Array<felt252> = array![hash];
            Serde::serialize(@signature, ref calldata);
            let result = starknet::syscalls::library_call_syscall(
                self.Migratable_verifier_class_hash.read(),
                selector!("is_valid_signature"),
                calldata.span(),
            )
                .unwrap_syscall();
            result.len() == 1 && *result.at(0) == starknet::VALIDATED
        }
    }
}
