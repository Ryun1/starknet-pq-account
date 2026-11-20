use pq_hybrid::migratable_v2::{IMigratableV2Dispatcher, IMigratableV2DispatcherTrait};
use pq_hybrid::utils::interface::{IHybridAccountDispatcher, IHybridAccountDispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    start_cheat_signature, start_cheat_transaction_hash,
};
use starknet::ClassHash;
use crate::fixtures::tests_falcon1024_fixture::{falcon1024_pk, falcon1024_sig};
use crate::fixtures::tests_pq_only_fixture::pq_only_proof;
use crate::fixtures::tests_wallets_fixture::{
    ECDSA_PK, ECDSA_R, ECDSA_S, REGISTRATION_HASH, falcon_pk, falcon_sig,
};

fn class_hash(name: ByteArray) -> ClassHash {
    *declare(name).unwrap().contract_class().class_hash
}

/// A HybridMigratableAccountV2 on `verifier`, as the current transaction (hash, signature).
fn account(
    verifier: ByteArray, pq_key: Array<felt252>, signature: Array<felt252>,
) -> IHybridAccountDispatcher {
    let mut calldata = array![ECDSA_PK];
    Serde::serialize(@pq_key, ref calldata);
    calldata.append(class_hash(verifier).into());
    calldata.append(0);
    let (contract_address, _) = declare("HybridMigratableAccountV2")
        .unwrap()
        .contract_class()
        .deploy(@calldata)
        .unwrap();
    start_cheat_transaction_hash(contract_address, REGISTRATION_HASH);
    start_cheat_signature(contract_address, signature.span());
    IHybridAccountDispatcher { contract_address }
}

fn hybrid_512() -> Array<felt252> {
    let mut sig = array![ECDSA_R, ECDSA_S];
    sig.append_span(falcon_sig().span());
    sig
}

fn falcon_only_1024() -> Array<felt252> {
    let sig = falcon1024_sig();
    let mut out = array![];
    out.append_span(sig.span().slice(2, sig.len() - 2));
    out
}

fn validate(a: IHybridAccountDispatcher) {
    assert_eq!(a.__validate__(array![]), starknet::VALIDATED);
}

#[test]
fn setup_validate_hybrid_512() {
    let _ = account("HybridShakeVerifierPfSmallKeyRead", falcon_pk(), hybrid_512());
}

#[test]
fn validate_hybrid_512() {
    validate(account("HybridShakeVerifierPfSmallKeyRead", falcon_pk(), hybrid_512()));
}

#[test]
fn setup_validate_pq_only_512() {
    let _ = account("FalconOnlyVerifierPfSmall", falcon_pk(), falcon_sig());
}

#[test]
fn validate_pq_only_512() {
    validate(account("FalconOnlyVerifierPfSmall", falcon_pk(), falcon_sig()));
}

#[test]
fn setup_validate_hybrid_1024() {
    let _ = account("HybridShakeVerifierFalcon1024", falcon1024_pk(), falcon1024_sig());
}

#[test]
fn validate_hybrid_1024() {
    validate(account("HybridShakeVerifierFalcon1024", falcon1024_pk(), falcon1024_sig()));
}

#[test]
fn setup_validate_pq_only_1024() {
    let _ = account("FalconOnlyVerifierFalcon1024", falcon1024_pk(), falcon_only_1024());
}

#[test]
fn validate_pq_only_1024() {
    validate(account("FalconOnlyVerifierFalcon1024", falcon1024_pk(), falcon_only_1024()));
}

/// `set_pq_key` from hybrid Falcon-512 to PQ-only Falcon-512, same key (in `__execute__`).
fn enter_setup() -> (IMigratableV2Dispatcher, ClassHash) {
    let a = account("HybridShakeVerifierPfSmallKeyRead", falcon_pk(), hybrid_512());
    start_cheat_caller_address(a.contract_address, a.contract_address);
    (IMigratableV2Dispatcher { contract_address: a.contract_address }, class_hash("FalconOnlyVerifierPfSmall"))
}

#[test]
fn setup_enter_pq_only_512() {
    let _ = enter_setup();
}

#[test]
fn enter_pq_only_512() {
    let (m, pq_only) = enter_setup();
    m.set_pq_key(falcon_pk(), pq_only, 0.try_into().unwrap(), pq_only_proof());
}
