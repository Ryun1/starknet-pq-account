//! PF-13 step 1: `HybridMigratableAccountV2` and `set_pq_key`, run as transactions
//! (`__validate__` with the signature, then `__execute__`, as in tests_guard.cairo), so a failed
//! call returns an error and the test can check that nothing changed.
//!
//! Real signatures are the SHAKE-256 Falcon-512 fixtures. The second scheme is a mock with a
//! 3-felt key and no cryptography: it exercises the account (a key of another length, a setup
//! class, a proof checked by the new verifier), not a verifier. Falcon-1024 (PF-14) is the first
//! real second scheme: 57-felt key, `HybridShakeVerifierFalcon1024`, no setup class
//! (tests_falcon1024_fixture.cairo). ML-DSA-44 (PF-13) adds another.

use starknet::account::Call;
use starknet::syscalls::{call_contract_syscall, deploy_syscall, get_class_hash_at_syscall};
use starknet::{ClassHash, ContractAddress, SyscallResult, SyscallResultTrait};
use crate::hybrid::{HybridPoseidonAccount, HybridShakeAccount, HybridShakeVerifierFalcon1024};
use crate::migratable::LegacyOzLikeAccount::{ILegacyDispatcher, ILegacyDispatcherTrait};
use crate::migratable::{
    IMigratableDispatcher, IMigratableDispatcherTrait, LegacyOzLikeAccount, registration_hash,
    rotation_hash,
};
use crate::migratable_v2::{
    HybridMigratableAccountV2, IMigratableV2Dispatcher, IMigratableV2DispatcherTrait,
    MigrationDataV2,
};
use crate::tests_falcon1024_fixture::{
    F1024_ROTATION_HASH, falcon1024_pk, falcon1024_registration_proof, falcon1024_rotation_proof,
    falcon1024_sig,
};
use crate::mldsa::{HybridMlDsa44Verifier, MALFORMED_KEY, MlDsa44KeySetup};
use crate::tests_migration::{deploy_legacy, hybrid_sig, migrate};
use crate::tests_mldsa_fixture::{
    MLDSA_ROTATION_HASH, mldsa_pk, mldsa_pk_b, mldsa_registration_proof, mldsa_rotation_proof,
    mldsa_rotation_proof_b, mldsa_sig, mldsa_sig_b,
};
use crate::tests_rotation_fixture::{
    ECDSA_ROTATION_HASH, FALCON_ROTATION_HASH, ecdsa_rotation_proof, falcon_pk_b,
    falcon_rotation_proof,
};
use crate::tests_wallets::{
    Argent03LikeAccount, ArgentLikeAccount, IArgent03LikeDispatcher, IArgent03LikeDispatcherTrait,
    IArgentLikeDispatcher, IArgentLikeDispatcherTrait,
};
use crate::tests_wallets_fixture::{
    ECDSA_PK, ECDSA_R, ECDSA_S, REGISTRATION_HASH, WRONG_ECDSA_PK, falcon_pk,
};
use crate::utils::execution::INVALID_SIGNATURE;
use crate::utils::interface::{IHybridAccountDispatcher, IHybridAccountDispatcherTrait};

const MSG: felt252 = REGISTRATION_HASH;

/// The mock scheme: a 3-felt key; the signature of `hash` is `[hash + key[0]]`, accepted only
/// once `MockSchemeSetup` has stored key[0] (standing in for work derived from the key).
#[starknet::contract]
pub mod MockSchemeVerifier {
    use starknet::storage::{StoragePointerReadAccess, Vec, VecTrait};

    #[storage]
    struct Storage {
        falcon_public_key: Vec<felt252>,
        mock_cache: felt252,
    }

    #[external(v0)]
    fn is_valid_signature(self: @ContractState, hash: felt252, signature: Array<felt252>) -> felt252 {
        if self.falcon_public_key.len() != 3 || signature.len() != 1 {
            return 0;
        }
        let cache = self.mock_cache.read();
        if cache == self.falcon_public_key.at(0).read() && *signature.at(0) == hash + cache {
            starknet::VALIDATED
        } else {
            0
        }
    }
}

