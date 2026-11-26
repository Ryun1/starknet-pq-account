# PF-13 implementation plan: ML-DSA-44 (FIPS 204) hybrid verifier

Issue: https://github.com/Ryun1/starknet-pq-account/issues/21. Planned 2026-11-19. Board figures
are external; figures marked "est." were estimates, since replaced by the measurements in steps 4
and 8.

**Progress, 2026-11-26.** Steps 0–8 and 10 done; both acceptance criteria closed. Step 1 merged in
PR #36, steps 2–10 in PR #41 (step 10 landed on the branch after review), the scarb 2.22.0
toolchain in PR #42, the browser page and an ML-DSA-44 demo account in PR #43.
Step 9 (release manifest `testnet-v2`, `wallet-coverage.md`) done the same day; every step is closed.

Step 1 (the scheme-switch account) is shared with PF-14 and is the only part PF-14 depends on.

## What changed since the issue was written

Read from `postquantum.provably.fast/api/participation/mldsa/results` on 2026-11-19.

| | Issue (2026-10-27) | Board, 2026-11-19 |
| --- | --- | --- |
| Record, verification from scratch | ~175M (`mj_eed20939`) | 169,708,897 (`mj_2e2f9ddebbcc4281b07d84937ae0ffbc`, 2026-11-16, 1 attack round withstood) |
| Cached account validation | 45.8M | not re-measured by the board since the 22 Oct record |
| Record's plain account class | not stated | 61,422 CASM felts, 3,057,372 class bytes (the board now caps a record's account at 75% of the class limits) |
| Breaks in the lane | — | 1 (`REJECTS_VALID`, an ExpandA flag carry, on a job that is not the record) |

Consequences:

- From scratch is still over the 100M validation cap, so the cached form is the only deployable one.
- The plain record class probably fits a block now: est. 5.1–5.4e9 declare L2 gas. Sierra felts are
  not published, so this uses the bytes-per-Sierra-felt range of our three PF Falcon-512 classes
  (43.9–48.9).
- The board's single cached account (`MlDsa44CachedAccount`: 79,664 CASM felts, 4,056,437 bytes)
  was built on the 22 Oct record, whose plain account was about 2.3 MB. Records have since grown to
  3.06 MB, so the same account on today's record would likely exceed the 4,089,446-byte class limit,
  and at ~160K felts it could not be declared in a block either (est. 6.5e9).
- So the design below splits validation code and one-time setup code into two classes. That is the
  answer to the issue's "may not fit at all".

## Design

Three classes. Only the first is new work shared with other schemes.

1. **`HybridMigratableAccountV2`** (step 1): scheme-agnostic account. One new entry point,
   `set_pq_key`, replaces the PQ key and its verifier together and proves the new pair works.
2. **`HybridMlDsa44Verifier`**: `is_valid_signature` only, library-called in `__validate__`. Checks
   ECDSA, then the record's cached check using the 43-felt key and a 418-felt cache (tr 8 felts,
   A-hat 410 felts) read from the account's storage. No ExpandA code.
3. **`MlDsa44KeySetup`**: `setup_pq_key()` only, library-called once in `__execute__`. Reads the
   stored key, runs the record's `precompute`, writes the 418 cache slots.

Sizes: key 43 felts, signature 79 felts, hybrid signature 81 felts (gateway limit 4,000).

Cache provenance (decided 2026-11-19): computed on chain by the setup class. It is a public function of the
key, so it changes nothing about which signatures are accepted, and it costs about 377M gas once
(board figure), inside the 1.11e9 execution cap. Rejected: passing a wallet-computed cache as
calldata. It saves a class and the 377M, but the account would then accept signatures under a
matrix nobody checked.

## Steps

### 0. Before starting

