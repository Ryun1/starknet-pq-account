# PF-14 implementation plan: NIST level 5 (Falcon-1024 class, ML-DSA-87 write-up)

Issue: https://github.com/Ryun1/starknet-pq-account/issues/22. Planned 2026-11-19. Board figures
are external; figures marked "est." were estimates, since replaced by the measurements in steps A2
and A7.

**Progress, 2026-11-26.** Part A steps A1–A8 merged in PR #37, Part B in PR #38; both acceptance
criteria closed. Benches re-measured on scarb 2.22.0 in PR #42. A9 and A8's manifest entry done
(PR #43, then the Falcon-512 move and release `testnet-v2`'s Falcon-1024 entry in PR #45). Every step is done. Not done: the kit's per-scheme allow list (see
`bench/pf14/README.md`).

Depends on step 1 of the PF-13 plan (`PF-13-ml-dsa-44.md`, `HybridMigratableAccountV2` and
`set_pq_key`) and on nothing else in PF-13. Part A can therefore be built before ML-DSA-44, and
should be: it is the smaller change and the first real user of the scheme switch.

## What changed since the issue was written

Read from `postquantum.provably.fast/api/participation/{falcon1024,mldsa87}/results` on 2026-11-19.

| | Issue (2026-10-27) | Board, 2026-11-19 |
| --- | --- | --- |
| Falcon-1024 record | 52.9M | 49,132,102 mean, 49,958,763 worst (`fk_2956035507114a6c89165c8cc8e8fe56`, 2026-11-16, 1 attack round withstood); 52.5M per transaction on the board's page |
| Falcon-1024 record's account class | not stated | 61,351 CASM felts, 3,064,804 class bytes; est. 5.1–5.4e9 declare L2 gas (88–93% of the block cap) |
| Falcon-1024 breaks | — | 6, all `COSTLY_REJECTION`, none against the record |
| ML-DSA-87 record | 90.3M, ~2.4B setup | 86,424,864 (`mk_6398ba24905340188781b551499160e4`, submitted 2026-11-19, no attack round yet); setup 3,096,494,364 in parts under 900M each |
| ML-DSA-87 breaks | the c-tilde break | 35 entries, all `ACCEPTS_INVALID` (the c-tilde input replayed against many jobs) |

The declare estimate uses the published CASM felts and class bytes with the bytes-per-Sierra-felt
range of our three PF Falcon-512 classes (43.9–48.9); Sierra felts are not published.

ML-DSA-87 leaves 13.6M under the 100M validation cap. The issue asks for 50M before a class is
considered, so Part B stays a write-up.

One correction to the issue's framing. The verifier is a replaceable class, as hoped, but the
deployed migratable classes hard-code the 29-felt key in three places (`_register`,
`_falcon_registered`, `rotate_falcon_public_key`), so a 57-felt key cannot be stored without one
new account class. That class is scheme-agnostic (PF-13 step 1), so it is needed once, not per
scheme.

## Part A: Falcon-1024 hybrid verifier

Sizes: key 57 felts, signature 116 felts (s1 57, salt 2, hint 57), hybrid signature 118 felts.

### A1. Vendor and pin

`vendor/provably-fast/falcon-1024/`: the baseline crate `falcon_1024` from the lane's bundle at
commit `bf7fd8785a189164d638e7f7c11d261c9e864d56` (its `ntt` and `falcon_512` crates are
byte-identical to our vendored baseline, checked 2026-11-19), the pinned record patch,
`SHA256SUMS`, `PROVENANCE.md` with the `builds_on` contributors, and a results snapshot.

`make_crates.sh` takes a lane argument (shared with PF-13 step 2). The record patch changes
`crates/falcon_1024/src` and `crates/ntt/src` (it adds `typed_ntt.cairo`), so the generated pair is
`pqbench_falcon_1024_pf_<name>` and `pqbench_ntt_f1024_pf_<name>`, renamed as the Falcon-512
candidates are. CI runs `--check` for every lane.

### A2. Screen and select

`bench/pf04/screen.sh` with a lane argument (API path, job-id prefix `fk_`, allowed patch paths
`crates/(falcon_1024|ntt)/src/…`, class name). Screen the record and three or four smaller or older
unbroken entries, for example `fk_91eb8438…` (60,046 CASM felts) and `fk_f5cc81df…` (2,993,086
class bytes). For each: CASM felts, Sierra felts, class bytes, declare L2 gas, attack rounds.