#[starknet::contract]
pub mod MockSchemeSetup {
    use starknet::storage::{
        MutableVecTrait, StoragePointerReadAccess, StoragePointerWriteAccess, Vec,
    };

    #[storage]
    struct Storage {
        falcon_public_key: Vec<felt252>,
        mock_cache: felt252,
    }

    #[external(v0)]
    fn setup_pq_key(ref self: ContractState) {
        self.mock_cache.write(self.falcon_public_key.at(0).read());
    }
}

/// A setup that also rewrites the mirrored classical key the verifiers read.
#[starknet::contract]
pub mod KeyRewritingSetup {
    use starknet::storage::{
        MutableVecTrait, StoragePointerReadAccess, StoragePointerWriteAccess, Vec,
    };

    #[storage]
    struct Storage {
        ecdsa_public_key: felt252,
        falcon_public_key: Vec<felt252>,
        mock_cache: felt252,
    }

    #[external(v0)]
    fn setup_pq_key(ref self: ContractState) {
        self.mock_cache.write(self.falcon_public_key.at(0).read());
        self.ecdsa_public_key.write('attacker');
    }
}

pub fn class(hash: felt252) -> ClassHash {
    hash.try_into().unwrap()
}

fn v2() -> ClassHash {
    HybridMigratableAccountV2::TEST_CLASS_HASH
}

pub fn shake() -> ClassHash {
    HybridShakeAccount::TEST_CLASS_HASH
}

fn falcon1024() -> ClassHash {
    HybridShakeVerifierFalcon1024::TEST_CLASS_HASH
}

fn mock_verifier() -> ClassHash {
    MockSchemeVerifier::TEST_CLASS_HASH
}

fn mock_setup() -> ClassHash {
    MockSchemeSetup::TEST_CLASS_HASH
}

pub fn mock_key() -> Array<felt252> {
    array![11, 22, 33]
}

pub fn mock_sig(hash: felt252) -> Array<felt252> {
    array![hash + 11]
}

fn mock_proof() -> Array<felt252> {
    mock_sig(rotation_hash(ECDSA_PK, mock_key().span()))
}

/// A migrated account on the earlier class: SHAKE verifier, Falcon key A.
pub fn v1_account() -> ContractAddress {
    let account = deploy_legacy();
    migrate(account);
    account
}

/// The same account after `upgrade` to V2 alone.
pub fn v2_account() -> ContractAddress {
    let account = v1_account();
    IMigratableDispatcher { contract_address: account }.upgrade(v2());
    account
}

pub fn upgrade_call(account: ContractAddress) -> Call {
    Call { to: account, selector: selector!("upgrade"), calldata: array![v2().into()].span() }
}

pub fn set_pq_key_call(
    account: ContractAddress, key: Array<felt252>, verifier: ClassHash, setup: ClassHash,
    proof: Array<felt252>,
) -> Call {
    let mut calldata = array![];
    Serde::serialize(@key, ref calldata);
    calldata.append(verifier.into());
    calldata.append(setup.into());
    Serde::serialize(@proof, ref calldata);
    Call { to: account, selector: selector!("set_pq_key"), calldata: calldata.span() }
}

/// One transaction from `account` with hash MSG: the protocol runs `__validate__`, then
/// `__execute__`.
pub fn transact(account: ContractAddress, calls: Array<Call>, signature: Array<felt252>) -> SyscallResult<Span<felt252>> {
    starknet::testing::set_contract_address(0.try_into().unwrap());
    starknet::testing::set_version(3);
    starknet::testing::set_transaction_hash(MSG);
    starknet::testing::set_signature(signature.span());
    let mut data = array![];
    Serde::serialize(@calls, ref data);
    call_contract_syscall(account, selector!("__validate__"), data.span())?;
    call_contract_syscall(account, selector!("__execute__"), data.span())
}

/// Signed by the keys every account here starts with (ECDSA_PK, Falcon key A, SHAKE-256).
fn signed(account: ContractAddress, calls: Array<Call>) -> SyscallResult<Span<felt252>> {
    transact(account, calls, hybrid_sig())
}

