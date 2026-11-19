//! `HybridMigratableAccount` without a fixed post-quantum scheme (PF-13 step 1, PF-14).
//!
//! Same account, storage and migration flows as `migratable.cairo`, with one difference: this
//! class does not know the PQ key's length. The verifier class decides what a valid key and
//! signature are, and every path that writes a key requires a proof that the owner can sign with
//! it through that verifier. So the account can hold a Falcon-512 key (29 felts), a Falcon-1024
//! key (57) or an ML-DSA-44 key (43), and move between them.
//!
//! `set_pq_key(pq_public_key, verifier_class_hash, setup_class_hash, proof)` replaces the PQ key
//! and its verifier in one hybrid-signed self-call: a key rotation (same verifier) or a scheme
//! change. The transaction is validated by the OLD key and verifier in `__validate__`; `proof` is
//! a hybrid signature by the NEW key pair over `rotation_hash(ecdsa_public_key, pq_public_key)`,
//! checked by the NEW verifier after the write. A key, verifier or setup that does not produce an
//! accepted signature reverts the call, so the account keeps its old key and verifier.
//!
//! `setup_class_hash`, if not zero, is library-called (`setup_pq_key()`) after the key is written
//! and before the proof is checked, for schemes that store work derived from the key (ML-DSA's
//! expanded matrix). Like the verifier, it runs as trusted code in this account's storage.
//!
//! An account on an earlier migratable class gets here with one hybrid-signed multicall:
//!   [ self.upgrade(this class), self.set_pq_key(...) ]
//! or with `upgrade` alone, keeping its Falcon-512 key and verifier: the storage is the same, and
//! `falcon_public_key` is the PQ key's storage name whatever the scheme, because the declared
//! verifier classes read it by that name.
//!
//! EXPERIMENTAL AND UNAUDITED. Testnet / demo use only.

use starknet::ClassHash;

/// `perform_upgrade` payload for Argent-style upgrades (`upgrade(class_hash, data)`).
#[derive(Drop, Serde)]
pub struct MigrationDataV2 {
    pub ecdsa_public_key: felt252,
    pub pq_public_key: Array<felt252>,
    pub verifier_class_hash: ClassHash,
    pub setup_class_hash: ClassHash,
    pub proof: Array<felt252>,
}

#[starknet::interface]
pub trait IMigratableV2<TState> {
    fn migrate(
        ref self: TState,
        ecdsa_public_key: felt252,
        pq_public_key: Array<felt252>,
        verifier_class_hash: ClassHash,
        setup_class_hash: ClassHash,
        proof: Array<felt252>,
    );
    fn perform_upgrade(ref self: TState, new_implementation: ClassHash, data: Span<felt252>);
    fn execute_after_upgrade(ref self: TState, data: Array<felt252>) -> Array<felt252>;
    fn set_pq_key(
        ref self: TState,
        pq_public_key: Array<felt252>,
        verifier_class_hash: ClassHash,
        setup_class_hash: ClassHash,
        proof: Array<felt252>,
    );
    fn rotate_ecdsa_public_key(ref self: TState, ecdsa_public_key: felt252, proof: Array<felt252>);
    fn set_verifier_class_hash(ref self: TState, verifier_class_hash: ClassHash);
    fn upgrade(ref self: TState, new_class_hash: ClassHash);
    fn get_ecdsa_public_key(self: @TState) -> felt252;
    fn get_falcon_public_key(self: @TState) -> Array<felt252>;
    fn get_verifier_class_hash(self: @TState) -> ClassHash;
    fn is_falcon_registered(self: @TState) -> bool;
}

#[starknet::contract(account)]
pub mod HybridMigratableAccountV2 {
    use core::num::traits::Zero;
    use pqbench_ecdsa_stark::EcdsaStarkVerifier;
    use starknet::account::Call;
    use starknet::storage::{
        MutableVecTrait, StoragePointerReadAccess, StoragePointerWriteAccess, Vec, VecTrait,
    };
    use starknet::{ClassHash, SyscallResultTrait, get_caller_address, get_contract_address};
    use crate::migratable::{registration_hash, rotation_hash};
    use crate::utils::execution;
    use crate::utils::interface::IHybridAccount;
    use super::MigrationDataV2;

