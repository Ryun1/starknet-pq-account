//! ARCH-02: `HybridDormantAccount`. Transactions run as in tests_scheme.cairo (`__validate__` with
//! the signature, then `__execute__`).
//!
//! Activation proofs use the mock scheme (3-felt key, signature `[hash + key[0]]`, no ECDSA half):
//! the activation hash binds the account address, which changes with the class hash, so a real
//! Falcon fixture would have to be regenerated on every edit. The real SHAKE-256 Falcon-512
//! verifier is still exercised on the rejection side (`real_verifier_rejects_a_proof_over_*`), and
//! the proof check is the same library call as V2's.

use starknet::account::Call;
use starknet::syscalls::{deploy_syscall, get_class_hash_at_syscall};
use starknet::{ClassHash, ContractAddress, SyscallResult, SyscallResultTrait};
use crate::dormant::HybridDormantAccount::{
    ALREADY_COMMITTED, INVALID_PROOF, NOTHING_PENDING, NOT_DORMANT, NOT_REGISTERED,
    SELF_CALL_BLOCKED, STATE_CHANGED, TOO_EARLY, WRONG_KEY, ZERO_COMMITMENT,
};
use crate::dormant::{
    DORMANT_DELAY, HybridDormantAccount, IDormantDispatcher, IDormantDispatcherTrait,
    activation_hash, commitment_hash,
};
use crate::hybrid::HybridShakeAccount;
use crate::migratable::LegacyOzLikeAccount::{ILegacyDispatcher, ILegacyDispatcherTrait};
use crate::migratable_v2::{
    HybridMigratableAccountV2, IMigratableV2Dispatcher, IMigratableV2DispatcherTrait,
};
use crate::tests_migration::{deploy_legacy, hybrid_sig};
use crate::tests_scheme::{
    KeyRewritingSetup, MockSchemeSetup, MockSchemeVerifier, assert_reverts_with, class, mock_key,
    mock_sig, transact,
};
use crate::tests_wallets_fixture::{
    ECDSA_PK, ECDSA_R, ECDSA_S, REGISTRATION_HASH, WRONG_ECDSA_R, WRONG_ECDSA_S, falcon_pk,
};
use crate::utils::execution::INVALID_SIGNATURE;
use crate::utils::interface::{IHybridAccountDispatcher, IHybridAccountDispatcherTrait};

/// The hash `transact` sets; ECDSA_R/ECDSA_S sign it with ECDSA_PK.
const MSG: felt252 = REGISTRATION_HASH;

fn dormant_class() -> ClassHash {
    HybridDormantAccount::TEST_CLASS_HASH
}

fn mock_verifier() -> ClassHash {
    MockSchemeVerifier::TEST_CLASS_HASH
}

fn mock_setup() -> ClassHash {
    MockSchemeSetup::TEST_CLASS_HASH
}

fn other_key() -> Array<felt252> {
    array![44, 55, 66]
}

fn commitment_of(key: Array<felt252>) -> felt252 {
    commitment_hash(mock_verifier(), mock_setup(), key.span())
}

fn ecdsa_sig() -> Array<felt252> {
    array![ECDSA_R, ECDSA_S]
}

fn deploy_with(commitment: felt252) -> SyscallResult<(ContractAddress, Span<felt252>)> {
    deploy_syscall(dormant_class(), 0, array![ECDSA_PK, commitment].span(), false)
}

/// A fresh dormant account committed to the mock key.
fn dormant() -> ContractAddress {
    let (address, _) = deploy_with(commitment_of(mock_key())).unwrap_syscall();
    address
}

fn d(account: ContractAddress) -> IDormantDispatcher {
    IDormantDispatcher { contract_address: account }
}

fn chain_id() -> felt252 {
    starknet::get_tx_info().unbox().chain_id
}

/// The proof the owner of `key` (mock scheme) gives to activate `account`.
fn proof_for(account: ContractAddress, key: Array<felt252>) -> Array<felt252> {
    let hash = activation_hash(chain_id(), account, ECDSA_PK, key.span());
    array![hash + *key.at(0)]
}

fn activate_call(
    account: ContractAddress,
    key: Array<felt252>,
    verifier: ClassHash,
    setup: ClassHash,
    proof: Array<felt252>,
) -> Call {
    let mut calldata = array![];
    Serde::serialize(@key, ref calldata);
    calldata.append(verifier.into());
    calldata.append(setup.into());
    Serde::serialize(@proof, ref calldata);
    Call { to: account, selector: selector!("activate"), calldata: calldata.span() }
}

fn self_call(account: ContractAddress, selector: felt252, calldata: Array<felt252>) -> Call {
    Call { to: account, selector, calldata: calldata.span() }
}