/// The call failed, and `reason` is among the felts of its error.
pub fn assert_reverts_with(result: SyscallResult<Span<felt252>>, reason: felt252) {
    match result {
        Ok(_) => panic!("succeeded, expected a revert with {reason}"),
        Err(error) => {
            let mut found = false;
            for felt in error.span() {
                found = found || *felt == reason;
            }
            assert!(found, "reverted with {:?}, expected {reason}", error);
        },
    }
}

/// Still the starting keys and verifier, and still accepting their signature.
pub fn assert_unchanged(account: ContractAddress) {
    let m = IMigratableV2Dispatcher { contract_address: account };
    assert_eq!(m.get_verifier_class_hash(), shake());
    assert_eq!(m.get_ecdsa_public_key(), ECDSA_PK);
    assert_eq!(m.get_falcon_public_key(), falcon_pk());
    let a = IHybridAccountDispatcher { contract_address: account };
    assert_eq!(a.is_valid_signature(MSG, hybrid_sig()), starknet::VALIDATED);
}

/// `set_pq_key` with these arguments, in a signed transaction from a V2 account, reverts with
/// `reason` and leaves the account as it was.
fn assert_set_pq_key_reverts(
    key: Array<felt252>, verifier: ClassHash, setup: ClassHash, proof: Array<felt252>, reason: felt252,
) {
    let account = v2_account();
    let call = set_pq_key_call(account, key, verifier, setup, proof);
    assert_reverts_with(signed(account, array![call]), reason);
    assert_unchanged(account);
}

// ---------------------------------------------------------------- upgrade from the earlier class

#[test]
fn upgrade_alone_keeps_keys_verifier_and_signatures() {
    let account = v1_account();
    signed(account, array![upgrade_call(account)]).unwrap_syscall();
    assert_eq!(get_class_hash_at_syscall(account).unwrap_syscall(), v2());
    assert!(IMigratableV2Dispatcher { contract_address: account }.is_falcon_registered());
    assert_unchanged(account);
    // The next transaction is validated by V2 with the same key and verifier.
    signed(account, array![]).unwrap_syscall();
}

#[test]
fn v1_account_changes_scheme_in_one_transaction_and_back() {
    let account = v1_account();
    let calls = array![
        upgrade_call(account),
        set_pq_key_call(account, mock_key(), mock_verifier(), mock_setup(), mock_proof()),
    ];
    signed(account, calls).unwrap_syscall();

    let m = IMigratableV2Dispatcher { contract_address: account };
    assert_eq!(m.get_falcon_public_key(), mock_key());
    assert_eq!(m.get_verifier_class_hash(), mock_verifier());
    assert_eq!(m.get_ecdsa_public_key(), ECDSA_PK);
    // The old scheme's signature is refused, in a signature check and in a transaction.
    let a = IHybridAccountDispatcher { contract_address: account };
    assert_eq!(a.is_valid_signature(MSG, hybrid_sig()), 0);
    assert_reverts_with(signed(account, array![]), INVALID_SIGNATURE);

    // Back to SHAKE-256 Falcon-512 with key B, in a transaction signed with the mock scheme: the
    // stored key grows from 3 felts to 29.
    let back = set_pq_key_call(account, falcon_pk_b(), shake(), class(0), falcon_rotation_proof());
    transact(account, array![back], mock_sig(MSG)).unwrap_syscall();
    assert_eq!(m.get_falcon_public_key(), falcon_pk_b());
    assert_eq!(m.get_verifier_class_hash(), shake());
    assert_eq!(
        a.is_valid_signature(FALCON_ROTATION_HASH, falcon_rotation_proof()), starknet::VALIDATED,
    );
    assert_reverts_with(transact(account, array![], mock_sig(MSG)), INVALID_SIGNATURE);
}

// ---------------------------------------------------------------- set_pq_key

#[test]
fn set_pq_key_rotates_the_key_within_a_scheme() {
    let account = v2_account();
    let call = set_pq_key_call(account, falcon_pk_b(), shake(), class(0), falcon_rotation_proof());
    signed(account, array![call]).unwrap_syscall();
    let m = IMigratableV2Dispatcher { contract_address: account };
    assert_eq!(m.get_falcon_public_key(), falcon_pk_b());
    assert_eq!(m.get_verifier_class_hash(), shake());
    let a = IHybridAccountDispatcher { contract_address: account };
    assert_eq!(a.is_valid_signature(MSG, hybrid_sig()), 0);
    assert_eq!(
        a.is_valid_signature(FALCON_ROTATION_HASH, falcon_rotation_proof()), starknet::VALIDATED,
    );
}