    pub const ONLY_SELF: felt252 = 'Migratable: only self';
    pub const INVALID_PROOF: felt252 = 'Migratable: invalid key proof';
    pub const INVALID_DATA: felt252 = 'Migratable: invalid data';
    pub const ALREADY_REGISTERED: felt252 = 'Migratable: already registered';
    pub const NOT_REGISTERED: felt252 = 'Migratable: not registered';
    pub const INVALID_PQ_KEY: felt252 = 'Migratable: empty pq key';
    pub const INVALID_VERIFIER: felt252 = 'Migratable: invalid verifier';
    pub const INCOMPATIBLE_VERIFIER: felt252 = 'Migratable: verifier rejects';
    pub const STATE_CHANGED: felt252 = 'Migratable: state changed';
    pub const NO_ECDSA_KEY: felt252 = 'Migratable: no ecdsa key';

    #[storage]
    struct Storage {
        // Same names and types as `HybridMigratableAccount`, so an account keeps its keys and
        // verifier when it upgrades to this class. `falcon_public_key` holds the PQ key of
        // whichever scheme the verifier implements.
        Account_public_key: felt252,
        ecdsa_public_key: felt252,
        falcon_public_key: Vec<felt252>,
        Migratable_verifier_class_hash: ClassHash,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        FalconKeyRegistered: FalconKeyRegistered,
        PqKeySet: PqKeySet,
        EcdsaKeyRotated: EcdsaKeyRotated,
        VerifierChanged: VerifierChanged,
    }

    #[derive(Drop, starknet::Event)]
    struct FalconKeyRegistered {
        verifier_class_hash: ClassHash,
    }

    #[derive(Drop, starknet::Event)]
    struct PqKeySet {
        verifier_class_hash: ClassHash,
    }

    #[derive(Drop, starknet::Event)]
    struct EcdsaKeyRotated {
        ecdsa_public_key: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct VerifierChanged {
        verifier_class_hash: ClassHash,
    }

    /// Fresh deployment path (no migration): both keys and the verifier at construction.
    #[constructor]
    fn constructor(
        ref self: ContractState,
        ecdsa_public_key: felt252,
        pq_public_key: Array<felt252>,
        verifier_class_hash: ClassHash,
        setup_class_hash: ClassHash,
    ) {
        self.Account_public_key.write(ecdsa_public_key);
        self._register(pq_public_key, verifier_class_hash, setup_class_hash);
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
            // Bootstrap: ECDSA-only, and only a single self-call to `migrate` (which checks the
            // key-possession proof).
            assert(calls.len() == 1, NOT_REGISTERED);
            let call = calls.at(0);
            assert(*call.to == get_contract_address(), NOT_REGISTERED);
            assert(*call.selector == selector!("migrate"), NOT_REGISTERED);
            execution::assert_valid_signature(
                EcdsaStarkVerifier::verify(
                    tx_info.transaction_hash,
                    array![self.Account_public_key.read()].span(),
                    tx_info.signature,
                ),
            )
        }

        fn __validate_declare__(self: @ContractState, class_hash: felt252) -> felt252 {
            let _ = class_hash;
            assert(self._registered(), NOT_REGISTERED);
            let tx_info = starknet::get_tx_info().unbox();
            execution::assert_valid_signature(
                self._verify(tx_info.transaction_hash, tx_info.signature),
            )
        }

        fn is_valid_signature(
            self: @ContractState, hash: felt252, signature: Array<felt252>,
        ) -> felt252 {
            if !self._registered() {
                return 0;
            }
            execution::signature_result(self._verify(hash, signature.span()))
        }

        fn supports_interface(self: @ContractState, interface_id: felt252) -> bool {
            execution::supports_account_interface(interface_id)
        }
    }

