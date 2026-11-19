# Provably Fast ML-DSA-44 patch: provenance

One patch from the Provably Fast ML-DSA-44 lane (https://postquantum.provably.fast/mldsa), pinned
for PF-13 (issue #21), applied on top of that lane's baseline, plus this project's cache module. It
is not audited, and neither it nor the baseline is reviewed or endorsed by OpenZeppelin.

## Baseline

- The lane's bundle, https://postquantum.provably.fast/mldsa/baseline.bundle, commit
  `78c83599f57ecb28847ba3ebc4528598318129b8` ("Add an ML-DSA-44 verifier"), whose parent is
  OpenZeppelin cairo-pq-verifiers `bece5c07eeea5784e570c01108ec000d2d04ae40`. Cloned and its commit
  checked 2026-11-19.
- Its `crates/ml_dsa_44` is vendored byte-identical at `vendor/cairo-pq-verifiers/crates/ml_dsa_44`.
  Its `crates/ntt`, `crates/falcon_512`, `crates/bench_interface` and `crates/ecdsa_stark` are
  byte-identical to the ones already vendored from `bece5c07` (checked 2026-11-19).

## Crate

`crates/ml_dsa_44_pf_record` is the baseline crate with the patch applied, `cache.cairo` added as
`src/verx/cache.cairo`, one `pub mod cache;` line appended to `src/verx.cairo`, and the package
renamed `pqbench_ml_dsa_44_pf_record`. Used by `HybridMlDsa44Verifier` and `MlDsa44KeySetup`
(`contracts/src/mldsa.cairo`). Generated, never edited by hand:

```sh
vendor/provably-fast/ml-dsa-44/make_crates.sh          # regenerate
vendor/provably-fast/ml-dsa-44/make_crates.sh --check  # CI: crates/ == baseline + patch + cache + renames
```

## Patch

Downloaded 2026-11-19 from
`https://postquantum.provably.fast/api/participation/mldsa/jobs/<JOB_ID>/patch`. Digest in
`SHA256SUMS`. It changes only `.cairo` files under `crates/ml_dsa_44/src`. Accepted challenge
patches are MIT (https://postquantum.provably.fast/agent-brief.md).

| File | Job | Board score (L2 gas, mean / worst) | Board account CASM felts / class bytes | Author |
| --- | --- | ---: | ---: | --- |
| `record-mj_2e2f9ddebbcc4281b07d84937ae0ffbc.patch` | `mj_2e2f9ddebbcc4281b07d84937ae0ffbc` | 169,708,897 / 169,897,155 | 61,422 / 3,057,372 | solanaqubits |

The baseline job scores 618,093,928.

## Cache module (`cache.cairo`, this project's)

A port of the board's `https://postquantum.provably.fast/mldsa/account/cairo/cache.cairo`
(downloaded 2026-11-19, SHA-256 `d519d789364ab7469b46ba178a0b8053faf099c867a5bc1cb30dd83bef2da76d`),
which was written for the 22 Oct record `mj_eed20939` and does not build against later records: they
renamed the functions it calls. The port changes only names and types: `precompute` is the
record's `lah` + `x2::xai` + `x2::uab`, and `verify_cached` is the record's `verx::tac` line for line,
with `tr` and A-hat taken from the cache instead of `xai` / `uab`. `pack_a` / `unpack_a` are the
board's, on the record's `sa0::Za` (the same `BoundedInt<0, 0xffffff>` as the board's `C24`).
`cache.cairo` is in `SHA256SUMS`, so a change to it is a change to the pin.

Checked 2026-11-19 in a scratch build of the baseline + patch + cache: the crate's 70 felt tests
(`tests/felts.cairo`, each asserting the reference's verdict) pass through `precompute` +
`verify_cached` as they do through `MlDsa44Verifier::verify` (191 tests passed in all, the crate's
own included). Not yet in CI (PF-13 step 7).

## Board state at download

`results-snapshot-2026-11-19.json` is the full response of
`https://postquantum.provably.fast/api/participation/mldsa/results` at download time
(SHA-256 `188a9dd269279237e4a8ded2fe848950e97e856409b7d57d30b8a3876579690c`).

- `mj_2e2f9dde` was submitted 2026-11-16, `attacks_withstood: 1`, not broken. Two records were
  submitted after it on 2026-11-19, both building on it: `mj_72178eb8` (169,703,823, 1 round) and
  `mj_dd8cba30` (169,697,824, 0 rounds), 5,074 and 11,073 gas cheaper from scratch. Neither is pinned:
  the difference is noise next to the cached check, and the second has not been attacked.
- The lane has one break, `REJECTS_VALID` (a valid signature rejected through an ExpandA flag
  carry) by `mj_8c3bebbe` against `mj_c13c474a`. That job is not in this record's `builds_on`
  lineage as far as the snapshot shows. Check `breaks` and the board again before relying on it; a
  later break does not change these pinned bytes.

## Contributors

The record builds on `mj_09897da7` (lyskey1). Following `builds_on` through the snapshot reaches 5
jobs by lyskey1, rukafe0x and solanaqubits. `builds_on` is self-reported; the board's contributor
lists are the authority for credit.

## Known review limitations

- The patch is minified (single- and three-letter identifiers, whole functions on one line).
- The patch is 261,685 bytes, just under the lane's 256 KiB limit.
- `verify_cached` panics instead of returning false if a cache slot holds a value no `precompute`
  writes. Only `MlDsa44KeySetup` writes the cache, inside the account's own `set_pq_key` / `migrate`.
