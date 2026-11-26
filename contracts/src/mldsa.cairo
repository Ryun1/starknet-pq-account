//! ML-DSA-44 (FIPS 204) for `HybridMigratableAccountV2` (PF-13), with the Provably Fast record
//! `mj_2e2f9ddebbcc4281b07d84937ae0ffbc` (see vendor/provably-fast/ml-dsa-44).
//!
//! Verifying from scratch costs about 170M L2 gas, over the 100M validation cap: most of it,
//! tr = H(pk) and the expanded matrix A-hat, depends only on the key. So the scheme has two classes:
//!
//! - `MlDsa44KeySetup`: `setup_pq_key()`, library-called once by `set_pq_key` / `migrate` after the
//!   key is written. Computes tr and A-hat from the stored key and writes them to the cache below,
//!   with a digest of the key they were computed from.
//! - `HybridMlDsa44Verifier`: `is_valid_signature`, library-called in `__validate__`. ECDSA first,
//!   then the record's check from the cache. A cache that does not match the stored key (no setup
//!   ran, or it ran for another key) rejects every signature.
//!
//! The cache is a public function of the key, so storing it changes nothing about which signatures
//! are accepted. Key 43 felts, ML-DSA signature 79 felts, hybrid signature 81.
//!
//! EXPERIMENTAL AND UNAUDITED. Testnet / demo use only.

use core::poseidon::poseidon_hash_span;
use pqbench_interface::PqSignatureVerifier;
use pqbench_ml_dsa_44_pf_record::verx::cache::{A_FELTS, TR_FELTS, precompute, verify_cached};
use starknet::storage_access::{
    StorageAddress, storage_address_from_base_and_offset, storage_base_address_from_felt252,
};
use starknet::syscalls::{storage_read_syscall, storage_write_syscall};
use starknet::SyscallResultTrait;

pub const PK_FELTS: u32 = 43;
pub const SIG_FELTS: u32 = 79;
/// tr, then A-hat, then the Poseidon digest of the key they were computed from.
pub const CACHE_FELTS: u32 = TR_FELTS + A_FELTS + 1;
pub const MALFORMED_KEY: felt252 = 'MlDsa44: malformed key';

/// Slot `i` of the cache: 0..256 from one base, the rest from another (an offset is a `u8`).
fn slot(i: u32) -> StorageAddress {
    if i < 256 {
        storage_address_from_base_and_offset(
            storage_base_address_from_felt252(selector!("MlDsa44_cache_0")), i.try_into().unwrap(),
        )
    } else {
        storage_address_from_base_and_offset(
            storage_base_address_from_felt252(selector!("MlDsa44_cache_1")),
            (i - 256).try_into().unwrap(),
        )
    }
}

fn read_slots(from: u32, to: u32) -> Array<felt252> {
    let mut out = array![];
    let mut i = from;
    while i != to {
        out.append(storage_read_syscall(0, slot(i)).unwrap_syscall());
        i += 1;
    }
    out
}

/// Computes and stores the cache for `pk`. Panics on a malformed key.
pub fn write_cache(pk: Span<felt252>) {
    let (tr, a_hat) = precompute(pk).expect(MALFORMED_KEY);
    let mut i = 0;
    for felt in tr.span().into_iter().chain(a_hat.span()) {
        storage_write_syscall(0, slot(i), *felt).unwrap_syscall();
        i += 1;
    }
    storage_write_syscall(0, slot(i), poseidon_hash_span(pk)).unwrap_syscall();
}

/// The record's check with tr and A-hat read from the cache. Called through the account's library
/// call, so the raw storage reads are the account's storage.
pub impl MlDsa44CachedVerifier of PqSignatureVerifier {
    fn verify(message_hash: felt252, public_key: Span<felt252>, signature: Span<felt252>) -> bool {
        if public_key.len() != PK_FELTS || signature.len() != SIG_FELTS {
            return false;
        }
        if storage_read_syscall(0, slot(TR_FELTS + A_FELTS)).unwrap_syscall() != poseidon_hash_span(
            public_key,
        ) {
            return false;
        }
        let tr = read_slots(0, TR_FELTS);
        let a_hat = read_slots(TR_FELTS, TR_FELTS + A_FELTS);
        verify_cached(message_hash, public_key, signature, tr.span(), a_hat.span())
    }
}

#[starknet::contract]
pub mod HybridMlDsa44Verifier {
    use crate::hybrid::HybridAccountComponent;
    use super::MlDsa44CachedVerifier;

    component!(path: HybridAccountComponent, storage: account, event: AccountEvent);

    #[abi(embed_v0)]
    impl VerifierImpl =
        HybridAccountComponent::VerifierKeyReadImpl<ContractState, MlDsa44CachedVerifier>;

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

#[starknet::contract]
pub mod MlDsa44KeySetup {
    use crate::hybrid::HybridAccountComponent;
    use crate::hybrid::HybridAccountComponent::InternalTrait;

    component!(path: HybridAccountComponent, storage: account, event: AccountEvent);

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

    /// Library-called by the account after it writes an ML-DSA-44 key.
    #[external(v0)]
    fn setup_pq_key(ref self: ContractState) {
        super::write_cache(self.account.read_falcon_public_key_once().span());
    }
}
