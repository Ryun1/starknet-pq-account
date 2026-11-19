# ARCH-02 implementation plan: dormant PQ key

Issue: https://github.com/Ryun1/starknet-pq-account/issues/26. Planned 2026-11-19. Nothing here is
built or measured yet. Experimental and testnet-only, as in PF-00.

## Summary

A new class, `HybridDormantAccount` (`contracts/src/dormant.cairo`), with three states:

| State | Storage | `__validate__` accepts |
| --- | --- | --- |
| Dormant | `Dormant_commitment != 0`, `falcon_public_key` empty | ECDSA-only, but no call to the account itself except `propose_commitment` and `activate` |
| Active | `falcon_public_key` set (commitment cleared) | hybrid only, exactly as a registered `HybridMigratableAccountV2` |
| Unregistered | neither | ECDSA-only, a single self-call to `commit` / `migrate` (V2's bootstrap) |

The commitment is `poseidon(DORMANT_DOMAIN, verifier_class_hash, setup_class_hash, pq_key...)`.
Activation reveals the key, checks it against the commitment, writes it with V2's `_register`, and
checks a **hybrid** proof (current ECDSA key + revealed PQ key) through the committed verifier. After
activation the account is in V2's registered state, storage-identical, so it can `upgrade` to V2.

Main reuse: V2's storage layout, `_write_pq_key`, `_register`, `_verify`, `_assert_state`, the
existing Falcon-512 verifier classes, `HybridSigner`, and the v0.1 key backup (the PQ key is
re-derived from the same mnemonic at activation, so the wallet stores nothing extra).

## Design decisions (answers to the issue's questions)

These go into the design note (step 1) with the threat model. Recommendations in **bold**.

1. **Who can change the commitment.** **ECDSA-only can propose a new commitment, which becomes
   effective after `DORMANT_DELAY` (constant, proposal 7 days; open question).** During the delay
   the owner vetoes by activating: `activate` clears any pending proposal. A dedicated veto entry
   point is unnecessary, because a pending proposal the owner did not make means ECDSA is
   compromised, and activation is then the right response anyway. A zero commitment is refused, so
   ECDSA-only cannot remove the key. An immutable commitment was rejected: a wallet that changes its
   key derivation, or a committed verifier found to be buggy, would leave the account with no way
   to fix the commitment.
2. **What ECDSA-only may do while dormant.** Any external call. No self-call except
   `propose_commitment` and `activate`. That blocks `upgrade`, `rotate_ecdsa_public_key`,
   `set_pq_key` and `set_verifier_class_hash`. An attacker who rotated the ECDSA key or upgraded the
   class would block the owner's hybrid activation proof, so these must be blocked. The check is in
   `__validate__`, over every call in the multicall.
3. **Activation trigger.** **The owner's proof only.** Guardians: out of scope, because Argent-style
   guardians belong to OZ-01/ARCH-03. On-chain signal: not built. We have no register to read today,
   and when one exists it is a single extra `__validate__` check ("signal set ⇒ refuse ECDSA-only").
   The design note records that option.
4. **Key type.** **Falcon-512 through the existing verifier classes.** Hash-based one-time keys
   (WOTS+/LMS, PF-15 item 4) and SLH-DSA in `__execute__` are left for later. The commitment binds
   `verifier_class_hash`, so a future scheme slots in as another verifier class with no account
   change. Binding the verifier is required: if activation could pick any verifier, an attacker with
   ECDSA could activate with a verifier that accepts anything.
5. **Fee griefing.** **`activate` is an external function callable by anyone, and the proof is
   checked in execution.** A third party who calls it pays their own fee, and a bad proof reverts
   their transaction, not ours. The owner can also call it as a self-call from the account itself
   (ECDSA-signed, allowed by rule 2). An attacker can submit that too, but only with a valid proof,
   which needs the PQ key. Nothing PQ runs in `__validate__`, so the dormant `__validate__` stays at
   ECDSA cost.
6. **Race window.** Not solved here. Until activation, an ECDSA forger can drain anything ECDSA
   reaches. The note states the loss bound plainly (everything) and points to ARCH-03 spend caps as
   the mitigation. The prototype adds nothing for the race beyond blocking self-calls.
7. **Replay and front-running.** The proof signs `activation_hash(DORMANT_DOMAIN, account address,
   chain id, ecdsa key, pq key)`. Activation is one-shot because the state changes, so no nonce is
   needed. A front-runner can only submit the same activation, which helps the owner.
8. **`is_valid_signature` while dormant.** ECDSA-only, otherwise dapps break (permits, SNIP-12
   logins). After Q-day these off-chain signatures are forgeable, the same as for any ECDSA account.
   The note says so. After activation it is hybrid.
9. **Overlap with `recovery/`.** The ZK seed proof stays the fallback for accounts that never
   committed. This class is the cheap path for those that do. No code is shared.
10. **After activation.** Hybrid, not PQ-only. Under hybrid AND, a forged ECDSA signature gains
    nothing, so ECDSA-alone is refused as the issue requires. Dropping ECDSA completely is ARCH-01.
    Activation is one-way: going back to dormant would re-open the ECDSA-only path, so there is no
    entry point for it.

## Steps

### 1. Design note: `contracts/docs/dormant-pq-key.md`

The decisions above, a threat model per question (attacker has ECDSA before and after Q-day,
attacker has neither, the owner has lost the PQ key), and the loss bound. This closes acceptance
criterion 1. Pause here for review before building.

### 2. Class: `contracts/src/dormant.cairo`

Storage: V2's four fields, plus `Dormant_commitment: felt252`, `Dormant_pending: felt252`,
`Dormant_ready_at: u64`. Names are prefixed so they don't collide with V2 or the wallets' classes
(extend `signer/storage_collision_check.mjs`).

Entry points:
- `constructor(ecdsa_public_key, commitment)`: fresh dormant account.
- `commit(commitment)`: self-only, unregistered → dormant. This is the bootstrap path after a
  wallet's `upgrade`. Argent `perform_upgrade` / `execute_after_upgrade` take the commitment as
  `data`.
- `propose_commitment(commitment)`: self-only, dormant. Writes pending and `ready_at = now + DELAY`
  and emits `CommitmentProposed`.
- `apply_commitment()`: anyone, after `ready_at`. Moves pending to the commitment.
- `activate(pq_key, verifier, setup, proof)`: anyone. Checks the commitment, then V2's
  `_register` → `_verify(activation_hash, proof)` → `_assert_state`. Clears the commitment and
  pending, and emits `Activated`.
- `upgrade` (active only, hybrid-signed) and getters, including `get_commitment()`,
  `get_pending_commitment()` and `is_dormant()`.

As built: V2's key-management entry points (`set_pq_key`, `rotate_ecdsa_public_key`,
`set_verifier_class_hash`) are **not** copied. An active account `upgrade`s to V2 for those, because
the storage is identical. The Argent `perform_upgrade` / `execute_after_upgrade` paths are left out:
`commit` would need the ECDSA key plus a proof of possession. Only fresh deployment and the
OZ-style `[upgrade, commit]` path are supported. The few V2 internals that are needed are copied,
not shared (turning them into a component is OZ-01), which keeps `migratable_v2.cairo` unchanged.

