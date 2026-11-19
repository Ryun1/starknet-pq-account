# PF-14 Part B: ML-DSA-87, write-up only

Issue #22. Should this project add an ML-DSA-87 (FIPS 204, NIST level 5) verifier class? **Not yet.**
The best entry on the board fits the 100M validation cap with 13% to spare. The issue asks for 50M
before a class is considered. The current record has been through one hammer round. No class, no
vendored code and no account change come out of this; the figures below are what a later decision
would start from.

Board state: `mldsa87-results-snapshot-2026-11-19.json`, the full response of
`https://postquantum.provably.fast/api/participation/mldsa87/results` on 2026-11-19 14:04 UTC
(SHA-256 `f662d1356c87121a92f5df9ed39324f5f4ae7fd96ba799f12b30cd9ffe512b7e`). Contest code, attacked but not audited.

## The record

`mk_94cd1f15e1c94f189f3a3579bb166377`, "bits as two 64-bit helper calls instead of a while loop"
(rukafe0x, 2026-11-19 12:09 UTC). It replaced `mk_6398ba24`, the record when PF-14 was planned that
morning. Patch SHA-256
`019846949f4a9f309e93eaa0b3fcfa4d6252712ca1415787b7f288977a18d5be`. It changes only `crates/ml_dsa_87/src`, on the lane's
baseline `23d05d6a` ("Add an ML-DSA-87 verifier and account", parent OpenZeppelin cairo-pq-verifiers
`bece5c07`, the parent our Falcon crates are vendored from).

The lane scores its own account, `MlDsa87Account`. Its constructor stores the 84-felt key, then
`fill_cache` runs once per part (any caller; each part is a public function of the stored key) and
stores the key's work (tr, NTT(t1·2^d) and Â). `__validate__` reads the cache back and runs the rest
of Algorithm 8.

| | L2 gas | Limit | Source |
| --- | ---: | --- | --- |
| Validation, mean / worst | 86,413,257 / 86,507,584 | 100M (86.4% / 86.5%) | board |
| Validation, the lane's own vector | 86,329,084 | | measured, snforge 0.59.0 |
| Rejection, wrong message | 86,403,624 | | measured |
| Validation, Cairo steps | 698,755 | 1,000,000 (69.9%) | measured |
| Setup, deploy + 7 parts | 3,096,494,364 | | board (measured 3,096,517,714) |
| Largest setup part (part 3) | 725,185,690 | 1.11e9 per transaction (65.3%) | measured |
| Largest setup part, Cairo steps | 4,119,651 | 10,000,000 (41.2%) | measured |

Setup parts, measured: 207.4M, 374.3M, 457.5M, 725.2M, 302.0M, 426.7M, 558.2M L2 gas; 1.11M,
1.75M, 2.26M, 4.12M, 1.45M, 2.22M, 3.09M steps. Each fits one transaction. Limits are from the
sequencer's versioned constants 0.14.4 (`execute_max_sierra_gas` 1,110,000,000,
`invoke_tx_max_n_steps` 10,000,000, `validate_max_sierra_gas` 100,000,000, `validate_max_n_steps`
1,000,000), the version `bench/pf04` pins. Together they store 1,641 felts (1 of tr, then 2 × 820 of the matrix halves); the
baseline stored 1,667 in 9 parts. Setup writes about 166.6K of L1 data gas.

Measured by building the lane's baseline bundle with the record patch, in its own `pq-accounts`
tests: validation is `bench_validate_ml_dsa_87` minus `bench_baseline_ml_dsa_87`, steps with
`--tracked-resource cairo-steps`, setup parts as the difference between tests that fill k and k + 1
parts. Toolchain as the lane pins: scarb 2.18.0, snforge 0.59.0 (universal-sierra-compiler 2.10.2).

### Declare size

`bench/pf04/screen.sh --lane mldsa87` (new in this change) builds the lane's bundle with a job's patch
and measures `MlDsa87Account` against `bench/pf04/network_libfuncs.json`, with deny on. Same formula
as PF-04. Both entries build with the network's libfuncs.

| Job | Board mean | CASM felts | Sierra felts | Class bytes | Declare L2 gas | of 5.8e9 block cap |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `mk_94cd1f15` (record) | 86,413,257 | 61,259 | 46,778 | 3,053,361 | 4,428,499,200 | 76.4% |
| `mk_6398ba24` (previous record) | 86,424,864 | 60,878 | 46,641 | 3,045,698 | 4,407,281,920 | 76.0% |

CASM felts and class bytes equal the board's figures exactly. The plan estimated 5.0–5.3e9 from
the bytes-per-Sierra-felt ratio of our Falcon-512 classes (43.9–48.9). This class has about 65 bytes
per Sierra felt, so it has fewer Sierra felts than that ratio predicted.

## Break history

35 breaks, all `ACCEPTS_INVALID`, all on 2026-10-26, all one flaw. None since.

