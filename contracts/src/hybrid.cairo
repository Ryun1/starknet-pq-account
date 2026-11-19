//! Hybrid ECDSA-STARK + Falcon-512 account.
//!
//! A transaction is valid only if BOTH signatures verify over the same transaction hash:
//! the classical STARK-curve ECDSA signature AND a post-quantum Falcon-512 signature.
//! If either scheme is broken (e.g. ECDSA by a future quantum computer), the other still
//! protects the account.
//!
//! Signature layout: `[ecdsa_r, ecdsa_s, falcon_signature...]` (2 + 60 felts for the
//! hint variants). Keys: one STARK-curve public key felt + a 29-felt packed Falcon key.
//!
//! EXPERIMENTAL AND UNAUDITED. Testnet / demo use only.

use pqbench_ecdsa_stark::EcdsaStarkVerifier;
use pqbench_falcon_512::PUBKEY_FELTS;
use pqbench_interface::PqSignatureVerifier;

/// Number of felts in the classical ECDSA part of the signature.
pub const ECDSA_SIG_FELTS: u32 = 2;

pub const INVALID_FALCON_KEY: felt252 = 'Hybrid: invalid falcon key';
pub const INVALID_ECDSA_KEY: felt252 = 'Hybrid: invalid ecdsa key';

/// Verifies the hybrid signature. Returns false on any malformed input.
pub fn verify_hybrid<impl Falcon: PqSignatureVerifier>(
    hash: felt252, ecdsa_public_key: felt252, falcon_public_key: Span<felt252>,
    signature: Span<felt252>,
) -> bool {
    if signature.len() <= ECDSA_SIG_FELTS {
        return false;
    }
    let ecdsa_ok = EcdsaStarkVerifier::verify(
        hash, array![ecdsa_public_key].span(), signature.slice(0, ECDSA_SIG_FELTS),
    );
    if !ecdsa_ok {
        return false;
    }
    Falcon::verify(
        hash,
        falcon_public_key,
        signature.slice(ECDSA_SIG_FELTS, signature.len() - ECDSA_SIG_FELTS),
    )
}

#[starknet::component]
pub mod HybridAccountComponent {
    use core::pedersen::pedersen;
    use pqbench_interface::PqSignatureVerifier;
    use starknet::account::Call;
    use starknet::storage::{
        MutableVecTrait, StoragePointerReadAccess, StoragePointerWriteAccess, Vec, VecTrait,
    };
    use starknet::storage_access::storage_base_address_from_felt252;
    use starknet::{Store, SyscallResultTrait};
    use crate::utils::execution;
    use crate::utils::interface::{
        IHybridAccount, IHybridDeployable, IHybridPublicKeys, IHybridVerifier,
    };
    use super::{INVALID_ECDSA_KEY, INVALID_FALCON_KEY, PUBKEY_FELTS, verify_hybrid};

    #[storage]
    pub struct Storage {
        pub ecdsa_public_key: felt252,
        pub falcon_public_key: Vec<felt252>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {}

    #[embeddable_as(AccountImpl)]
    impl Account<
        TContractState,
        impl Falcon: PqSignatureVerifier,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
    > of IHybridAccount<ComponentState<TContractState>> {
        fn __execute__(self: @ComponentState<TContractState>, calls: Array<Call>) {
            execution::assert_protocol_caller();
            execution::assert_valid_tx_version();
            execution::execute_calls(calls.span());
        }

        fn __validate__(self: @ComponentState<TContractState>, calls: Array<Call>) -> felt252 {
            let _ = calls;
            self.validate_transaction::<Falcon>()
        }

        fn __validate_declare__(
            self: @ComponentState<TContractState>, class_hash: felt252,
        ) -> felt252 {
            let _ = class_hash;
            self.validate_transaction::<Falcon>()
        }

        fn is_valid_signature(
            self: @ComponentState<TContractState>, hash: felt252, signature: Array<felt252>,
        ) -> felt252 {
            execution::signature_result(
                verify_hybrid::<
                    Falcon,
                >(
                    hash,
                    self.ecdsa_public_key.read(),
                    self.read_falcon_public_key().span(),
                    signature.span(),
                ),
            )
        }

        fn supports_interface(
            self: @ComponentState<TContractState>, interface_id: felt252,
        ) -> bool {
            execution::supports_account_interface(interface_id)
        }
    }

