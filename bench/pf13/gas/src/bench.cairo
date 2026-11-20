use pq_hybrid::migratable_v2::{IMigratableV2Dispatcher, IMigratableV2DispatcherTrait};
use pq_hybrid::utils::interface::{IHybridAccountDispatcher, IHybridAccountDispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    start_cheat_signature, start_cheat_transaction_hash,
};
use starknet::{ClassHash, ContractAddress};
use crate::legacy::LegacyOzLikeAccount::{ILegacyDispatcher, ILegacyDispatcherTrait};

pub fn class_hash(name: ByteArray) -> ClassHash {
    *declare(name).unwrap().contract_class().class_hash
}

pub fn mldsa() -> ClassHash {
    class_hash("HybridMlDsa44Verifier")
}

pub fn mldsa_setup() -> ClassHash {
    class_hash("MlDsa44KeySetup")
}

pub fn falcon512() -> ClassHash {
    class_hash("HybridShakeVerifierPfSmallKeyRead")
}

pub fn hybrid(r: felt252, s: felt252, falcon: Span<felt252>) -> Array<felt252> {
    let mut sig = array![r, s];
    sig.append_span(falcon);
    sig
}

/// A `HybridMigratableAccountV2` deployed with both keys, `verifier` and `setup` (zero for none):
/// the same storage as an account moved to that scheme with `set_pq_key` or migrated straight to it.
pub fn account(
    verifier: ClassHash, setup: felt252, ecdsa_public_key: felt252, pq_public_key: Span<felt252>,
) -> IHybridAccountDispatcher {
    let mut calldata = array![ecdsa_public_key];
    Serde::serialize(@pq_public_key, ref calldata);
    calldata.append(verifier.into());
    calldata.append(setup);
    let (contract_address, _) = declare("HybridMigratableAccountV2")
        .unwrap()
        .contract_class()
        .deploy(@calldata)
        .unwrap();
    IHybridAccountDispatcher { contract_address }
}

/// Makes `account` see `hash` and `signature` as the current transaction's.
pub fn as_transaction(account: ContractAddress, hash: felt252, signature: Span<felt252>) {
    start_cheat_transaction_hash(account, hash);
    start_cheat_signature(account, signature);
}

pub fn validate(account: IHybridAccountDispatcher) {
    assert_eq!(account.__validate__(array![]), starknet::VALIDATED);
}

pub fn validate_declare(account: IHybridAccountDispatcher) {
    assert_eq!(account.__validate_declare__(0x1234), starknet::VALIDATED);
}

pub fn as_self(account: ContractAddress) -> IMigratableV2Dispatcher {
    start_cheat_caller_address(account, account);
    IMigratableV2Dispatcher { contract_address: account }
}

/// A legacy ECDSA account holding `public_key`, already upgraded to V2 (unregistered).
pub fn legacy_on_v2(public_key: felt252) -> ContractAddress {
    let (account, _) = declare("LegacyOzLikeAccount")
        .unwrap()
        .contract_class()
        .deploy(@array![public_key])
        .unwrap();
    start_cheat_caller_address(account, account);
    ILegacyDispatcher { contract_address: account }.upgrade(class_hash("HybridMigratableAccountV2"));
    account
}