#[test]
fn proof_by_the_current_key_reverts() {
    assert_set_pq_key_reverts(
        falcon_pk_b(), shake(), class(0), hybrid_sig(), HybridMigratableAccountV2::INVALID_PROOF,
    );
}

#[test]
fn key_nobody_can_sign_for_reverts() {
    let mut other = array![];
    for f in falcon_pk_b() {
        other.append(f + 1);
    }
    assert_set_pq_key_reverts(
        other, shake(), class(0), falcon_rotation_proof(), HybridMigratableAccountV2::INVALID_PROOF,
    );
}

#[test]
fn key_the_verifier_cannot_use_reverts() {
    // A 3-felt key under the Falcon-512 verifier: the account takes any length, the verifier
    // refuses it, and the proof fails.
    assert_set_pq_key_reverts(
        mock_key(), shake(), class(0), mock_proof(), HybridMigratableAccountV2::INVALID_PROOF,
    );
}

#[test]
fn verifier_of_another_scheme_for_the_new_key_reverts() {
    assert_set_pq_key_reverts(
        falcon_pk_b(),
        HybridPoseidonAccount::TEST_CLASS_HASH,
        class(0),
        falcon_rotation_proof(),
        HybridMigratableAccountV2::INVALID_PROOF,
    );
}

#[test]
fn scheme_that_needs_setup_reverts_without_it() {
    assert_set_pq_key_reverts(
        mock_key(), mock_verifier(), class(0), mock_proof(), HybridMigratableAccountV2::INVALID_PROOF,
    );
}

#[test]
fn empty_key_reverts() {
    assert_set_pq_key_reverts(
        array![], mock_verifier(), mock_setup(), mock_proof(), HybridMigratableAccountV2::INVALID_PQ_KEY,
    );
}

#[test]
fn zero_verifier_reverts() {
    assert_set_pq_key_reverts(
        mock_key(), class(0), mock_setup(), mock_proof(), HybridMigratableAccountV2::INVALID_VERIFIER,
    );
}

#[test]
fn undeclared_verifier_reverts() {
    assert_set_pq_key_reverts(
        mock_key(), class(0x1234), mock_setup(), mock_proof(), 'CLASS_HASH_NOT_DECLARED',
    );
}

#[test]
fn setup_class_without_the_entry_point_reverts() {
    assert_set_pq_key_reverts(
        mock_key(),
        mock_verifier(),
        LegacyOzLikeAccount::TEST_CLASS_HASH,
        mock_proof(),
        'ENTRYPOINT_NOT_FOUND',
    );
}

#[test]
fn setup_that_rewrites_a_key_reverts() {
    assert_set_pq_key_reverts(
        mock_key(),
        mock_verifier(),
        KeyRewritingSetup::TEST_CLASS_HASH,
        mock_proof(),
        HybridMigratableAccountV2::STATE_CHANGED,
    );
}

#[test]
fn ecdsa_only_transaction_cannot_set_the_key() {
    let account = v2_account();
    let call = set_pq_key_call(account, mock_key(), mock_verifier(), mock_setup(), mock_proof());
    assert_reverts_with(transact(account, array![call], array![ECDSA_R, ECDSA_S]), INVALID_SIGNATURE);
    assert_unchanged(account);
}

#[test]
#[should_panic(expected: ('Migratable: only self', 'ENTRYPOINT_FAILED'))]
fn set_pq_key_from_outsider_fails() {
    let account = v2_account();
    starknet::testing::set_contract_address(0x1234.try_into().unwrap());
    IMigratableV2Dispatcher { contract_address: account }
        .set_pq_key(mock_key(), mock_verifier(), mock_setup(), mock_proof());
}

#[test]
#[should_panic(expected: ('Migratable: not registered', 'ENTRYPOINT_FAILED'))]
fn set_pq_key_before_migration_fails() {
    let account = deploy_legacy();
    starknet::testing::set_contract_address(account);
    ILegacyDispatcher { contract_address: account }.upgrade(v2());
    IMigratableV2Dispatcher { contract_address: account }
        .set_pq_key(mock_key(), mock_verifier(), mock_setup(), mock_proof());
}

