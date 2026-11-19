//! ARCH-01: PQ-only mode on `HybridMigratableAccountV2`, entered and left with `set_pq_key` and a
//! Falcon-only verifier class (`FalconOnlyVerifierPfSmall`, `FalconOnlyVerifierFalcon1024`). Run
//! as transactions, as in tests_scheme.cairo.
//!
//! Signatures: the Falcon half of the existing hybrid fixtures (`falcon_sig()` is the Falcon half
//! of `hybrid_sig()`), plus `pq_only_proof()` (tests_pq_only_fixture.cairo).

use starknet::account::Call;
use starknet::{ClassHash, ContractAddress, SyscallResultTrait};
use crate::hybrid::{FalconOnlyVerifierFalcon1024, FalconOnlyVerifierPfSmall};
use crate::migratable_v2::HybridMigratableAccountV2::{
    INCOMPATIBLE_VERIFIER, INVALID_PROOF, ONLY_SELF,
};
use crate::migratable_v2::{IMigratableV2Dispatcher, IMigratableV2DispatcherTrait};
use crate::tests_falcon1024_fixture::{falcon1024_pk, falcon1024_rotation_proof, falcon1024_sig};
use crate::tests_migration::hybrid_sig;
use crate::tests_pq_only_fixture::{PQ_ONLY_ROTATION_HASH, pq_only_proof};
use crate::tests_rotation_fixture::{ecdsa_rotation_proof, falcon_rotation_proof};
use crate::tests_scheme::{
    assert_reverts_with, assert_unchanged, set_pq_key_call, shake, transact, upgrade_call,
    v1_account, v2_account,
};
use crate::tests_wallets_fixture::{
    ECDSA_PK, ECDSA_R, ECDSA_S, REGISTRATION_HASH, WRONG_ECDSA_PK, WRONG_ECDSA_R, WRONG_ECDSA_S,
    falcon_pk, falcon_sig,
};
use crate::utils::execution::INVALID_SIGNATURE;
use crate::utils::interface::{IHybridAccountDispatcher, IHybridAccountDispatcherTrait};

const MSG: felt252 = REGISTRATION_HASH;

fn pq_only_512() -> ClassHash {
    FalconOnlyVerifierPfSmall::TEST_CLASS_HASH
}

fn pq_only_1024() -> ClassHash {
    FalconOnlyVerifierFalcon1024::TEST_CLASS_HASH
}

/// A hybrid signature without its two ECDSA felts.
fn falcon_half(sig: Array<felt252>) -> Array<felt252> {
    let span = sig.span();
    let mut out = array![];
    out.append_span(span.slice(2, span.len() - 2));
    out
}

fn enter_call(account: ContractAddress) -> Call {
    set_pq_key_call(account, falcon_pk(), pq_only_512(), 0.try_into().unwrap(), pq_only_proof())
}

/// A V2 account on Falcon-512 key A, switched to PQ-only by a hybrid-signed `set_pq_key`.
fn pq_only_account() -> ContractAddress {
    let account = v2_account();
    transact(account, array![enter_call(account)], hybrid_sig()).unwrap_syscall();
    account
}

fn check(account: ContractAddress, hash: felt252, signature: Array<felt252>) -> felt252 {
    IHybridAccountDispatcher { contract_address: account }.is_valid_signature(hash, signature)
}

/// PQ-only on key A: Falcon-only passes, hybrid and ECDSA-only are refused, in a signature check
/// and in a transaction.
fn assert_pq_only(account: ContractAddress) {
    let m = IMigratableV2Dispatcher { contract_address: account };
    assert_eq!(m.get_verifier_class_hash(), pq_only_512());
    assert_eq!(m.get_falcon_public_key(), falcon_pk());
    assert_eq!(check(account, MSG, falcon_sig()), starknet::VALIDATED);
    assert_eq!(check(account, MSG, hybrid_sig()), 0);
    assert_eq!(check(account, MSG, array![ECDSA_R, ECDSA_S]), 0);
    transact(account, array![], falcon_sig()).unwrap_syscall();
    assert_reverts_with(transact(account, array![], hybrid_sig()), INVALID_SIGNATURE);
    assert_reverts_with(transact(account, array![], array![ECDSA_R, ECDSA_S]), INVALID_SIGNATURE);
}