Select as PF-04 did: the cheapest unbroken entry whose declare is at most 95% of 5.8e9 and that
builds against both the audited list and `network_libfuncs.json`. This closes the declare half of
acceptance criterion 1.

### A3. Verifier class

`HybridShakeVerifierFalcon1024` in `contracts/src/hybrid.cairo`: the same 20-line module as
`HybridShakeVerifierPfSmallKeyRead`, with `Falcon1024Verifier` from the generated crate.
`verify_hybrid`, `HybridAccountComponent` and `read_falcon_public_key_once` do not know the key
length (the verifier checks it), so the component is unchanged. One dependency line in
`contracts/Scarb.toml`. Existing classes stay byte-identical.

### A4. Account

`HybridMigratableAccountV2` from PF-13 step 1. Falcon-1024 has no setup class, so
`setup_class_hash` is zero. Routes: a migrated Falcon-512 account moves with
`[upgrade(V2), set_pq_key(key1024, verifier1024, 0, proof)]`; an unmigrated wallet migrates
straight to Falcon-1024 with the V2 class.

Add to `tests_scheme.cairo`: Falcon-512 → Falcon-1024 → Falcon-512; a 29-felt key with the 1024
verifier reverts on the proof; a 512 signature after the switch is rejected; a raw
`set_verifier_class_hash` to the 1024 verifier reverts with `Migratable: verifier rejects`.

### A5. Signer

`signer/falcon_adapter.mjs`, parametrised by n instead of copied:

- headers: public key `0x0A`, 1,793 bytes; signature `0x3A`; salt still 40 bytes;
- packing: 56 felts of 18 coefficients, then a last felt holding sixteen (nine low, seven high),
  not the eight-low last felt of Falcon-512;
- `mulNegacyclic` and the NTT at n = 1024.

NTT roots: `scripts/export_ntt_roots.py` stops at 512. Export n = 1024 to a **new** file,
`signer/falcon1024_ntt_roots.json`. `falcon_ntt_roots.json` stays byte-identical, so
`build_page.mjs --check` and the hosted page are untouched.

noble `falcon1024` is exported by the pinned 0.6.1. Add `falcon-1024` to the kit's scheme table.

### A6. Key backup profile v0.2

Same profile as PF-13 step 6 (salt `starknet-pq-backup-v0.2`; v0 and v0.1 untouched):
`seed48 = HKDF-SHA512(…, info = "falcon-1024/noble/account/i", L = 48)`, then
`falcon1024.keygen(seed48)`. As in v0.1, the key is defined by that library's key generation;
say so in `key-backup-v0.2.md`.

### A7. Correctness and gas (`bench/pf14`)

Correctness, PF-03 pattern. Authority: `reference/falcon1024.py`, pinned by SHA-256. Baseline and
pinned candidate must both equal it on every vector:

- valid: falcon.py at n = 1024 and noble through the adapter; messages 0 and p − 1; salts needing
  16 and 17 SHAKE blocks and the most expensive word counts found;
- norm bound 70,265,242 approached from both sides;
- tampered: message, salt halves, swapped felts, s1 with and without re-hinting, hint, another key;
- malformed: non-canonical halves, the sixteen-coefficient last felt, salt out of range, wrong lengths;
- rejection cost: every break in this lane is a costly rejection, so assert worst invalid at most
  1.25 times worst valid, and include the published break vector if it can be obtained.

Gas, PF-04 pattern, importing `class_size` and the limit tables from `bench/pf04/summarize.py`:
`__validate__` mean and worst on a V2 account, `__validate_declare__`, `is_valid_signature`,
rejected signature, `set_pq_key` from Falcon-512, migration straight to Falcon-1024, steps on the
worst vector, `budgets.json`, class table, network libfunc build.

Expectation: est. 52–53M per validation (49.1–50.0M verification, about 2.3M to read 57 felts
with the length read once, about 0.4M for ECDSA and the library call), 47% under the cap. This
closes the validation half of acceptance criterion 1.

CI: a differential job and a budgets job, beside the Falcon-512 ones.

### A8. Docs and manifest

The same new manifest as PF-13 step 9 lists the class with `scheme: falcon-1024`. README table,
`NOTICE.md`, `PROVENANCE.md`. The browser page and hosted demo are not changed.

### A9. Sepolia receipts — needs your authorization