/// `activate` sent by a third party (not a transaction of the account).
fn activate_from_outsider(
    account: ContractAddress,
    key: Array<felt252>,
    verifier: ClassHash,
    setup: ClassHash,
    proof: Array<felt252>,
) -> SyscallResult<Span<felt252>> {
    starknet::testing::set_contract_address(0x1234.try_into().unwrap());
    let call = activate_call(account, key, verifier, setup, proof);
    starknet::syscalls::call_contract_syscall(call.to, call.selector, call.calldata)
}

fn activate_mock(account: ContractAddress) {
    activate_from_outsider(
        account, mock_key(), mock_verifier(), mock_setup(), proof_for(account, mock_key()),
    )
        .unwrap_syscall();
}

fn propose(account: ContractAddress, commitment: felt252) {
    let call = self_call(account, selector!("propose_commitment"), array![commitment]);
    transact(account, array![call], ecdsa_sig()).unwrap_syscall();
}

fn assert_still_dormant(account: ContractAddress, commitment: felt252) {
    assert!(d(account).is_dormant());
    assert_eq!(d(account).get_commitment(), commitment);
    assert!(!d(account).is_falcon_registered());
    assert_eq!(d(account).get_falcon_public_key(), array![]);
}

// ---------------------------------------------------------------- dormant validation

#[test]
fn dormant_account_validates_with_ecdsa_alone() {
    let account = dormant();
    assert_still_dormant(account, commitment_of(mock_key()));
    assert_eq!(d(account).get_ecdsa_public_key(), ECDSA_PK);
    transact(account, array![], ecdsa_sig()).unwrap_syscall();
    let a = IHybridAccountDispatcher { contract_address: account };
    assert_eq!(a.is_valid_signature(MSG, ecdsa_sig()), starknet::VALIDATED);
    assert_eq!(a.is_valid_signature(MSG, array![WRONG_ECDSA_R, WRONG_ECDSA_S]), 0);
}

#[test]
fn dormant_account_rejects_a_wrong_ecdsa_signature() {
    let account = dormant();
    assert_reverts_with(
        transact(account, array![], array![WRONG_ECDSA_R, WRONG_ECDSA_S]), INVALID_SIGNATURE,
    );
}

#[test]
fn dormant_account_blocks_ecdsa_only_self_calls() {
    let account = dormant();
    let blocked = array![
        self_call(account, selector!("upgrade"), array![dormant_class().into()]),
        self_call(account, selector!("commit"), array![commitment_of(other_key())]),
        self_call(account, selector!("apply_commitment"), array![]),
        self_call(account, selector!("rotate_ecdsa_public_key"), array![1, 0]),
        self_call(account, selector!("set_verifier_class_hash"), array![1]),
    ];
    for call in blocked {
        assert_reverts_with(transact(account, array![call], ecdsa_sig()), SELF_CALL_BLOCKED);
    }
    // An allowed self-call does not carry a blocked one.
    let calls = array![
        self_call(account, selector!("propose_commitment"), array![commitment_of(other_key())]),
        self_call(account, selector!("upgrade"), array![dormant_class().into()]),
    ];
    assert_reverts_with(transact(account, calls, ecdsa_sig()), SELF_CALL_BLOCKED);
    assert_still_dormant(account, commitment_of(mock_key()));
    assert_eq!(d(account).get_pending_commitment(), (0, 0));
    assert_eq!(get_class_hash_at_syscall(account).unwrap_syscall(), dormant_class());
}

#[test]
fn zero_commitment_is_refused() {
    assert!(deploy_with(0).is_err());
    let account = dormant();
    let call = self_call(account, selector!("propose_commitment"), array![0]);
    assert_reverts_with(transact(account, array![call], ecdsa_sig()), ZERO_COMMITMENT);
}

// ---------------------------------------------------------------- activation

#[test]
fn activation_switches_to_hybrid_and_refuses_ecdsa_alone() {
    let account = dormant();
    activate_mock(account);

    assert!(!d(account).is_dormant());
    assert!(d(account).is_falcon_registered());
    assert_eq!(d(account).get_commitment(), 0);
    assert_eq!(d(account).get_falcon_public_key(), mock_key());
    assert_eq!(d(account).get_verifier_class_hash(), mock_verifier());
    assert_eq!(d(account).get_ecdsa_public_key(), ECDSA_PK);

    assert_reverts_with(transact(account, array![], ecdsa_sig()), INVALID_SIGNATURE);
    transact(account, array![], mock_sig(MSG)).unwrap_syscall();
    let a = IHybridAccountDispatcher { contract_address: account };
    assert_eq!(a.is_valid_signature(MSG, ecdsa_sig()), 0);
    assert_eq!(a.is_valid_signature(MSG, mock_sig(MSG)), starknet::VALIDATED);
}