Decisions confirmed with the user on 2026-11-19: 7-day delay, `apply_commitment` callable by
anyone, a hybrid activation proof, and a PR that covers the note, class and tests (steps 4 and 5
are follow-ups).

### 3. Tests: `contracts/src/tests_dormant.cairo`

`cairo_test` with `starknet::testing` (`set_block_timestamp`, `set_signature`), as in
`tests_scheme.cairo`. Reuse the Falcon-512 fixtures.

- Dormant: an ECDSA-only transfer validates; a hybrid one is not needed; each blocked self-call
  (`upgrade`, `rotate_ecdsa_public_key`, `set_pq_key`, `set_verifier_class_hash`, and a multicall
  that pairs an allowed call with a blocked one) is rejected in `__validate__`.
- Activation: the right key and proof activate, then ECDSA-only is rejected and hybrid validates.
  A wrong key (commitment mismatch), the right key with another verifier, a tampered Falcon half,
  a proof for another account address, and a second activation all revert.
- Time lock: `apply_commitment` before `ready_at` reverts, and at `ready_at` it succeeds. Veto: a
  pending proposal followed by activation leaves no pending proposal, and `apply_commitment`
  reverts.
- Zero commitment is refused in the constructor, `commit` and `propose_commitment`.
- An activated account `upgrade`s to V2 and validates there (storage compatibility).
- A third party calling `activate` with a bad proof reverts and leaves the account dormant.

### 4. Wallet kit: `signer/pq_account_kit.mjs`

- `dormantCommitment(keys, verifierClass, setupClass)`, matching the Cairo hash, with a vector
  test.
- `activationCalls(address, keys, …)`, plus a pre-flight that **simulates** activation without
  sending, so a wallet can check at commit time that its derived key opens the commitment. This
  replaces an on-chain proof of possession at commit (29.6M saved).
- `inspectAccount` reports dormant / active / pending, with `ready_at`.
- `HybridSigner` signs ECDSA-only while the account is dormant.

### 5. Measure

`__validate__` gas for a dormant ECDSA-only transfer, compared with a plain ECDSA account (issue
target ~31K). Also activation execution gas. Use devnet (`verifier_switch_devnet.mjs` style), and
record it as devnet-only in the way bench/pf06 labels its evidence. Sepolia only in a
user-authorized rollout.

## Out of scope

Spend caps and delayed transfers (ARCH-03), PQ-only after activation (ARCH-01), hash-based keys
(PF-15 item 4), guardians, Sepolia or hosted-demo changes.

## Open questions for review

- `DORMANT_DELAY`: 7 days assumes the owner watches for `CommitmentProposed`. Who alerts them? A
  wallet-side check on open is the cheapest option.
- Should `apply_commitment` be self-only? Anyone-callable saves the owner a transaction and gives an
  attacker nothing they couldn't get by calling it from the account.
- Is a hybrid activation proof right, or should it be PQ-only? Hybrid reuses everything. The cost
  is that the owner must still hold the ECDSA key, which a mnemonic backup guarantees.

EXPERIMENTAL AND UNAUDITED: the security claims here need independent review before any reliance.