    /// `is_valid_signature` alone, for verifier classes that are only library-called.
    #[embeddable_as(VerifierImpl)]
    impl Verifier<
        TContractState,
        impl Falcon: PqSignatureVerifier,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
    > of IHybridVerifier<ComponentState<TContractState>> {
        fn is_valid_signature(
            self: @ComponentState<TContractState>, hash: felt252, signature: Array<felt252>,
        ) -> felt252 {
            execution::signature_result(
                verify_hybrid::<
                    Falcon,
                >(
                    hash,
                    self.ecdsa_public_key.read(),
                    self.read_falcon_public_key().span(),
                    signature.span(),
                ),
            )
        }
    }

    /// As `VerifierImpl`, reading the Falcon key with `read_falcon_public_key_once` (PF-11).
    #[embeddable_as(VerifierKeyReadImpl)]
    impl VerifierKeyRead<
        TContractState,
        impl Falcon: PqSignatureVerifier,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
    > of IHybridVerifier<ComponentState<TContractState>> {
        fn is_valid_signature(
            self: @ComponentState<TContractState>, hash: felt252, signature: Array<felt252>,
        ) -> felt252 {
            execution::signature_result(
                verify_hybrid::<
                    Falcon,
                >(
                    hash,
                    self.ecdsa_public_key.read(),
                    self.read_falcon_public_key_once().span(),
                    signature.span(),
                ),
            )
        }
    }

    /// PQ-only (ARCH-01): the signature is the PQ signature alone, no ECDSA felts. The ECDSA key
    /// stays in storage, unread. Installed with V2's `set_pq_key`, whose proof it checks the same
    /// way, so the account class does not change.
    #[embeddable_as(PqOnlyVerifierImpl)]
    impl PqOnlyVerifier<
        TContractState,
        impl Pq: PqSignatureVerifier,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
    > of IHybridVerifier<ComponentState<TContractState>> {
        fn is_valid_signature(
            self: @ComponentState<TContractState>, hash: felt252, signature: Array<felt252>,
        ) -> felt252 {
            execution::signature_result(
                Pq::verify(hash, self.read_falcon_public_key_once().span(), signature.span()),
            )
        }
    }

    #[embeddable_as(DeployableImpl)]
    impl Deployable<
        TContractState,
        impl Falcon: PqSignatureVerifier,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
    > of IHybridDeployable<ComponentState<TContractState>> {
        fn __validate_deploy__(
            self: @ComponentState<TContractState>,
            class_hash: felt252,
            contract_address_salt: felt252,
            ecdsa_public_key: felt252,
            falcon_public_key: Array<felt252>,
        ) -> felt252 {
            let _ = class_hash;
            let _ = contract_address_salt;
            let _ = ecdsa_public_key;
            let _ = falcon_public_key;
            self.validate_transaction::<Falcon>()
        }
    }