// ---------------------------------------------------------------- entering PQ-only

#[test]
fn hybrid_account_enters_pq_only_and_keeps_its_keys() {
    let account = pq_only_account();
    assert_pq_only(account);
    // The ECDSA key is kept, unread.
    assert_eq!(
        IMigratableV2Dispatcher { contract_address: account }.get_ecdsa_public_key(), ECDSA_PK,
    );
}

#[test]
fn v1_account_enters_pq_only_in_one_transaction() {
    let account = v1_account();
    transact(account, array![upgrade_call(account), enter_call(account)], hybrid_sig())
        .unwrap_syscall();
    assert_pq_only(account);
}

#[test]
fn ecdsa_only_transaction_cannot_enter_pq_only() {
    let account = v2_account();
    assert_reverts_with(
        transact(account, array![enter_call(account)], array![ECDSA_R, ECDSA_S]), INVALID_SIGNATURE,
    );
    assert_unchanged(account);
}

#[test]
fn falcon_only_transaction_cannot_enter_pq_only() {
    let account = v2_account();
    assert_reverts_with(
        transact(account, array![enter_call(account)], falcon_sig()), INVALID_SIGNATURE,
    );
    assert_unchanged(account);
}

#[test]
fn wrong_key_switch_reverts() {
    // Falcon key B's proof (over rotation_hash(ECDSA_PK, key B)) offered for key A.
    let account = v2_account();
    let call = set_pq_key_call(
        account,
        falcon_pk(),
        pq_only_512(),
        0.try_into().unwrap(),
        falcon_half(falcon_rotation_proof()),
    );
    assert_reverts_with(transact(account, array![call], hybrid_sig()), INVALID_PROOF);
    assert_unchanged(account);
}

#[test]
fn hybrid_proof_does_not_open_pq_only() {
    // The right Falcon signature with two ECDSA felts in front: the PQ-only verifier refuses it.
    let account = v2_account();
    let mut proof = array![ECDSA_R, ECDSA_S];
    proof.append_span(pq_only_proof().span());
    let call = set_pq_key_call(account, falcon_pk(), pq_only_512(), 0.try_into().unwrap(), proof);
    assert_reverts_with(transact(account, array![call], hybrid_sig()), INVALID_PROOF);
    assert_unchanged(account);
}

#[test]
fn raw_verifier_switch_to_pq_only_reverts() {
    // set_verifier_class_hash checks this hybrid transaction's own signature through the new class.
    let account = v2_account();
    let call = Call {
        to: account,
        selector: selector!("set_verifier_class_hash"),
        calldata: array![pq_only_512().into()].span(),
    };
    assert_reverts_with(transact(account, array![call], hybrid_sig()), INCOMPATIBLE_VERIFIER);
    assert_unchanged(account);
}

#[test]
fn pq_only_proof_signs_the_rotation_hash() {
    assert_eq!(
        PQ_ONLY_ROTATION_HASH, crate::migratable::rotation_hash(ECDSA_PK, falcon_pk().span()),
    );
}

// ---------------------------------------------------------------- leaving PQ-only

/// Back to hybrid with a new ECDSA key (WRONG_ECDSA_PK), in one Falcon-only transaction:
/// `rotate_ecdsa_public_key`'s proof is checked by the PQ-only verifier (Falcon alone), then
/// `set_pq_key`'s by the hybrid verifier, which proves the new ECDSA key. Both sign
/// rotation_hash(WRONG_ECDSA_PK, falcon_pk()).
fn exit_calls(account: ContractAddress) -> Array<Call> {
    let mut rotate = array![WRONG_ECDSA_PK];
    Serde::serialize(@falcon_half(ecdsa_rotation_proof()), ref rotate);
    array![
        Call {
            to: account, selector: selector!("rotate_ecdsa_public_key"), calldata: rotate.span(),
        },
        set_pq_key_call(
            account, falcon_pk(), shake(), 0.try_into().unwrap(), ecdsa_rotation_proof(),
        ),
    ]
}