- Fast-forward this fork to upstream main (decided 2026-11-19: V2 is cut from the merged source,
  so there is one new account class, not two). The issue #35 merge landed upstream on 2026-11-16
  (0xjuno PR #1). On 2026-11-19 this fork's main was 25 commits behind and had nothing upstream
  lacks. The merged `migratable.cairo` already has a self-checking `set_verifier_class_hash` and
  proof-checked `rotate_falcon_public_key` / `rotate_ecdsa_public_key` over a new `rotation_hash`;
  step 1 builds on those. Steps 2–4 do not touch that file.
- Re-read the network's versioned constants and block cap; `bench/pf04` pins 0.14.4.

### 1. `HybridMigratableAccountV2` (shared with PF-14)

Status 2026-11-19: built on branch `pf13-account-v2`, uncommitted. 26 Cairo tests and the offline
kit check pass; the full contract suite (135) passes; existing classes still match the release
manifest. Differences from the text below:

- The cross-scheme tests use a mock second scheme (3-felt key, setup class, no cryptography), not
  SHAKE ↔ Poseidon: there is no Poseidon signer without a falcon.py checkout. The first real
  second scheme is Falcon-1024 (PF-14 A4).
- `set_pq_key` also re-checks the keys and the verifier pointer after the setup and verifier have
  run, as the merged `set_verifier_class_hash` does.
- Kit: `setPqKeyCalls`, `sendSimulated` and V2 `migrationArgs` are in. The scheme table, the
  per-scheme allow list and the manifest's `scheme` / `setup` fields wait for PF-14 A5 and A8:
  with one real scheme there is nothing to dispatch on.
- Not done: `bench/pf04/run.sh --check` (needs universal-sierra-compiler 2.10.3, not installed
  here), transaction gas of `set_pq_key`, a devnet run against the deployed class versions.

New file `contracts/src/migratable_v2.cairo`, a copy of the merged `migratable.cairo` with the diff
below.
The v1 file stays byte-identical: `release/testnet-v1.json` pins its class hash and CI checks it,
and keeping v1 in the build makes the v1 → v2 upgrade a plain Cairo test.

Changes against v1:

- Drop `PUBKEY_FELTS`. The account no longer knows a key length. "Registered" becomes
  `falcon_public_key.len() != 0`, which is true for every migrated v1 account (length 29) and false
  for an unmigrated one, so storage carries over.
- The storage name `falcon_public_key` stays and becomes "the PQ key, any scheme". Verifier classes
  read it by that name through the library call, so renaming it would break every declared verifier.
- New `set_pq_key(pq_public_key, verifier_class_hash, setup_class_hash, proof)`: self-only,
  registered accounts only. It writes the key (pop to empty, then push; `Vec::pop` exists in corelib
  2.18.0), writes the verifier, library-calls `setup_pq_key()` on `setup_class_hash` if non-zero, then
  requires `proof` to verify through the new verifier, as `_migrate` already does.
- `proof` is a hybrid signature by the current ECDSA key and the new PQ key over the merged
  source's `rotation_hash(ecdsa_public_key, pq_public_key)`, the message `rotate_falcon_public_key`
  already signs. No new hash or domain: the proof prevents lock-out, it authorises nothing (the
  transaction's own hybrid signature does that), and it is checked by whichever verifier is being
  installed.
- `set_pq_key` replaces `rotate_falcon_public_key(key, proof)`: the same proof-checked write, plus
  the verifier and the setup call. A same-scheme rotation is `set_pq_key` with the same verifier.
- `MigrationData` and `migrate` gain `setup_class_hash`, and `_register`, `_migrate` and
  `set_pq_key` share one `_write_pq_key`, so a wallet can migrate straight to any scheme.
- Unchanged: the self-checking `set_verifier_class_hash` (a raw switch to another scheme reverts
  with `Migratable: verifier rejects` instead of locking the account), `rotate_ecdsa_public_key`,
  `upgrade`, the getters, the bootstrap path, `__validate__`.

Sketch (not compiled):

```cairo
fn set_pq_key(
    ref self: ContractState, pq_public_key: Array<felt252>, verifier_class_hash: ClassHash,
    setup_class_hash: ClassHash, proof: Array<felt252>,
) {
    self._assert_only_self();
    assert(self._registered(), NOT_REGISTERED);
    let message = rotation_hash(self.Account_public_key.read(), pq_public_key.span());
    self._write_pq_key(pq_public_key, verifier_class_hash, setup_class_hash);
    assert(self._verify(message, proof.span()), INVALID_PROOF);
    self.emit(PqKeySet { verifier_class_hash });
}
```

Routes this gives (write up in `contracts/docs/scheme-switch.md`, and replace the "same scheme
only" limit in `verifier-replacement.md` with a pointer to it):

| From → to | Route |
| --- | --- |
| Same scheme, new verifier, same key layout | guarded `switchVerifier`, unchanged |
| Migrated v1 account → another scheme | one hybrid-signed multicall `[upgrade(V2), set_pq_key(...)]`; `replace_class` already applies to the second call, as in `[upgrade, migrate]` |
| V2 account → another scheme, or key rotation | `set_pq_key` |
| Unmigrated Argent / Braavos / OpenZeppelin → any scheme | existing migration flows with the V2 class |
| The 2 migrated accounts on the Poseidon verifier | now possible: `[upgrade(V2), set_pq_key]` to a SHAKE verifier, signed with the Poseidon signer |
| Directly deployed `HybridShakeAccount` / `HybridPoseidonAccount` | none, as today (no upgrade entry point) |

The transaction is validated by the old scheme in `__validate__` and the proof by the new one in
`__execute__`, so the proof check does not count against the 100M validation cap.

Tests (`contracts/src/tests_scheme.cairo`, same transaction-style harness as `tests_guard.cairo`):

- v1 account upgraded to V2 keeps both keys and still validates; an unmigrated account on V2 still
  takes the bootstrap path.
- Falcon-512 SHAKE → Poseidon → SHAKE with `set_pq_key` (two schemes that exist today, so this
  lands before any new verifier), then a transaction under each.
- Reverts with state unchanged: wrong proof, proof by another key, key the verifier cannot use,
  zero verifier, undeclared verifier, setup class without the entry point, outsider caller,
  unregistered account.
- After a switch: old-scheme signature rejected, ECDSA-only rejected.
- All existing migration tests (Argent 0.4+, 0.3.x, Braavos, OpenZeppelin) repeated on V2.

Kit: `signer/pq_account_kit.mjs` gains `setPqKeyCalls` / `switchScheme` (simulate with validation,
then send, like `switchVerifier`), and a scheme table (`falcon-512`, later `falcon-1024`,
`ml-dsa-44`) that `HybridSigner` dispatches on. `signer/verifiers.mjs` stops inferring the scheme
from the id prefix `shake-`; the manifest carries `scheme` and optional `setup` per verifier, and
`ALLOWED_VERIFIERS` becomes per scheme so `switchVerifier` refuses a cross-scheme class.
`signer/storage_collision_check.mjs` covers the new slots.

### 2. Vendor and pin

Status 2026-11-19: done; pinned `mj_2e2f9dde` (see `vendor/provably-fast/ml-dsa-44/PROVENANCE.md`).
The board's `cache.cairo` does not build against it (renamed internals); ported as a child module of
the record's `verx`, overlaid by `make_crates.sh` and covered by `SHA256SUMS`.

`vendor/provably-fast/ml-dsa-44/`: the baseline crate `ml_dsa_44` from the lane's bundle at commit
`78c83599f57ecb28847ba3ebc4528598318129b8` (the bundle's `ntt` and `falcon_512` crates are
byte-identical to our vendored baseline, checked 2026-11-19), the pinned record patch,
`SHA256SUMS`, `PROVENANCE.md` with the `builds_on` contributors, and a results snapshot.
`make_crates.sh` takes a lane argument and `--check` runs for every lane in CI. The crate needs
`corelib_imports 0.1.2`, already in the lockfile.

Pin by cached cost, not by board score. On the 22 Oct record 153M of 175M depended only on the
key, so improvements to ExpandA and tr since then do not reach a cached account. Screen two
candidates in step 4:

- `mj_2e2f9dde…`, today's record (169.7M, 1 round withstood);
- `mj_eed20939…`, the record the board's `cache.cairo` was written for (known: 45,776,248 cached
  validation, 377,112,933 setup), or its neighbour `mj_366ff85e…` (199.1M, 10 rounds withstood,
  a 2.3 MB class).

### 3. Cache module and the two classes

Status 2026-11-19: done. One change: the cache has a 419th slot, the Poseidon digest of the key it
was built for, checked by the verifier (a key written without the setup cannot use a stale cache).

`contracts/src/mldsa.cairo`:

- Cache layout in one place, used by both classes so it cannot diverge: 418 consecutive slots from
  two bases (an offset is a `u8`), derived from `selector!("MlDsa44_cache_0")` and `_1`, not magic
  constants. Read and write with the raw storage syscalls.
- `cache::precompute(pk)` and `cache::verify_cached(hash, pk, sig, tr, a_hat)` live in the vendored
  crate's generated copy (they call the record's internals, e.g. `zread`). Start from the board's
  `mldsa/account/cairo/cache.cairo` (source and download date in `PROVENANCE.md`), ported to the
  pinned record. They are part of what the pin covers.
- `HybridMlDsa44Verifier`: ECDSA first, as `verify_hybrid` does, then `verify_cached`. Reads
  `ecdsa_public_key` and `falcon_public_key` (43 felts, length read once) plus the cache.
- `MlDsa44KeySetup`: `setup_pq_key()` reads the key, panics on a malformed one, writes the cache.

### 4. Screen: go / no-go

Status 2026-11-19: **go**, every gate passes (bench/pf13/README.md): verifier declare 65.2%, setup
34.7%, `__validate__` worst 40.6M, `set_pq_key` 414M. Measured with `bench/pf13/gas` (step 8's
harness, built early) rather than a generalised `screen.sh`; only the record was built.
Re-measured 2026-11-26 on scarb 2.22.0 (PR #42): `__validate__` worst 43.4M, verifier declare 67.0%,
setup 36.4%; every gate still passes.

Generalise `bench/pf04/screen.sh` to take a lane (API path, job-id prefix `mj_`, allowed patch
paths `crates/ml_dsa_44/src/…`, class names). For each candidate record, record CASM felts, Sierra
felts, class bytes and declare L2 gas of both classes, built against the audited list and
`network_libfuncs.json`.

Gates, all required:

| Gate | Threshold | Expectation |
| --- | --- | --- |
| Each class's declare | ≤ 95% of 5.8e9 (small is at 93.8%; PF-04 rejected 97.7% as too thin) | verifier est. 5.1–5.4e9, setup well under |
| Class limits | CASM and Sierra ≤ 81,920 felts, class ≤ 4,089,446 bytes | verifier est. ~61K CASM |
| `__validate__`, worst | ≤ 60M (40% headroom) and ≤ 1M steps | est. 46–48M |
| `set_pq_key` and migration | ≤ 1.11e9 execution gas, ≤ 10M steps | est. ~425M (377M setup + ~46M proof) |
| Pinned record | unbroken, at least one hammer round withstood | |

Write the result, with numbers, to `bench/pf13/README.md` and the issue. That closes acceptance
criterion 1 either way. If no-go, stop here; the remaining steps are not built.

### 5. Signer

Status 2026-11-19: done. `signer/mldsa_adapter.mjs` and `signer/mldsa_fixture.mjs`; the kit's
`prepareKeys` / `hybridSignature` treat a 1,312-byte key as ML-DSA-44, and `scheme_switch_check.mjs`
checks the kit's key felts, `set_pq_key` proof and transaction signature equal the Cairo fixture's.
The manifest's `scheme` field waits for step 9's manifest.

`signer/mldsa_adapter.mjs`, about 20 lines: bytes to felts of 31 little-endian bytes (last felt
holds the rest), `publicKeyFelts` (1,312 B → 43), `signatureFelts` (2,420 B → 79), and
`signTxHash`: noble `ml_dsa44.sign` over the hash as 32 **big-endian** bytes, empty context.
(Falcon signs the little-endian bytes; this is the one place the two differ, so it gets a vector
test.) `@noble/post-quantum` 0.6.1 already exports `ml_dsa44`. No new dependency.

### 6. Key backup profile v0.2

Status 2026-11-19: done. `deriveAccountKeys(..., "ml-dsa-44")`; noble checked against the 25
ML-DSA-44 cases of NIST's ACVP keyGen vectors (`bench/pf13/acvp_keygen.json`) rather than
`mldsa44.py`; vector in `contracts/docs/key-backup-v0.2.md`.

New HKDF salt `starknet-pq-backup-v0.2`, used only for new schemes; v0 and v0.1 code and vectors
are untouched and `backup_fixtures_check.mjs` keeps pinning them.

- `seed32 = HKDF-SHA512(ikm = BIP39 seed, salt = "starknet-pq-backup-v0.2",
  info = "ml-dsa-44/fips204/account/i", L = 32)`, then `ML-DSA.KeyGen_internal(seed32)`.
- FIPS 204 fully specifies key generation from that seed, so unlike the Falcon profiles the key
  does not depend on one library. The vectors test checks noble against the lane reference
  (`mldsa44.py`).
- `deriveAccountKeys(mnemonic, index, ecdsaProfile, scheme = "falcon-512")`; document in
  `contracts/docs/key-backup-v0.2.md`. `recovery/` proves the ECDSA derivation only and is unaffected.

### 7. Correctness suite (`bench/pf13`, PF-03 pattern)

Authority: `reference/mldsa44.py`, pinned by SHA-256. Every vector runs through three paths and
each must equal the reference: baseline from scratch, pinned record from scratch, pinned record
through setup and the cached check.

- Valid: the 45 ACVP sigVer cases in the baseline crate, noble signatures through the adapter,
  messages 0 and p − 1.
- Edges: largest |z| = 130,994 rejected and 130,993 accepted; 80 hints accepted.
- Malformed: every hint `HintBitUnpack` refuses (counts falling or passing 80, positions out of
  order or repeated, a non-zero byte after the last), felts with a bit above their bytes, wrong
  lengths.
- Tampered: message, c-tilde, z, hints, key; a cache built for another key; a tampered cache slot.
- The lane's recorded break (`REJECTS_VALID`, ExpandA flag carry), if its vector is published.
- Rejection cost: worst invalid at most 1.25 times worst valid, as a regression target.

CI job beside `falcon-differential`.

Status 2026-11-19: done (`bench/pf13/correctness`): 128 vectors (21 valid, 107 invalid), all three
paths agree with the reference; 10 cache tests; 45 ACVP sigVer cases on the baseline only (the record does not
expose `verify_internal`). Rejection cost ratio 1.000. The lane's break vector is not published.

### 8. Account-level gas (`bench/pf13`, PF-04 pattern)

Reuse `class_size` and the limit tables from `bench/pf04/summarize.py` by import. Paired snforge
tests on a V2 account with the ML-DSA verifier: `__validate__` mean and worst,
`__validate_declare__`, `is_valid_signature`, rejected signature, `set_pq_key` from Falcon-512,
migration (`upgrade` + `migrate`) straight to ML-DSA, steps on the worst vector. `budgets.json` at
measured + 1%, class table, clean build against the network libfunc list. This is the Starknet
Foundry half of acceptance criterion 2.

Status 2026-11-19: done (`bench/pf13/gas`, numbers in bench/pf13/README.md), `budgets.json` checked in CI.

### 9. Docs and manifest

`scripts/release_manifest.mjs` and a new manifest (not `testnet-v1.json`) list V2, the verifier and
the setup class with `scheme` and `setup`. README table, `NOTICE.md`, `wallet-coverage.md`,
`scheme-switch.md`. The browser page and hosted demo are not changed.

Status 2026-11-19: docs done (README, NOTICE, scheme-switch.md, key-backup-v0.2.md). The manifest and
`wallet-coverage.md` wait for step 10: they record declared class hashes and Sepolia receipts.

### 10. Sepolia receipts — needs your authorization

Declare V2, the verifier and the setup class (PF-04 paid 103 STRK for a 5.4e9 declare). Then, with
fresh public test keys: migrate one Argent 0.5.0 and one Braavos account straight to ML-DSA; move
one migrated Falcon-512 account with `[upgrade, set_pq_key]`; a hybrid transfer on each; an
ECDSA-only transfer rejected. Receipts into `bench/pf13/sepolia.json`. This is the Sepolia half of
acceptance criterion 2.

Status 2026-11-26: done (bench/pf13/README.md, `sepolia.json`). Declared from a scarb 2.22.0 build:
the Sepolia gateway accepted only Sierra 1.10.0. Argent 0.5.0 and Braavos 1.2.0 migrated straight to
ML-DSA-44, a Falcon-512 account moved with `[upgrade, set_pq_key]`; hybrid transfers succeeded,
ECDSA-only rejected. The move needs about 45K L1 data gas; the first attempts bounded it at 5,000
and reverted (recorded). Step 9's manifest follows the toolchain change.

Status 2026-11-26, step 9: the toolchain change is merged (PR #42) and a 2.22.0 build reproduces the
three declared class hashes, so the manifest and `wallet-coverage.md` can now be written.

Status 2026-11-26, step 9: done. `release/testnet-v2.json` pins the three declared classes
(`release_manifest.mjs --release testnet-v2`; `--check` in CI on the 2.22.0 build, `--chain`
confirms the declare transactions); `testnet-v1` writes back byte-identical. `wallet-coverage.md`
has an ML-DSA-44 section. Not done: `verifiers.mjs` and the kit still read `testnet-v1` only; the
scheme table that dispatches on the manifest's `scheme` is PF-14 A5/A8.

## Acceptance criteria

| Criterion | Closed by |
| --- | --- |
| Declare gas and class size computed; go / no-go recorded | step 4 |
| If go: validation and transfer gas on Starknet Foundry and on a Sepolia receipt | steps 8 and 10 |

## Not in this plan

- A browser signer page or hosted demo for ML-DSA: a separate, authorized rollout. Done anyway on
  2026-11-26: the page restores and signs with ML-DSA-44 keys (`7b49b05`), and PR #43 added a
  "Try ML-DSA-44" demo account (demo words index 2, `bench/pf13/demo-sepolia.json`: migration
  1.12e9 L2 gas from the page's OpenZeppelin class, against Sepolia's 1.21e9 cap; hybrid transfer
  44.7M; ECDSA-only rejected).
- Committing to the cache and passing it in the signature instead of reading 461 storage slots.
  Possibly several million gas per transaction, unmeasured; look at it only if step 8 shows the
  reads dominate.
- Hardware or HSM signer integration: the adapter takes any FIPS 204 signature, so nothing blocks it.

## Review

Unaudited design. Reusing the rotation proof for a scheme change, and the setup library call
running as trusted code in the account's storage, are security-relevant choices and need
independent review before any recommendation beyond testnet.