    #[abi(embed_v0)]
    impl MigratableImpl of super::IMigratableV2<ContractState> {
        /// Migration after a self-only `upgrade` (Braavos, OpenZeppelin), in the same
        /// multicall. Both keys must be proven.
        fn migrate(
            ref self: ContractState,
            ecdsa_public_key: felt252,
            pq_public_key: Array<felt252>,
            verifier_class_hash: ClassHash,
            setup_class_hash: ClassHash,
            proof: Array<felt252>,
        ) {
            self._assert_only_self();
            assert(!self._registered(), ALREADY_REGISTERED);
            self
                ._migrate(
                    ecdsa_public_key, pq_public_key, verifier_class_hash, setup_class_hash, proof,
                );
        }

        /// Argent upgrade callback, library-called by the old class's `upgrade`: replaces the
        /// class and migrates in the same call. `data` is a serialized `MigrationDataV2`.
        fn perform_upgrade(
            ref self: ContractState, new_implementation: ClassHash, data: Span<felt252>,
        ) {
            self._assert_only_self();
            assert(!self._registered(), ALREADY_REGISTERED);
            starknet::syscalls::replace_class_syscall(new_implementation).unwrap_syscall();
            self._migrate_from_data(data);
        }

        /// Argent 0.3.x upgrade callback: the old class has already replaced itself with this
        /// one and library-calls this with the `upgrade` calldata (a serialized
        /// `MigrationDataV2`).
        fn execute_after_upgrade(ref self: ContractState, data: Array<felt252>) -> Array<felt252> {
            self._assert_only_self();
            assert(!self._registered(), ALREADY_REGISTERED);
            self._migrate_from_data(data.span());
            array![]
        }

        /// Replaces the PQ key and its verifier: a key rotation, or a change of scheme. Requires
        /// a hybrid-signed transaction (self-call) and a proof by the new key pair that the new
        /// verifier accepts. The verifier and the setup class run in this account's storage, so
        /// the call also reverts if they changed the keys or the verifier pointer.
        fn set_pq_key(
            ref self: ContractState,
            pq_public_key: Array<felt252>,
            verifier_class_hash: ClassHash,
            setup_class_hash: ClassHash,
            proof: Array<felt252>,
        ) {
            self._assert_only_self();
            assert(self._registered(), NOT_REGISTERED);
            let account_key = self.Account_public_key.read();
            let mirrored_key = self.ecdsa_public_key.read();
            let pq_key = pq_public_key.span();
            let message = rotation_hash(account_key, pq_key);
            self._write_pq_key(pq_public_key, verifier_class_hash, setup_class_hash);
            assert(self._verify(message, proof.span()), INVALID_PROOF);
            self._assert_state(account_key, mirrored_key, pq_key, verifier_class_hash);
            self.emit(PqKeySet { verifier_class_hash });
        }

        /// Replaces the classical STARK-curve key. Requires a hybrid-signed transaction
        /// (self-call), so a forged ECDSA signature alone cannot rotate it, and a proof that the
        /// owner can sign with the new key.
        fn rotate_ecdsa_public_key(
            ref self: ContractState, ecdsa_public_key: felt252, proof: Array<felt252>,
        ) {
            self._assert_only_self();
            assert(self._registered(), NOT_REGISTERED);
            assert(ecdsa_public_key != 0, NO_ECDSA_KEY);
            self.Account_public_key.write(ecdsa_public_key);
            self.ecdsa_public_key.write(ecdsa_public_key);
            let message = rotation_hash(ecdsa_public_key, self._read_pq_key().span());
            assert(self._verify(message, proof.span()), INVALID_PROOF);
            self.emit(EcdsaKeyRotated { ecdsa_public_key });
        }

        /// Points verification at another declared verifier class of the SAME scheme (e.g. an
        /// audited one). Requires a hybrid-signed transaction (self-call). The new verifier must
        /// accept this transaction's own signature, or the switch reverts; a verifier of another
        /// scheme therefore needs `set_pq_key`.
        fn set_verifier_class_hash(ref self: ContractState, verifier_class_hash: ClassHash) {
            self._assert_only_self();
            assert(self._registered(), NOT_REGISTERED);
            assert(verifier_class_hash.is_non_zero(), INVALID_VERIFIER);
            let account_key = self.Account_public_key.read();
            let mirrored_key = self.ecdsa_public_key.read();
            let pq_key = self._read_pq_key();
            self.Migratable_verifier_class_hash.write(verifier_class_hash);
            let tx_info = starknet::get_tx_info().unbox();
            assert(self._verify(tx_info.transaction_hash, tx_info.signature), INCOMPATIBLE_VERIFIER);
            self._assert_state(account_key, mirrored_key, pq_key.span(), verifier_class_hash);
            self.emit(VerifierChanged { verifier_class_hash });
        }