1. 07:06 UTC, `mk_1d9969f4` (akashneelesh) broke `mk_6466aca5`: "c_tilde' compared on its first 32
   of 64 bytes". In that patch, `verify.cairo` hashes μ ‖ w1Encode(w1) with one `keccak_syscall`. It
   pads the input for SHAKE-256 by hand. The syscall returns 256 bits, and the check is
   `h.low == c0 + c1·2^64 && h.high == c2 + c3·2^64`. Lanes c4..c7, bytes 32..63 of c̃, are never
   compared.
2. 11:14 UTC, `mk_dd797b79` (rukafe0x) broke `mk_04bcef3e`, which had the same comparison.
3. 12:04–12:16 UTC, the board's hammer replayed one vector (digest `8436ae9e`) against other
   entries and broke 33 more.

The vector, from the break titles: a key with t1 = 0, z = 0 and h = 0. Then w′ = Az − c·t1·2^d = 0
whatever c is, so w1 does not depend on c̃. Anyone can compute c̃′ = H(μ ‖ w1Encode(0)) and make a
signature for that key that FIPS 204 accepts. Flipping c̃'s second half makes the reference reject it,
but a verifier that compares only the first half still accepts. The entries scored, so the scoring
vectors cannot have included an input that changed only c̃'s second half. A real key is not this degenerate. The board
counts any accept the reference rejects as a break, and so would this project.

The current record has the broken patches' module layout (`fk`, `k2`, `nttu`, `packing`, `rowp`,
`zread`); its `builds_on` is empty, so the board does not record the lineage. Its final check (`keccak::shake256_pairs_packed`) now compares all eight c̃ lanes:
o0 against c0‖c1, o5 against c2‖c3, o1 against c5‖c6, and the low halves l10 and l6 against c4 and
c7. Read from the source, not proven; a review should check the lane mapping.

Hammer rounds: the lane's `attack_count` is 40. Four entries in the record chain show
`attacks_withstood: 1`: `mk_2456bdc3`, `mk_1ca901aa`, `mk_6398ba24` and the current record. None
shows more.

## What this project's account would need

Sizes: key 84 felts, signature 150 felts, hybrid signature 152 felts (gateway limit 4,000). Cache
1,641 felts.

- **Validation.** On `HybridMigratableAccountV2` the verifier class would run ECDSA, then the
  record's cached check against a cache in the account's storage, through the library call. The
  verifier does not need the 84-felt key (tr is in the cache). Est. +0.4–0.5M over the board figure
  for ECDSA and the library call (the PF-14 plan's figure; Part A did not measure them on their
  own): about 86.9M mean and 87.0M worst, 13% under the cap. Steps would rise slightly from 70% of
  the 1M cap.
- **Declare.** A verifier-only class drops the setup code (`cache::part`) and adds the small ECDSA
  path, so it should be at or below the 76.4% measured above (est., not built); the setup code would
  be a second, smaller class.
- **Setup.** 3.05B over 7 transactions. V2's `set_pq_key` makes one `setup_pq_key()` library call
  inside one transaction, capped at 1.11e9, so it cannot run this. And `set_pq_key` checks its proof
  through the new verifier in the same call, so the cache has to be complete first. That would take:
  a self-only entry point that stages the pending key and a setup class; a self-only entry point that
  fills one part per call from the pending key, into slots separate from the live cache (the
  account's current scheme may be ML-DSA too); then `set_pq_key` promotes the pending key and its
  cache. **Not added now.** An account can `upgrade` to a class that has these when the trigger
  below is met, and nothing in V2 rules that out.
- **Cost against Falcon-1024** (Part A, measured): 51.3M mean validation and no setup, against an
  est. 86.9M validation plus 3.1B of setup. The signature is 152 felts against 118, the key 84
  against 57. Declare sizes are about equal (both 76.4% of the block cap). For the same NIST level,
Falcon-1024 is cheaper on everything else here.

## Trigger to revisit

Reconsider a class when all three hold:

| Condition | Now |
| --- | --- |
| A record at or under 50M validation L2 gas | 86.4M: not met |
| Unbroken through several hammer rounds | 1 round: not met |
| Its class declarable (at most 95% of the block cap, network libfuncs) | 76.4%, builds: met |

Check with:

```sh
curl -s https://postquantum.provably.fast/api/participation/mldsa87/results \
  | python3 -c 'import json,sys; r=json.load(sys.stdin)["record"]; print(r["job_id"], r["score_l2_gas"], r["attacks_withstood"], r["broken_by"])'
bench/pf04/screen.sh --lane mldsa87 <record job id>
```

## Review

Unaudited. The record is minified contest code. A review would need to cover the c̃ lane mapping
above, the setup parts' bounds (`BOUNDS` in `cache.cairo`) and the rejection cost. Only one
rejection was measured here (wrong message, the same cost as a valid verification); a review would
need the full tampered and malformed set that Part A ran for Falcon-1024.
