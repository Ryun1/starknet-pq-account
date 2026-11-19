# Provably Fast Falcon-1024 patch: provenance

One patch from the Provably Fast Falcon-1024 lane (https://postquantum.provably.fast/falcon1024),
pinned for PF-14 (issue #22), applied on top of that lane's baseline. It is not audited, and
neither it nor the baseline is reviewed or endorsed by OpenZeppelin.

## Baseline

- The lane's bundle, https://postquantum.provably.fast/falcon1024/baseline.bundle, commit
  `bf7fd8785a189164d638e7f7c11d261c9e864d56` ("Add a Falcon-1024 verifier"), whose parent is
  OpenZeppelin cairo-pq-verifiers `bece5c07eeea5784e570c01108ec000d2d04ae40`. Cloned and its commit
  checked 2026-11-19.
- Its `crates/falcon_1024` is vendored byte-identical at `vendor/cairo-pq-verifiers/crates/falcon_1024`
  (beside the other baseline crates, so its `pqbench_ntt = { path = "../ntt" }` resolves unchanged).
  Its `crates/ntt`, `crates/falcon_512` and `crates/bench_interface` are byte-identical to the
  ones already vendored from `bece5c07` (checked 2026-11-19), so nothing else changes.

## Crates

`crates/` holds the `falcon_1024` + `ntt` pair with the patch applied, used by
`HybridShakeVerifierFalcon1024` (`contracts/src/hybrid.cairo`). Generated, never edited by hand:

```sh
vendor/provably-fast/falcon-1024/make_crates.sh          # regenerate
vendor/provably-fast/falcon-1024/make_crates.sh --check  # CI: crates/ == baseline + patch + renames
```

The only change besides the patch is the package names, `pqbench_falcon_1024_pf_record` and
`pqbench_ntt_f1024_pf_record`, and the `use` paths that name them (Scarb cannot load two packages
with the same name; `_f1024` keeps the NTT apart from the Falcon-512 candidates' `pqbench_ntt_pf_record`).

## Patch

Downloaded 2026-11-19 from
`https://postquantum.provably.fast/api/participation/falcon1024/jobs/<JOB_ID>/patch`. Digest in
`SHA256SUMS`. It changes only `.cairo` files under `crates/falcon_1024/src` and `crates/ntt/src`, and
adds `crates/falcon_1024/src/fk.cairo` and `crates/ntt/src/typed_ntt.cairo`. Accepted challenge
patches are MIT (https://postquantum.provably.fast/agent-brief.md).

| File | Job | Board score (L2 gas, mean / worst) | Board account CASM felts / class bytes | Author |
| --- | --- | ---: | ---: | --- |
| `record-fk_2956035507114a6c89165c8cc8e8fe56.patch` | `fk_2956035507114a6c89165c8cc8e8fe56` | 49,132,102 / 49,958,763 | 61,351 / 3,064,804 | rukafe0x |

The baseline job scores 143,304,166.

## Board state at download

`results-snapshot-2026-11-19.json` is the full response of
`https://postquantum.provably.fast/api/participation/falcon1024/results` at download time
(SHA-256 `4e27468c21c7b12d7edaf0fa0dd8ccf7809fd2487638a71566554a1a593a1dad`).

- `fk_29560355` was the record, submitted 2026-11-16, `attacks_withstood: 1`, not broken.
- The lane had six breaks, all `COSTLY_REJECTION` (a rejection costing more than 1.25 times the
  target's worst valid verification), none against this job. All six were against its own
  ancestors through `builds_on` (`fk_6eba4efb`, `fk_a02e7ae9`, `fk_557f4fd8`, `fk_b619640e`,
  `fk_343e4f21`, `fk_1280c59e`). Every break's input joins all later
  checks, so this job passed those inputs when it was scored; the lineage is why its rejection
  cost deserves a look in any review. Check `breaks` and the board again before relying on it; a
  later break does not change these pinned bytes.

## Contributors

The record builds on `fk_1b83ad24` (lyskey1) and `fk_9308a17e` (rukafe0x). Following `builds_on`
through the snapshot reaches 21 jobs by ardianreffa, binharold, lyskey1, nadai2010 and rukafe0x;
one ancestor (`fk_1f587c3dd2ae4b4fb793e323337ef8e5`) is not in the snapshot. `builds_on` is
self-reported; the board's contributor lists are the authority for credit.

## Declare size

As `HybridShakeVerifierFalcon1024`, 59,762 CASM and 48,437 Sierra felts: 4.43e9 declare L2 gas, 76.4%
of the 5.8e9 block cap (bench/pf14). The four unbroken entries cheaper to validate need 105–107.5%
and cannot be declared; four more expensive ones screened between 60.1% and 75.9%. The record is
the cheapest that fits, so it is the one pinned.

## Known review limitations

- Large parts of the patch are minified (single-letter identifiers, whole modules on one line).
- It enables the unstable `bounded-int-utils` Cairo feature, as the Falcon-512 patches do.
- The patch is 261,860 bytes, just under the lane's 256 KiB limit; the board's account for it uses
  74.9% of the class limits.