    #[embeddable_as(PublicKeysImpl)]
    impl PublicKeys<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>,
    > of IHybridPublicKeys<ComponentState<TContractState>> {
        fn get_ecdsa_public_key(self: @ComponentState<TContractState>) -> felt252 {
            self.ecdsa_public_key.read()
        }

        fn get_falcon_public_key(self: @ComponentState<TContractState>) -> Array<felt252> {
            self.read_falcon_public_key()
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>,
    > of InternalTrait<TContractState> {
        /// Stores both public keys. Rejects malformed keys at deployment.
        fn initializer(
            ref self: ComponentState<TContractState>,
            ecdsa_public_key: felt252,
            falcon_public_key: Array<felt252>,
        ) {
            assert(ecdsa_public_key != 0, INVALID_ECDSA_KEY);
            assert(falcon_public_key.len() == PUBKEY_FELTS, INVALID_FALCON_KEY);
            self.ecdsa_public_key.write(ecdsa_public_key);
            for felt in falcon_public_key {
                self.falcon_public_key.push(felt);
            }
        }

        /// Validates the current transaction hash against the hybrid signature.
        fn validate_transaction<impl Falcon: PqSignatureVerifier>(
            self: @ComponentState<TContractState>,
        ) -> felt252 {
            let tx_info = starknet::get_tx_info().unbox();
            execution::assert_valid_signature(
                verify_hybrid::<
                    Falcon,
                >(
                    tx_info.transaction_hash,
                    self.ecdsa_public_key.read(),
                    self.read_falcon_public_key().span(),
                    tx_info.signature,
                ),
            )
        }

        fn read_falcon_public_key(self: @ComponentState<TContractState>) -> Array<felt252> {
            let mut key = array![];
            let len = self.falcon_public_key.len();
            let mut i = 0;
            while i != len {
                key.append(self.falcon_public_key.at(i).read());
                i += 1;
            }
            key
        }

        /// As `read_falcon_public_key`, reading the length once. `Vec::at` reads it again for
        /// every element to check bounds, 29 storage reads per signature. Same storage layout:
        /// element `i` is at `pedersen(base, i)`, so migrated accounts read the same key.
        fn read_falcon_public_key_once(self: @ComponentState<TContractState>) -> Array<felt252> {
            let base = self.falcon_public_key.__base_address__;
            let len = self.falcon_public_key.len();
            let mut key = array![];
            let mut i: u64 = 0;
            while i != len {
                let address = storage_base_address_from_felt252(pedersen(base, i.into()));
                key.append(Store::<felt252>::read(0, address).unwrap_syscall());
                i += 1;
            }
            key
        }
    }
}

/// Hybrid account using the Falcon-512 native-Poseidon verifier (cheapest; needs a
/// matching Poseidon hash-to-point signer).
#[starknet::contract(account)]
pub mod HybridPoseidonAccount {
    use pqbench_falcon_512::Falcon512PoseidonVerifier;
    use super::HybridAccountComponent;

    component!(path: HybridAccountComponent, storage: account, event: AccountEvent);

    #[abi(embed_v0)]
    impl AccountImpl =
        HybridAccountComponent::AccountImpl<ContractState, Falcon512PoseidonVerifier>;
    #[abi(embed_v0)]
    impl DeployableImpl =
        HybridAccountComponent::DeployableImpl<ContractState, Falcon512PoseidonVerifier>;
    #[abi(embed_v0)]
    impl PublicKeysImpl = HybridAccountComponent::PublicKeysImpl<ContractState>;
    impl InternalImpl = HybridAccountComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        account: HybridAccountComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        AccountEvent: HybridAccountComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, ecdsa_public_key: felt252, falcon_public_key: Array<felt252>,
    ) {
        self.account.initializer(ecdsa_public_key, falcon_public_key);
    }
}

/// Hybrid account using the round-three Falcon-512 verifier with SHAKE-256 hash-to-point
/// (interoperable with Falcon-512 signers using that hash-to-point, such as falcon.py and the
/// browser signer; ~4x the verification gas of Poseidon). Not FN-DSA (FIPS 206).
#[starknet::contract(account)]
pub mod HybridShakeAccount {
    use pqbench_falcon_512::Falcon512ShakeVerifier;
    use super::HybridAccountComponent;

    component!(path: HybridAccountComponent, storage: account, event: AccountEvent);

    #[abi(embed_v0)]
    impl AccountImpl =
        HybridAccountComponent::AccountImpl<ContractState, Falcon512ShakeVerifier>;
    #[abi(embed_v0)]
    impl DeployableImpl =
        HybridAccountComponent::DeployableImpl<ContractState, Falcon512ShakeVerifier>;
    #[abi(embed_v0)]
    impl PublicKeysImpl = HybridAccountComponent::PublicKeysImpl<ContractState>;
    impl InternalImpl = HybridAccountComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        account: HybridAccountComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        AccountEvent: HybridAccountComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, ecdsa_public_key: felt252, falcon_public_key: Array<felt252>,
    ) {
        self.account.initializer(ecdsa_public_key, falcon_public_key);
    }
}

/// Verifier class for `HybridMigratableAccount`, with the Provably Fast compact Falcon-512
/// verifier (`fj_3a0b1c78817845a68e1e907928a541e4`, see vendor/provably-fast/falcon-512).
/// Same SHAKE-256 signatures, keys and storage as `HybridShakeAccount`, about half the
/// verification gas. Only `is_valid_signature`: it is declared and library-called, never deployed.
#[starknet::contract]
pub mod HybridShakeVerifierPfCompact {
    use pqbench_falcon_512_pf_compact::Falcon512ShakeVerifier;
    use super::HybridAccountComponent;

    component!(path: HybridAccountComponent, storage: account, event: AccountEvent);

    #[abi(embed_v0)]
    impl VerifierImpl =
        HybridAccountComponent::VerifierImpl<ContractState, Falcon512ShakeVerifier>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        account: HybridAccountComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        AccountEvent: HybridAccountComponent::Event,
    }
}

/// As `HybridShakeVerifierPfCompact`, with the Falcon-512 record verifier at the time of pinning
/// (`fj_c3459a8b07a54bd5828d3fdde899c4e0`).
#[starknet::contract]
pub mod HybridShakeVerifierPfRecord {
    use pqbench_falcon_512_pf_record::Falcon512ShakeVerifier;
    use super::HybridAccountComponent;

    component!(path: HybridAccountComponent, storage: account, event: AccountEvent);

    #[abi(embed_v0)]
    impl VerifierImpl =
        HybridAccountComponent::VerifierImpl<ContractState, Falcon512ShakeVerifier>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        account: HybridAccountComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        AccountEvent: HybridAccountComponent::Event,
    }
}