// ---------------------------------------------------------------- the entry points V2 keeps

#[test]
fn raw_verifier_switch_to_another_scheme_reverts() {
    let account = v2_account();
    let call = Call {
        to: account,
        selector: selector!("set_verifier_class_hash"),
        calldata: array![mock_verifier().into()].span(),
    };
    assert_reverts_with(
        signed(account, array![call]), HybridMigratableAccountV2::INCOMPATIBLE_VERIFIER,
    );
    assert_unchanged(account);
}

#[test]
fn rotate_ecdsa_key_still_needs_and_takes_a_proof() {
    let account = v2_account();
    starknet::testing::set_contract_address(account);
    let m = IMigratableV2Dispatcher { contract_address: account };
    m.rotate_ecdsa_public_key(WRONG_ECDSA_PK, ecdsa_rotation_proof());
    assert_eq!(m.get_ecdsa_public_key(), WRONG_ECDSA_PK);
    let a = IHybridAccountDispatcher { contract_address: account };
    assert_eq!(a.is_valid_signature(ECDSA_ROTATION_HASH, ecdsa_rotation_proof()), starknet::VALIDATED);
    assert_eq!(a.is_valid_signature(MSG, hybrid_sig()), 0);
}

// ---------------------------------------------------------------- migrating straight to V2

fn migration_data(key: Array<felt252>, verifier: ClassHash, setup: ClassHash, proof: Array<felt252>) -> Array<felt252> {
    let m = MigrationDataV2 {
        ecdsa_public_key: ECDSA_PK,
        pq_public_key: key,
        verifier_class_hash: verifier,
        setup_class_hash: setup,
        proof,
    };
    let mut data = array![];
    m.serialize(ref data);
    data
}

fn deploy(class_hash: ClassHash) -> ContractAddress {
    let (address, _) = deploy_syscall(class_hash, 0, array![ECDSA_PK].span(), false)
        .unwrap_syscall();
    starknet::testing::set_contract_address(address);
    address
}

fn assert_migrated(account: ContractAddress) {
    assert_eq!(get_class_hash_at_syscall(account).unwrap_syscall(), v2());
    assert!(IMigratableV2Dispatcher { contract_address: account }.is_falcon_registered());
    assert_unchanged(account);
    let a = IHybridAccountDispatcher { contract_address: account };
    assert_eq!(a.is_valid_signature(MSG, array![ECDSA_R, ECDSA_S]), 0);
}

#[test]
fn openzeppelin_upgrade_then_migrate() {
    let account = deploy(LegacyOzLikeAccount::TEST_CLASS_HASH);
    ILegacyDispatcher { contract_address: account }.upgrade(v2());
    IMigratableV2Dispatcher { contract_address: account }
        .migrate(ECDSA_PK, falcon_pk(), shake(), class(0), hybrid_sig());
    assert_migrated(account);
}

#[test]
fn argent_upgrade_migrates_in_one_call() {
    let account = deploy(ArgentLikeAccount::TEST_CLASS_HASH);
    IArgentLikeDispatcher { contract_address: account }
        .upgrade(v2(), migration_data(falcon_pk(), shake(), class(0), hybrid_sig()));
    assert_migrated(account);
}

#[test]
fn argent_0_3_upgrade_migrates_in_one_call() {
    let account = deploy(Argent03LikeAccount::TEST_CLASS_HASH);
    IArgent03LikeDispatcher { contract_address: account }
        .upgrade(v2(), migration_data(falcon_pk(), shake(), class(0), hybrid_sig()));
    assert_migrated(account);
}

#[test]
fn migrates_straight_to_a_scheme_with_setup() {
    let account = deploy(ArgentLikeAccount::TEST_CLASS_HASH);
    let proof = mock_sig(registration_hash(ECDSA_PK, mock_key().span()));
    IArgentLikeDispatcher { contract_address: account }
        .upgrade(v2(), migration_data(mock_key(), mock_verifier(), mock_setup(), proof));
    let m = IMigratableV2Dispatcher { contract_address: account };
    assert_eq!(m.get_falcon_public_key(), mock_key());
    assert_eq!(m.get_verifier_class_hash(), mock_verifier());
    transact(account, array![], mock_sig(MSG)).unwrap_syscall();
}