#[test]
fn owner_can_activate_from_the_account_itself() {
    let account = dormant();
    let call = activate_call(
        account, mock_key(), mock_verifier(), mock_setup(), proof_for(account, mock_key()),
    );
    transact(account, array![call], ecdsa_sig()).unwrap_syscall();
    assert!(d(account).is_falcon_registered());
}

#[test]
fn activation_with_a_key_that_was_not_committed_reverts() {
    let account = dormant();
    let result = activate_from_outsider(
        account, other_key(), mock_verifier(), mock_setup(), proof_for(account, other_key()),
    );
    assert_reverts_with(result, WRONG_KEY);
    assert_still_dormant(account, commitment_of(mock_key()));
}

#[test]
fn activation_with_another_verifier_or_setup_reverts() {
    let account = dormant();
    let proof = proof_for(account, mock_key());
    let shake = HybridShakeAccount::TEST_CLASS_HASH;
    assert_reverts_with(
        activate_from_outsider(account, mock_key(), shake, mock_setup(), proof.clone()), WRONG_KEY,
    );
    assert_reverts_with(
        activate_from_outsider(account, mock_key(), mock_verifier(), class(0), proof), WRONG_KEY,
    );
    assert_still_dormant(account, commitment_of(mock_key()));
}

#[test]
fn activation_with_a_bad_proof_reverts_and_stays_dormant() {
    let account = dormant();
    let mut proof = proof_for(account, mock_key());
    let bad = array![proof.pop_front().unwrap() + 1];
    assert_reverts_with(
        activate_from_outsider(account, mock_key(), mock_verifier(), mock_setup(), bad),
        INVALID_PROOF,
    );
    assert_still_dormant(account, commitment_of(mock_key()));
    transact(account, array![], ecdsa_sig()).unwrap_syscall();
}

#[test]
fn a_proof_for_another_account_does_not_activate_this_one() {
    let account = dormant();
    let (other, _) = deploy_syscall(
        dormant_class(), 1, array![ECDSA_PK, commitment_of(mock_key())].span(), false,
    )
        .unwrap_syscall();
    let result = activate_from_outsider(
        account, mock_key(), mock_verifier(), mock_setup(), proof_for(other, mock_key()),
    );
    assert_reverts_with(result, INVALID_PROOF);
    assert_still_dormant(account, commitment_of(mock_key()));
}

#[test]
fn activation_is_one_shot() {
    let account = dormant();
    activate_mock(account);
    let result = activate_from_outsider(
        account, mock_key(), mock_verifier(), mock_setup(), proof_for(account, mock_key()),
    );
    assert_reverts_with(result, NOT_DORMANT);
}

#[test]
fn real_verifier_rejects_a_proof_over_another_hash() {
    // Committed to the SHAKE-256 Falcon-512 key and verifier; the hybrid signature over the
    // registration hash is a valid signature by both keys, but not over the activation hash.
    let shake = HybridShakeAccount::TEST_CLASS_HASH;
    let commitment = commitment_hash(shake, class(0), falcon_pk().span());
    let (account, _) = deploy_with(commitment).unwrap_syscall();
    let result = activate_from_outsider(account, falcon_pk(), shake, class(0), hybrid_sig());
    assert_reverts_with(result, INVALID_PROOF);
    assert_still_dormant(account, commitment);
}

#[test]
fn a_setup_that_rewrites_the_keys_reverts_activation() {
    let setup = KeyRewritingSetup::TEST_CLASS_HASH;
    let commitment = commitment_hash(mock_verifier(), setup, mock_key().span());
    let (account, _) = deploy_with(commitment).unwrap_syscall();
    let result = activate_from_outsider(
        account, mock_key(), mock_verifier(), setup, proof_for(account, mock_key()),
    );
    assert_reverts_with(result, STATE_CHANGED);
    assert_still_dormant(account, commitment);
}

// ---------------------------------------------------------------- time-locked rotation and veto

