# Replacing a migrated account's verifier

A migrated `HybridMigratableAccount` checks signatures by library-calling a verifier class
(`Migratable_verifier_class_hash`). `set_verifier_class_hash` changes it, but only checks that
the caller is the account, that it has migrated and that the hash is non-zero. Installing a
verifier that cannot validate the account's signatures would lock it: every later transaction
would fail `__validate__`, including one that tries to switch back.

## The guarded switch

One hybrid-signed transaction from the account:

```
[ account.set_verifier_class_hash(candidate),
  guard.assert_compatible(account, candidate) ]
```

`VerifierSwitchGuard.assert_compatible` (`contracts/src/guard.cairo`) checks that the caller is
the account and that it now points at `candidate`. It then calls
`account.is_valid_signature(tx.transaction_hash, tx.signature)` with this same transaction's
hash and signature. By then that library-calls the candidate in the account's own storage, and
the guard requires `VALIDATED`. Finally it checks the verifier pointer and the keys the account
reports are unchanged. If any check fails it panics, and the whole transaction reverts, leaving
the old verifier in place.

- No new account entry point or class upgrade: it uses `set_verifier_class_hash` and
  `is_valid_signature`, which every deployed migratable class has (see below).
- No separate proof. The transaction hash already commits to the chain, the account, the nonce
  and the candidate in the calldata, so the signature cannot be replayed onto another switch.
- The wallet kit builds it: `verifierSwitchCalls(provider, address, candidate, { guard, allowed })`
  in `signer/pq_account_kit.mjs`. It checks, read-only, that:
  - the account is a migrated hybrid account;
  - the candidate is in the wallet's `allowed` list, declared, exposes
    `is_valid_signature(hash, signature)` and isn't already installed;
  - the guard is deployed.

  It always returns both calls. Simulate them before sending.

## Limits

- **Same scheme only.** The old verifier checks the signature in `__validate__` and the candidate
  checks the same signature in the guard. That works between two SHAKE-256 verifiers (for example
  `HybridShakeAccount` and `HybridShakeVerifierPfCompact`), not between Poseidon and SHAKE-256,
  which need a signature of the candidate's scheme in the calldata. That case isn't supported.
- **One signature.** The check catches gross incompatibility: the wrong hash-to-point, storage,
  ABI or return value. It doesn't catch a verifier that only rejects rare inputs. That's what the
  differential suite (PF-03, `bench/pf03`) is for.
- **Tooling, not an invariant.** `set_verifier_class_hash` and `upgrade` can still be called
  directly in a hybrid-signed transaction and skip the guard.
- **The candidate is trusted code.** It runs in the account's storage and can read or write
  anything there. The guard sees only the verifier pointer and the keys the account reports
  (`get_ecdsa_public_key`, `get_falcon_public_key`), not the mirrored `ecdsa_public_key` slot or
  other storage. It protects against accidental incompatibility, not a hostile class. Allow only
  reviewed, pinned class hashes.
- **Switching back needs a working verifier.** Returning to the baseline uses the same guarded
  switch, so it works only while the active verifier still accepts the account's signatures.
  Nothing recovers an account whose verifier rejects every transaction.
- A failed switch is a reverted transaction: the fee is charged and the nonce advances.

## Tests

`contracts/src/tests_guard.cairo` runs each case as a transaction: `__validate__` with the
signature, then `__execute__` with the calls. Each failing case asserts its revert reason and
that the verifier pointer and keys are unchanged afterwards.

| Case | Result |
| --- | --- |
| baseline SHAKE → `HybridShakeVerifierPfCompact`, then a transaction validated by it | installed, validates |
| compact → baseline | installed |
| `HybridPoseidonAccount` (same key, other hash-to-point) | reverts: `Guard: signature rejected` |
| zero class hash | reverts: `Migratable: invalid verifier` |
| undeclared class hash | reverts: `CLASS_HASH_NOT_DECLARED` |
| class without `is_valid_signature` | reverts: `ENTRYPOINT_NOT_FOUND` |
| class answering something other than `VALIDATED` | reverts: `Guard: signature rejected` |
| class that accepts and rewrites the classical key | reverts: `Guard: account state changed`; key restored |
| guard before the switch, or naming another class | reverts: `Guard: verifier not installed` |
| ECDSA-only, Falcon-only, wrong ECDSA key | rejected in `__validate__` |
| outsider calls `__execute__` or the setter | `Account: invalid caller` / `Migratable: only self` |
| guard called by anyone but the account | `Guard: caller is not account` |

When the guard's signature check is removed, the Poseidon and wrong-answer cases fail. When its
state check is removed, the key-rewriting case fails.

`signer/verifier_switch_check.mjs` checks the kit's read-only gates offline against the compiled
ABIs.

## Deployed accounts

`signer/verifier_switch_inventory.mjs` reads Sepolia (read-only) for every account linked from
`README.md` and `contracts/docs/wallet-coverage.md`. On 2026-10-27 it found 17 migrated accounts
on 4 migratable class versions. All are registered, all have `set_verifier_class_hash` and
`is_valid_signature`, and every verifier they point at has `is_valid_signature`. So the guarded
switch needs no account upgrade on any of them.

| Migratable class | Accounts | Notes |
| --- | ---: | --- |
| `0x4b067679dbb29516dd79fba49ba1f1b2bc3973b33c74881ff56098d19e27a78` | 11 | current class (2026-10-19); this commit rebuilds to the same hash |
| `0x660679aa09bef2ef29e1a2ebe21ee85d87bacde8746430b380425db5dd3c31b` | 2 | earlier class (Argent and Braavos demo accounts) |
| `0x7b6d5ed4cbb6c7a2633dd9139c25ffb76bb608cafbba9e424a277a885432b25` | 1 | public demo account |
| `0xae4154b7e35c9475f4875757bcfa2b19ca88fc2e9bd9fa793e82a91ef5815f` | 3 | includes the README's in-place OpenZeppelin migration (`0x54370be5…`) |

| Verifier | Accounts | Class |
| --- | ---: | --- |
| `0x2255fc213bf39d1df2129c9e068b363f2b11a27b70b4b2c48df8ea4275f1c92` | 15 | `HybridShakeAccount` (this commit rebuilds to the same hash): can switch to an optimized SHAKE-256 verifier |
| `0x7f10b6f2f70e72ef87e97844b5f6f13d384c92afcfed2a1233a03524d359d6f` | 2 | `HybridPoseidonAccount`: needs a scheme change, not supported by the guarded switch |

Class hashes built at this commit with Scarb 2.18.0, not declared anywhere yet (that's PF-07):

| Class | Class hash | CASM felts |
| --- | --- | ---: |
| `HybridShakeVerifierPfCompact` | `0x5e121c050ad841f727873ee3412aedcfb2d7c1c9f8c79a53a73251e79d9d4c7` | 71,580 |
| `HybridShakeVerifierPfRecord` | `0x281a32f3b7c2eee62405318cd8b074a44ff17f6c804a003f80276b0dc3c905a` | 77,902 |
| `VerifierSwitchGuard` | `0x44779ad7a4ea11318759272383a06d06fdf1b7c007ba1e5f38a2096e6e26178` | 1,164 |