        /// Class upgrade. Hybrid-signed self-call. Not checked: the class it installs is trusted.
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self._assert_only_self();
            starknet::syscalls::replace_class_syscall(new_class_hash).unwrap_syscall();
        }

        fn get_ecdsa_public_key(self: @ContractState) -> felt252 {
            self.Account_public_key.read()
        }

        /// The PQ key of whichever scheme the verifier implements (the name is the earlier
        /// classes', which wallets and the verifier-switch guard already call).
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

        /// A PQ key is stored. True for an account migrated on an earlier class (29 felts).
        fn _registered(self: @ContractState) -> bool {
            self.falcon_public_key.len() != 0
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

        /// Replaces the stored PQ key and verifier, then runs the scheme's setup, if any. The
        /// caller must check a proof afterwards: nothing here says the key is usable.
        fn _write_pq_key(
            ref self: ContractState,
            pq_public_key: Array<felt252>,
            verifier_class_hash: ClassHash,
            setup_class_hash: ClassHash,
        ) {
            assert(!pq_public_key.is_empty(), INVALID_PQ_KEY);
            assert(verifier_class_hash.is_non_zero(), INVALID_VERIFIER);
            while self.falcon_public_key.pop().is_some() {}
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

        /// The verifier and setup classes ran in this account's storage: the keys and the
        /// verifier pointer must still be what this call wrote.
        fn _assert_state(
            self: @ContractState,
            account_key: felt252,
            mirrored_key: felt252,
            pq_key: Span<felt252>,
            verifier_class_hash: ClassHash,
        ) {
            assert(self.Migratable_verifier_class_hash.read() == verifier_class_hash, STATE_CHANGED);
            assert(self.Account_public_key.read() == account_key, STATE_CHANGED);
            assert(self.ecdsa_public_key.read() == mirrored_key, STATE_CHANGED);
            assert(self._read_pq_key().span() == pq_key, STATE_CHANGED);
        }

        fn _register(
            ref self: ContractState,
            pq_public_key: Array<felt252>,
            verifier_class_hash: ClassHash,
            setup_class_hash: ClassHash,
        ) {
            let ecdsa_key = self.Account_public_key.read();
            assert(ecdsa_key != 0, NO_ECDSA_KEY);
            self.ecdsa_public_key.write(ecdsa_key);
            self._write_pq_key(pq_public_key, verifier_class_hash, setup_class_hash);
            self.emit(FalconKeyRegistered { verifier_class_hash });
        }

        fn _migrate_from_data(ref self: ContractState, data: Span<felt252>) {
            let mut data = data;
            let m: MigrationDataV2 = Serde::deserialize(ref data).expect(INVALID_DATA);
            assert(data.is_empty(), INVALID_DATA);
            self
                ._migrate(
                    m.ecdsa_public_key,
                    m.pq_public_key,
                    m.verifier_class_hash,
                    m.setup_class_hash,
                    m.proof,
                );
        }

        /// Writes both keys, then requires a hybrid signature by them over the registration
        /// hash, so an account cannot be migrated to keys its owner does not hold.
        fn _migrate(
            ref self: ContractState,
            ecdsa_public_key: felt252,
            pq_public_key: Array<felt252>,
            verifier_class_hash: ClassHash,
            setup_class_hash: ClassHash,
            proof: Array<felt252>,
        ) {
            assert(ecdsa_public_key != 0, NO_ECDSA_KEY);
            let message = registration_hash(ecdsa_public_key, pq_public_key.span());
            self.Account_public_key.write(ecdsa_public_key);
            self._register(pq_public_key, verifier_class_hash, setup_class_hash);
            assert(self._verify(message, proof.span()), INVALID_PROOF);
        }

        /// Library-calls the verifier class's `is_valid_signature`, which reads the mirrored
        /// keys from this account's storage and checks ECDSA AND the PQ signature.
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