#[test]
#[should_panic]
fn migration_with_a_proof_by_other_keys_fails() {
    let account = deploy(ArgentLikeAccount::TEST_CLASS_HASH);
    IArgentLikeDispatcher { contract_address: account }
        .upgrade(v2(), migration_data(falcon_pk_b(), shake(), class(0), hybrid_sig()));
}

#[test]
#[should_panic(expected: ('Migratable: already registered', 'ENTRYPOINT_FAILED'))]
fn migrate_twice_fails() {
    let account = v2_account();
    starknet::testing::set_contract_address(account);
    IMigratableV2Dispatcher { contract_address: account }
        .migrate(ECDSA_PK, falcon_pk(), shake(), class(0), hybrid_sig());
}

#[test]
fn bootstrap_accepts_only_an_ecdsa_signed_migrate_call() {
    let account = deploy(LegacyOzLikeAccount::TEST_CLASS_HASH);
    ILegacyDispatcher { contract_address: account }.upgrade(v2());
    let migrate_call = Call { to: account, selector: selector!("migrate"), calldata: array![].span() };
    let other_call = Call { to: account, selector: selector!("upgrade"), calldata: array![].span() };
    starknet::testing::set_transaction_hash(MSG);
    starknet::testing::set_signature(array![ECDSA_R, ECDSA_S].span());
    let mut data = array![];
    Serde::serialize(@array![migrate_call], ref data);
    call_contract_syscall(account, selector!("__validate__"), data.span()).unwrap_syscall();
    let mut data = array![];
    Serde::serialize(@array![other_call], ref data);
    assert_reverts_with(
        call_contract_syscall(account, selector!("__validate__"), data.span()),
        HybridMigratableAccountV2::NOT_REGISTERED,
    );
}

#[test]
fn fresh_deployment_with_both_keys() {
    let mut calldata = array![ECDSA_PK];
    Serde::serialize(@falcon_pk(), ref calldata);
    calldata.append(shake().into());
    calldata.append(0);
    let (account, _) = deploy_syscall(v2(), 0, calldata.span(), false).unwrap_syscall();
    assert_unchanged(account);
}

// ---------------------------------------------------------------- Falcon-1024 (PF-14)

/// The account holds the Falcon-1024 key and verifier, accepts its signatures and refuses
/// Falcon-512 ones.
fn assert_on_falcon1024(account: ContractAddress) {
    let m = IMigratableV2Dispatcher { contract_address: account };
    assert_eq!(m.get_falcon_public_key(), falcon1024_pk());
    assert_eq!(m.get_verifier_class_hash(), falcon1024());
    assert_eq!(m.get_ecdsa_public_key(), ECDSA_PK);
    let a = IHybridAccountDispatcher { contract_address: account };
    assert_eq!(a.is_valid_signature(MSG, falcon1024_sig()), starknet::VALIDATED);
    assert_eq!(a.is_valid_signature(MSG, hybrid_sig()), 0);
    assert_reverts_with(signed(account, array![]), INVALID_SIGNATURE);
    transact(account, array![], falcon1024_sig()).unwrap_syscall();
}

#[test]
fn falcon512_to_falcon1024_and_back() {
    let account = v2_account();
    let up = set_pq_key_call(
        account, falcon1024_pk(), falcon1024(), class(0), falcon1024_rotation_proof(),
    );
    signed(account, array![up]).unwrap_syscall();
    assert_on_falcon1024(account);
    assert_eq!(
        IHybridAccountDispatcher { contract_address: account }
            .is_valid_signature(F1024_ROTATION_HASH, falcon1024_rotation_proof()),
        starknet::VALIDATED,
    );

    // Back to Falcon-512 key B, in a transaction signed with Falcon-1024: 57 felts to 29.
    let down = set_pq_key_call(account, falcon_pk_b(), shake(), class(0), falcon_rotation_proof());
    transact(account, array![down], falcon1024_sig()).unwrap_syscall();
    let m = IMigratableV2Dispatcher { contract_address: account };
    assert_eq!(m.get_falcon_public_key(), falcon_pk_b());
    assert_eq!(m.get_verifier_class_hash(), shake());
    let a = IHybridAccountDispatcher { contract_address: account };
    assert_eq!(
        a.is_valid_signature(FALCON_ROTATION_HASH, falcon_rotation_proof()), starknet::VALIDATED,
    );
    assert_eq!(a.is_valid_signature(MSG, falcon1024_sig()), 0);
    assert_reverts_with(transact(account, array![], falcon1024_sig()), INVALID_SIGNATURE);
}