#[test]
fn pq_only_returns_to_hybrid_with_a_new_ecdsa_key() {
    let account = pq_only_account();
    transact(account, exit_calls(account), falcon_sig()).unwrap_syscall();

    let m = IMigratableV2Dispatcher { contract_address: account };
    assert_eq!(m.get_verifier_class_hash(), shake());
    assert_eq!(m.get_ecdsa_public_key(), WRONG_ECDSA_PK);
    let new_hybrid = {
        let mut sig = array![WRONG_ECDSA_R, WRONG_ECDSA_S];
        sig.append_span(falcon_sig().span());
        sig
    };
    assert_eq!(check(account, MSG, new_hybrid.clone()), starknet::VALIDATED);
    transact(account, array![], new_hybrid).unwrap_syscall();
    // Falcon alone and the old ECDSA key are refused.
    assert_reverts_with(transact(account, array![], falcon_sig()), INVALID_SIGNATURE);
    assert_reverts_with(transact(account, array![], hybrid_sig()), INVALID_SIGNATURE);
}

#[test]
fn return_to_hybrid_without_proving_the_new_ecdsa_key_reverts() {
    // set_pq_key back to hybrid with a proof by the OLD ECDSA key: the account now holds the new
    // one, so the hybrid verifier refuses it and the whole transaction reverts.
    let account = pq_only_account();
    let mut calls = exit_calls(account);
    let rotate = calls.pop_front().unwrap();
    let mut bad_proof = array![ECDSA_R, ECDSA_S];
    bad_proof.append_span(falcon_half(ecdsa_rotation_proof()).span());
    let call = set_pq_key_call(account, falcon_pk(), shake(), 0.try_into().unwrap(), bad_proof);
    assert_reverts_with(transact(account, array![rotate, call], falcon_sig()), INVALID_PROOF);
    assert_pq_only(account);
    assert_eq!(
        IMigratableV2Dispatcher { contract_address: account }.get_ecdsa_public_key(), ECDSA_PK,
    );
}

#[test]
fn hybrid_signed_transaction_cannot_leave_pq_only() {
    let account = pq_only_account();
    assert_reverts_with(transact(account, exit_calls(account), hybrid_sig()), INVALID_SIGNATURE);
    assert_pq_only(account);
}

#[test]
fn outsider_cannot_switch_mode() {
    let account = pq_only_account();
    starknet::testing::set_contract_address(0x1234.try_into().unwrap());
    let result = starknet::syscalls::call_contract_syscall(
        account, selector!("set_pq_key"), enter_call(account).calldata,
    );
    assert_reverts_with(result, ONLY_SELF);
}

// ---------------------------------------------------------------- Falcon-1024

#[test]
fn falcon1024_pq_only() {
    let account = v2_account();
    let call = set_pq_key_call(
        account,
        falcon1024_pk(),
        pq_only_1024(),
        0.try_into().unwrap(),
        falcon_half(falcon1024_rotation_proof()),
    );
    transact(account, array![call], hybrid_sig()).unwrap_syscall();
    let m = IMigratableV2Dispatcher { contract_address: account };
    assert_eq!(m.get_verifier_class_hash(), pq_only_1024());
    assert_eq!(m.get_falcon_public_key(), falcon1024_pk());

    assert_eq!(check(account, MSG, falcon_half(falcon1024_sig())), starknet::VALIDATED);
    assert_eq!(check(account, MSG, falcon1024_sig()), 0);
    assert_eq!(check(account, MSG, falcon_sig()), 0);
    transact(account, array![], falcon_half(falcon1024_sig())).unwrap_syscall();
    assert_reverts_with(transact(account, array![], falcon1024_sig()), INVALID_SIGNATURE);
}

#[test]
fn falcon512_key_under_falcon1024_pq_only_reverts() {
    let account = v2_account();
    let call = set_pq_key_call(
        account, falcon_pk(), pq_only_1024(), 0.try_into().unwrap(), pq_only_proof(),
    );
    assert_reverts_with(transact(account, array![call], hybrid_sig()), INVALID_PROOF);
    assert_unchanged(account);
}