#[test]
fn proposed_commitment_applies_only_after_the_delay() {
    let account = dormant();
    starknet::testing::set_block_timestamp(1000);
    propose(account, commitment_of(other_key()));
    let ready_at = 1000 + DORMANT_DELAY;
    assert_eq!(d(account).get_pending_commitment(), (commitment_of(other_key()), ready_at));

    starknet::testing::set_block_timestamp(ready_at - 1);
    assert_reverts_with(
        starknet::syscalls::call_contract_syscall(
            account, selector!("apply_commitment"), array![].span(),
        ),
        TOO_EARLY,
    );
    assert_still_dormant(account, commitment_of(mock_key()));

    starknet::testing::set_block_timestamp(ready_at);
    d(account).apply_commitment();
    assert_still_dormant(account, commitment_of(other_key()));
    assert_eq!(d(account).get_pending_commitment(), (0, 0));

    // The old key no longer opens it; the new one does.
    let result = activate_from_outsider(
        account, mock_key(), mock_verifier(), mock_setup(), proof_for(account, mock_key()),
    );
    assert_reverts_with(result, WRONG_KEY);
    activate_from_outsider(
        account, other_key(), mock_verifier(), mock_setup(), proof_for(account, other_key()),
    )
        .unwrap_syscall();
    assert_eq!(d(account).get_falcon_public_key(), other_key());
}

#[test]
fn apply_with_nothing_pending_reverts() {
    let account = dormant();
    assert_reverts_with(
        starknet::syscalls::call_contract_syscall(
            account, selector!("apply_commitment"), array![].span(),
        ),
        NOTHING_PENDING,
    );
}

#[test]
fn a_new_proposal_restarts_the_clock() {
    let account = dormant();
    propose(account, commitment_of(other_key()));
    starknet::testing::set_block_timestamp(DORMANT_DELAY - 1);
    propose(account, commitment_of(array![77, 88, 99]));
    starknet::testing::set_block_timestamp(DORMANT_DELAY);
    assert_reverts_with(
        starknet::syscalls::call_contract_syscall(
            account, selector!("apply_commitment"), array![].span(),
        ),
        TOO_EARLY,
    );
}

#[test]
fn activation_vetoes_a_pending_proposal() {
    let account = dormant();
    propose(account, commitment_of(other_key()));
    activate_mock(account);
    assert_eq!(d(account).get_pending_commitment(), (0, 0));
    starknet::testing::set_block_timestamp(DORMANT_DELAY);
    assert_reverts_with(
        starknet::syscalls::call_contract_syscall(
            account, selector!("apply_commitment"), array![].span(),
        ),
        NOT_DORMANT,
    );
    assert_eq!(d(account).get_falcon_public_key(), mock_key());
}

// ---------------------------------------------------------------- bootstrap and upgrade

#[test]
fn oz_style_account_upgrades_and_commits() {
    let account = deploy_legacy();
    starknet::testing::set_contract_address(account);
    ILegacyDispatcher { contract_address: account }.upgrade(dormant_class());
    // Upgraded alone: unregistered, and only a single `commit` self-call validates.
    assert!(!d(account).is_dormant());
    assert_reverts_with(transact(account, array![], ecdsa_sig()), NOT_REGISTERED);
    let two = array![
        self_call(account, selector!("commit"), array![commitment_of(mock_key())]),
        self_call(account, selector!("commit"), array![commitment_of(mock_key())]),
    ];
    assert_reverts_with(transact(account, two, ecdsa_sig()), NOT_REGISTERED);

    let call = self_call(account, selector!("commit"), array![commitment_of(mock_key())]);
    transact(account, array![call], ecdsa_sig()).unwrap_syscall();
    assert_still_dormant(account, commitment_of(mock_key()));
    activate_mock(account);
    assert!(d(account).is_falcon_registered());
}

#[test]
fn commit_on_a_dormant_account_reverts() {
    let account = dormant();
    starknet::testing::set_contract_address(account);
    let result = starknet::syscalls::call_contract_syscall(
        account, selector!("commit"), array![commitment_of(other_key())].span(),
    );
    assert_reverts_with(result, ALREADY_COMMITTED);
}

#[test]
fn active_account_upgrades_to_v2_and_keeps_its_keys() {
    let account = dormant();
    activate_mock(account);
    let v2 = HybridMigratableAccountV2::TEST_CLASS_HASH;
    let call = self_call(account, selector!("upgrade"), array![v2.into()]);
    transact(account, array![call], mock_sig(MSG)).unwrap_syscall();
    assert_eq!(get_class_hash_at_syscall(account).unwrap_syscall(), v2);
    let m = IMigratableV2Dispatcher { contract_address: account };
    assert!(m.is_falcon_registered());
    assert_eq!(m.get_falcon_public_key(), mock_key());
    assert_eq!(m.get_verifier_class_hash(), mock_verifier());
    assert_eq!(m.get_ecdsa_public_key(), ECDSA_PK);
    transact(account, array![], mock_sig(MSG)).unwrap_syscall();
    assert_reverts_with(transact(account, array![], ecdsa_sig()), INVALID_SIGNATURE);
}