#[test]
fn v1_account_moves_to_falcon1024_in_one_transaction() {
    let account = v1_account();
    let calls = array![
        upgrade_call(account),
        set_pq_key_call(
            account, falcon1024_pk(), falcon1024(), class(0), falcon1024_rotation_proof(),
        ),
    ];
    signed(account, calls).unwrap_syscall();
    assert_eq!(get_class_hash_at_syscall(account).unwrap_syscall(), v2());
    assert_on_falcon1024(account);
}

#[test]
fn falcon512_key_under_the_falcon1024_verifier_reverts() {
    // A valid Falcon-512 key and proof: the 1024 verifier refuses the 29-felt key.
    assert_set_pq_key_reverts(
        falcon_pk_b(),
        falcon1024(),
        class(0),
        falcon_rotation_proof(),
        HybridMigratableAccountV2::INVALID_PROOF,
    );
}

#[test]
fn falcon1024_key_under_a_falcon512_verifier_reverts() {
    assert_set_pq_key_reverts(
        falcon1024_pk(),
        shake(),
        class(0),
        falcon1024_rotation_proof(),
        HybridMigratableAccountV2::INVALID_PROOF,
    );
}

#[test]
fn raw_verifier_switch_to_falcon1024_reverts() {
    let account = v2_account();
    let call = Call {
        to: account,
        selector: selector!("set_verifier_class_hash"),
        calldata: array![falcon1024().into()].span(),
    };
    assert_reverts_with(
        signed(account, array![call]), HybridMigratableAccountV2::INCOMPATIBLE_VERIFIER,
    );
    assert_unchanged(account);
}

#[test]
fn migrates_straight_to_falcon1024() {
    let account = deploy(ArgentLikeAccount::TEST_CLASS_HASH);
    IArgentLikeDispatcher { contract_address: account }
        .upgrade(
            v2(),
            migration_data(
                falcon1024_pk(), falcon1024(), class(0), falcon1024_registration_proof(),
            ),
        );
    assert!(IMigratableV2Dispatcher { contract_address: account }.is_falcon_registered());
    assert_on_falcon1024(account);
}

// ---------------------------------------------------------------- ML-DSA-44 (PF-13)

fn mldsa() -> ClassHash {
    HybridMlDsa44Verifier::TEST_CLASS_HASH
}

fn mldsa_setup() -> ClassHash {
    MlDsa44KeySetup::TEST_CLASS_HASH
}

/// The account holds the ML-DSA-44 key and verifier, accepts its signatures and refuses
/// Falcon-512 ones.
fn assert_on_mldsa(account: ContractAddress) {
    let m = IMigratableV2Dispatcher { contract_address: account };
    assert_eq!(m.get_falcon_public_key(), mldsa_pk());
    assert_eq!(m.get_verifier_class_hash(), mldsa());
    assert_eq!(m.get_ecdsa_public_key(), ECDSA_PK);
    let a = IHybridAccountDispatcher { contract_address: account };
    assert_eq!(a.is_valid_signature(MSG, mldsa_sig()), starknet::VALIDATED);
    assert_eq!(a.is_valid_signature(MSG, mldsa_sig_b()), 0);
    assert_eq!(a.is_valid_signature(MSG, hybrid_sig()), 0);
    assert_reverts_with(signed(account, array![]), INVALID_SIGNATURE);
    transact(account, array![], mldsa_sig()).unwrap_syscall();
}

fn to_mldsa(account: ContractAddress) -> Call {
    set_pq_key_call(account, mldsa_pk(), mldsa(), mldsa_setup(), mldsa_rotation_proof())
}