Declare the verifier (and V2 if PF-13 has not). With fresh public test keys: one wallet migrated
straight to Falcon-1024, one Falcon-512 account moved with `[upgrade, set_pq_key]`, a hybrid
transfer on each, an ECDSA-only transfer rejected. Receipts into `bench/pf14/sepolia.json`.

Status 2026-11-26: partly done in PR #43. `HybridShakeVerifierFalcon1024` declared from a scarb
2.22.0 build (`0x647ae0aa…`, 4.43e9 L2 gas). The public demo account (demo words index 1) migrated
straight to Falcon-1024 (171.8M L2 gas), hybrid transfer 54.2M, ECDSA-only rejected; receipts in
`bench/pf14/sepolia.json`.

Status 2026-11-26: done. A fresh Argent 0.5.0 account migrated to testnet-v1 Falcon-512 and then
moved with one hybrid-signed `[upgrade V2, set_pq_key Falcon-1024]`: 115.7M L2 gas, 4,832 L1 data
gas, 3.38 STRK; hybrid transfer 54.2M; ECDSA-only rejected; stored keys equal the words' keys,
balance drop equals the fee. `signer/pf13_sepolia.mjs` with `PQ_TARGET=falcon-1024`; receipts in
`bench/pf14/a9-sepolia.json` (`sepolia.json` stays the demo account's). A8's manifest entry:
release `testnet-v2` lists the verifier with `scheme: falcon-1024` and its declare transaction.

## Part B: ML-DSA-87, write-up only

Status 2026-11-19: done, PR #38. `bench/pf14/ml-dsa-87.md`, board snapshot beside it, and
`screen.sh --lane mldsa87`. The record moved to `mk_94cd1f15` (86,413,257). Its cache is 1,641 felts in
7 parts, not 1,667. Declare 4.43e9 (76.4%), validation steps 698,755, largest setup part 725M.

`bench/pf14/ml-dsa-87.md`. No class, no vendored code.

- Screen: the lane scores `MlDsa87Account` itself, so run the generalised `screen.sh` on the
  record's account as published (lane `mldsa87`, `mk_` ids) for CASM, Sierra, class bytes and
  declare gas. Est. 5.0–5.3e9 from the board's 60,878 CASM felts and 3,045,698 bytes.
- Costs: 86.4M validation, 3.10B setup across the record's parts, each under 900M. Hybrid adds
  ECDSA and a library call, est. under 0.5M.
- Break history: what the partial c-tilde check was and how it passed scoring, from the published
  break titles and the broken jobs' patches; the count of replays; which records have withstood
  hammer rounds.
- What our account would need: 84-felt key, 150-felt signature, a 1,641-felt cache (record). Setup exceeds
  one transaction's 1.11e9 execution cap, so V2's single `setup_pq_key()` call cannot do it. It
  would take one more self-only entry point to run setup in parts before `set_pq_key`. Not added
  now; an account can `upgrade` to a class that has it.
- Trigger to revisit, recorded explicitly: a record at or under 50M validation gas, unbroken
  through several hammer rounds, with a declarable class.

## Key-rotation and verifier-switch design (acceptance criterion 2)

`contracts/docs/scheme-switch.md`, written in PF-13 step 1: the routes table, why the proof is
checked by the new verifier in `__execute__`, what reverts and what state survives a revert, and
the limits (the setup and verifier classes are trusted code in the account's storage; a raw
`set_verifier_class_hash` to another scheme reverts on V2 but still locks an account on the
classes deployed before 2026-11-16, so the kit's allowlist is per scheme; a level-5 account can be
moved back to a weaker scheme by its own hybrid signature).

## Acceptance criteria

| Criterion | Closed by |
| --- | --- |
| Falcon-1024 declare gas and validation gas measured | A2 and A7 |
| Key-rotation and verifier-switch design for a scheme change written up | PF-13 step 1 (`scheme-switch.md`), exercised by A4 |

## Order (decided 2026-11-19)

0. Fast-forward this fork to upstream main (the issue #35 merge landed 2026-11-16, 0xjuno PR #1);
   V2 is cut from that `migratable.cairo`. A1–A3 and A5 do not touch that file.
1. PF-13 step 1: account V2, tested with the two Falcon-512 schemes that exist today.
2. PF-14 Part A.
3. PF-13 steps 2–10.
4. PF-14 Part B, any time; it needs only the generalised screen.

## Review

Unaudited design; the board's records are contest code, attacked but not audited. The issue's
reference to CNSA 2.0 is not verified here and should be checked against the primary source before
it is repeated in documentation.