/// As `HybridShakeVerifierPfCompact`, with the Provably Fast `fj_dee1326c0eef48e6989ed0338e9e9785`
/// verifier: about 3% more verification gas than compact, but its declare (about 5.44e9 L2 gas) fits
/// in a Starknet block, which compact's and record's (5.87e9, 6.31e9) do not (bench/pf04).
#[starknet::contract]
pub mod HybridShakeVerifierPfSmall {
    use pqbench_falcon_512_pf_small::Falcon512ShakeVerifier;
    use super::HybridAccountComponent;

    component!(path: HybridAccountComponent, storage: account, event: AccountEvent);

    #[abi(embed_v0)]
    impl VerifierImpl =
        HybridAccountComponent::VerifierImpl<ContractState, Falcon512ShakeVerifier>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        account: HybridAccountComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        AccountEvent: HybridAccountComponent::Event,
    }
}

/// As `HybridShakeVerifierPfSmall`, reading the Falcon key's length once instead of once per
/// element (PF-11). Same storage layout, so the guarded switch can install it over small.
#[starknet::contract]
pub mod HybridShakeVerifierPfSmallKeyRead {
    use pqbench_falcon_512_pf_small::Falcon512ShakeVerifier;
    use super::HybridAccountComponent;

    component!(path: HybridAccountComponent, storage: account, event: AccountEvent);

    #[abi(embed_v0)]
    impl VerifierImpl =
        HybridAccountComponent::VerifierKeyReadImpl<ContractState, Falcon512ShakeVerifier>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        account: HybridAccountComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        AccountEvent: HybridAccountComponent::Event,
    }
}

/// Falcon-1024 (NIST level 5) verifier class for `HybridMigratableAccountV2` (PF-14), with the
/// Provably Fast Falcon-1024 record (`fk_2956035507114a6c89165c8cc8e8fe56`, see
/// vendor/provably-fast/falcon-1024). 57-felt key, 116-felt Falcon signature in the Falcon-512 hint
/// layout at n = 1024. The account stores the key in the same `falcon_public_key` Vec, so a V2
/// account switches to it with `set_pq_key`; the verifier rejects a 29-felt key.
#[starknet::contract]
pub mod HybridShakeVerifierFalcon1024 {
    use pqbench_falcon_1024_pf_record::Falcon1024Verifier;
    use super::HybridAccountComponent;

    component!(path: HybridAccountComponent, storage: account, event: AccountEvent);

    #[abi(embed_v0)]
    impl VerifierImpl =
        HybridAccountComponent::VerifierKeyReadImpl<ContractState, Falcon1024Verifier>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        account: HybridAccountComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        AccountEvent: HybridAccountComponent::Event,
    }
}

/// PQ-only (ARCH-01) verifier class for `HybridMigratableAccountV2`: Falcon-512 SHAKE-256 alone,
/// with the verifier of `HybridShakeVerifierPfSmall`. Signature: the 60 Falcon felts, no ECDSA.
/// An account switches to it with `set_pq_key`, whose proof is then a Falcon-only signature over
/// `rotation_hash`. EXPERIMENTAL: drops ECDSA's defence in depth against a Falcon or verifier bug
/// (contracts/docs/pq-only.md).
#[starknet::contract]
pub mod FalconOnlyVerifierPfSmall {
    use pqbench_falcon_512_pf_small::Falcon512ShakeVerifier;
    use super::HybridAccountComponent;

    component!(path: HybridAccountComponent, storage: account, event: AccountEvent);

    #[abi(embed_v0)]
    impl VerifierImpl =
        HybridAccountComponent::PqOnlyVerifierImpl<ContractState, Falcon512ShakeVerifier>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        account: HybridAccountComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        AccountEvent: HybridAccountComponent::Event,
    }
}

/// As `FalconOnlyVerifierPfSmall`, with the Falcon-1024 verifier of
/// `HybridShakeVerifierFalcon1024`: 57-felt key, 116-felt signature, no ECDSA.
#[starknet::contract]
pub mod FalconOnlyVerifierFalcon1024 {
    use pqbench_falcon_1024_pf_record::Falcon1024Verifier;
    use super::HybridAccountComponent;

    component!(path: HybridAccountComponent, storage: account, event: AccountEvent);

    #[abi(embed_v0)]
    impl VerifierImpl =
        HybridAccountComponent::PqOnlyVerifierImpl<ContractState, Falcon1024Verifier>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        account: HybridAccountComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        AccountEvent: HybridAccountComponent::Event,
    }
}