#[test]
fn falcon512_to_mldsa_and_back() {
    let account = v2_account();
    signed(account, array![to_mldsa(account)]).unwrap_syscall();
    assert_on_mldsa(account);
    assert_eq!(
        IHybridAccountDispatcher { contract_address: account }
            .is_valid_signature(MLDSA_ROTATION_HASH, mldsa_rotation_proof()),
        starknet::VALIDATED,
    );

    // Back to Falcon-512 key B, signed with ML-DSA: 43 felts to 29, no setup.
    let down = set_pq_key_call(account, falcon_pk_b(), shake(), class(0), falcon_rotation_proof());
    transact(account, array![down], mldsa_sig()).unwrap_syscall();
    let m = IMigratableV2Dispatcher { contract_address: account };
    assert_eq!(m.get_falcon_public_key(), falcon_pk_b());
    assert_eq!(m.get_verifier_class_hash(), shake());
    assert_reverts_with(transact(account, array![], mldsa_sig()), INVALID_SIGNATURE);
}

#[test]
fn v1_account_moves_to_mldsa_in_one_transaction() {
    let account = v1_account();
    signed(account, array![upgrade_call(account), to_mldsa(account)]).unwrap_syscall();
    assert_eq!(get_class_hash_at_syscall(account).unwrap_syscall(), v2());
    assert_on_mldsa(account);
}

#[test]
fn migrates_straight_to_mldsa() {
    let account = deploy(ArgentLikeAccount::TEST_CLASS_HASH);
    IArgentLikeDispatcher { contract_address: account }
        .upgrade(v2(), migration_data(mldsa_pk(), mldsa(), mldsa_setup(), mldsa_registration_proof()));
    assert!(IMigratableV2Dispatcher { contract_address: account }.is_falcon_registered());
    assert_on_mldsa(account);
}

#[test]
fn mldsa_without_its_setup_reverts() {
    assert_set_pq_key_reverts(
        mldsa_pk(), mldsa(), class(0), mldsa_rotation_proof(), HybridMigratableAccountV2::INVALID_PROOF,
    );
}

#[test]
fn mldsa_setup_on_a_falcon_key_reverts() {
    assert_set_pq_key_reverts(
        falcon_pk_b(), mldsa(), mldsa_setup(), falcon_rotation_proof(), MALFORMED_KEY,
    );
}

#[test]
fn mldsa_key_under_a_falcon512_verifier_reverts() {
    assert_set_pq_key_reverts(
        mldsa_pk(), shake(), mldsa_setup(), mldsa_rotation_proof(), HybridMigratableAccountV2::INVALID_PROOF,
    );
}

#[test]
fn raw_verifier_switch_to_mldsa_reverts() {
    let account = v2_account();
    let call = Call {
        to: account,
        selector: selector!("set_verifier_class_hash"),
        calldata: array![mldsa().into()].span(),
    };
    assert_reverts_with(
        signed(account, array![call]), HybridMigratableAccountV2::INCOMPATIBLE_VERIFIER,
    );
    assert_unchanged(account);
}

#[test]
fn mldsa_rotation_needs_the_setup_again() {
    // The cache is for key A: key B without the setup is refused (its digest does not match), key
    // B with the setup is accepted, and key A's signatures are then refused.
    let account = v2_account();
    signed(account, array![to_mldsa(account)]).unwrap_syscall();
    let stale = set_pq_key_call(account, mldsa_pk_b(), mldsa(), class(0), mldsa_rotation_proof_b());
    assert_reverts_with(
        transact(account, array![stale], mldsa_sig()), HybridMigratableAccountV2::INVALID_PROOF,
    );
    assert_on_mldsa(account);

    let rotate = set_pq_key_call(
        account, mldsa_pk_b(), mldsa(), mldsa_setup(), mldsa_rotation_proof_b(),
    );
    transact(account, array![rotate], mldsa_sig()).unwrap_syscall();
    let a = IHybridAccountDispatcher { contract_address: account };
    assert_eq!(a.is_valid_signature(MSG, mldsa_sig_b()), starknet::VALIDATED);
    assert_eq!(a.is_valid_signature(MSG, mldsa_sig()), 0);
    transact(account, array![], mldsa_sig_b()).unwrap_syscall();
}
