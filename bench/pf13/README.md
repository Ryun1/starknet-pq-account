# PF-13: ML-DSA-44 (FIPS 204) hybrid verifier

Issue #21. ML-DSA-44 for `HybridMigratableAccountV2` ([scheme-switch.md](../../contracts/docs/scheme-switch.md))
as two classes, `HybridMlDsa44Verifier` and `MlDsa44KeySetup` (`contracts/src/mldsa.cairo`), built on
the Provably Fast record `mj_2e2f9dde` ([PROVENANCE](../../vendor/provably-fast/ml-dsa-44/PROVENANCE.md)).
Experimental, unaudited, testnet only; nothing here is declared on Sepolia.

## Go / no-go: **go** (2026-11-19)

Acceptance criterion 1, "declare gas and class size computed; go / no-go recorded". Every gate of
the plan passes, with margin:

| Gate | Threshold | Measured |
| --- | --- | --- |
| Verifier class declare | ≤ 95% of 5.8e9 | 3.78e9, **65.2%** |
| Setup class declare | ≤ 95% of 5.8e9 | 2.01e9, **34.7%** |
| Class limits (both) | CASM, Sierra ≤ 81,920 felts; class ≤ 4,089,446 bytes | largest: 50,158 CASM, 42,207 Sierra, 2,221,816 bytes |
| `__validate__`, worst | ≤ 60M L2 gas, ≤ 1M steps | **40.6M**, 337,502 steps |
| `set_pq_key` from Falcon-512, `migrate` | ≤ 1.11e9 execution gas, ≤ 10M steps | 414M / 420M, 1,461,539 steps |
| Network libfunc list | every class builds | yes (`bench/pf04/network_libfuncs.json`, deny) |
| Pinned record | unbroken, ≥ 1 attack round withstood | `mj_2e2f9dde`: unbroken, 1 round |

The plan expected a single verifier class at 88–93% of the block cap. Splitting the one-time ExpandA
code into the setup class leaves the verifier at 65%.

## Design

- **Verifier** (`is_valid_signature` only, library-called in `__validate__`): ECDSA first, then the
  record's check with tr and A-hat read from the account's storage: 43-felt key, 79-felt ML-DSA
  signature, 81-felt hybrid signature.
- **Setup** (`setup_pq_key()`, library-called once by `set_pq_key` / `migrate`): computes tr and A-hat
  from the stored key and writes them to 419 slots at two bases from `selector!("MlDsa44_cache_0")`
  and `_1`: tr (8), A-hat (410, ten 24-bit coefficients per felt), then the Poseidon digest of the key.
- The digest is an addition to the plan's 418-slot cache. The verifier rejects when it does not
  match the stored key, so a key written without the setup (or with another scheme's) cannot be
  checked against a cache left by an earlier ML-DSA key. `mldsa_rotation_needs_the_setup_again`
  covers it.
- The cache is computed on chain from the key, never passed in: it is a public function of the key,
  so it changes nothing about which signatures are accepted.

## Results

### Validation and calls (`gas/`, snforge L2 gas)

`HybridMigratableAccountV2` on the ML-DSA-44 verifier over the 12 valid vectors of `vectors.json`
(noble, 3 keys, messages 0, p − 1 and two others per key).

| Path | L2 gas | of the 100M validation cap |
| --- | ---: | ---: |
| `__validate__`, mean | 40,466,574 | 40.5% |
| `__validate__`, worst | 40,636,546 | 40.6% |
| `__validate_declare__`, worst of selected | 40,631,046 | 40.6% |
| `is_valid_signature`, worst of selected | 40,892,786 | 40.9% |
| rejected signature (valid ECDSA, ML-DSA of another message), worst of selected | 40,892,306 | 40.9% |
| `set_pq_key` Falcon-512 → ML-DSA-44 (in `__execute__`) | 414,139,287 | not validation |
| `migrate` straight to ML-DSA-44 (in `__execute__`) | 420,352,361 | not validation |

Cairo steps: `__validate__` on the worst vector 337,502 (cap 1,000,000); `set_pq_key` 1,461,539
(cap 10,000,000). A rejected signature costs the same as an accepted one.

For comparison: Falcon-512 (`HybridShakeVerifierPfSmallKeyRead`) validates at 26.5M, Falcon-1024 at
51.3M mean (bench/pf14). The board measured 45.8M for its cached account on the 22 Oct record.

Split of the record's work, measured in a scratch build of the crate (snforge, not account level):

| | L2 gas |
| --- | ---: |
| `MlDsa44Verifier::verify` from scratch (bench input) | 169,742,627 |
| `precompute` (tr, A-hat, packing) | 164,239,011 |
| `verify_cached` | 29,205,866 |

So the account adds about 11.4M to the cached check: reading the key and the 419 cache slots, ECDSA
and the library call. Reading the cache from calldata under a commitment instead might save part of that;
not attempted (see the plan's "Not in this plan").

### Declare size

| Class | CASM felts | Sierra felts | Class object bytes | Declare L2 gas | of 5.8e9 block cap |
| --- | ---: | ---: | ---: | ---: | ---: |
| `HybridMlDsa44Verifier` | 50,158 | 42,207 | 2,221,816 | 3,784,184,320 | 65.2% |
| `MlDsa44KeySetup` | 28,557 | 20,585 | 1,012,250 | 2,013,356,800 | 34.7% |
| `HybridMigratableAccountV2` | 9,748 | 4,564 | 238,125 | 593,775,360 | 10.2% |

Only `mj_2e2f9dde` was built. The plan named a second candidate, the 22 Oct record `mj_eed20939`
(the board's cache was written for it) or `mj_366ff85e` (199.1M, 10 rounds withstood). Not screened:
`mj_eed20939` is no longer among the board's records, `mj_366ff85e` is 29M more expensive from scratch, and the record passes every gate. They
remain the fallback if the record is broken.

### Correctness so far

- `contracts/src/tests_scheme.cairo`, ML-DSA section (8 tests, fixture `tests_mldsa_fixture.cairo`
  from `signer/mldsa_fixture.mjs`): Falcon-512 → ML-DSA-44 → Falcon-512, a v1 account moving in one
  `[upgrade, set_pq_key]` transaction, an Argent-style account migrating straight to ML-DSA-44,
  rotation within ML-DSA-44 (refused without the setup, accepted with it), and reverts for a missing
  setup, a Falcon key under the setup, an ML-DSA key under a Falcon verifier and a raw verifier switch.
### Differential suite (`correctness/`, plan step 7)

Authority: the lane's reference verifier https://postquantum.provably.fast/reference/mldsa44.py,
SHA-256 `02c79ee38eab5bb89c451ead196eb481ba80e9115ec73554a1f437f0fb4c56d8` (checked by
`gen_vectors.py`; downloaded 2026-11-19, read in full, stdlib only). Every vector's `expected` is its
`verify_felts` verdict. Each vector runs through three paths, and each must equal the reference:
the baseline from scratch, the pinned record from scratch, and the record through
`cache::precompute` + `cache::verify_cached` (a key `precompute` refuses counts as a rejection, as
`MlDsa44KeySetup` panics on it). CI job `mldsa44-differential`.

| Category | Valid | Invalid | Contents |
| --- | ---: | ---: | --- |
| valid | 19 | | the baseline crate's felt tests (dilithium-py, messages 0, 1, p − 1), 12 noble signatures |
| edge | 2 | 13 | largest valid \|z\| = 130,993 accepted, 130,994 rejected; a valid signature with 80 hints; the crate's z-bound tests |
| malformed | | 55 | every HintBitUnpack refusal (count past 80, counts falling, positions repeated or out of order, a non-zero byte after the last), bits above a felt's bytes, wrong key and signature lengths |
| tampered | | 39 | message (+1, p − 1), c-tilde, z coefficients, a hint position, the key's rho and t1 |
| **all** | **21** | **107** | 128 vectors, all three paths agree with the reference |

Also: 10 cache tests (`src/cache_tests.cairo`; key A's signature against key B's cache, B's tr or
B's A-hat alone, a tampered first / last tr slot, a tampered first / middle / last A-hat slot, a
short A-hat: all rejected, A's own cache accepted), and the baseline crate's 45 NIST ACVP sigVer
tests (baseline only: they use the byte-level `verify_internal` / `verify_mu` with contexts and
external mu, which the record does not expose).

Rejection cost (cairo-test gas estimate, `verify` alone; for `cached`, `verify_cached` alone):

| Path | Worst valid | Worst invalid | Ratio |
| --- | ---: | ---: | ---: |
| baseline | 618,159,133 | 618,083,423 | 1.000 |
| record | 170,188,799 | 170,128,489 | 1.000 |
| cached | 29,441,070 | 29,380,760 | 0.998 |

The edge signatures come from a small FIPS 204 signer in `gen_vectors.py` (seeded y, uniform
small secrets); only the public key and signature are judged, by the reference. The lane's one
break (`REJECTS_VALID`, `mj_8c3bebbe`) is not included: the board publishes only its digest, not the
vector.

## Reproduce

```sh
node bench/pf13/noble_vectors.mjs > bench/pf13/vectors.json   # deterministic; after npm install in signer/
node signer/mldsa_fixture.mjs                                  # contracts/src/tests_mldsa_fixture.cairo
vendor/provably-fast/ml-dsa-44/make_crates.sh --check
(cd contracts && scarb cairo-test -f mldsa)
python3 -I bench/pf13/correctness/gen_vectors.py --reference PATH/mldsa44.py   # deterministic, ~10 s
bench/pf13/correctness/run.sh    # CI: differential suite, ACVP, cache tests; writes correctness/results.json
bench/pf13/gas/run.sh            # gas, steps, class sizes, network libfuncs; writes gas/results.json
bench/pf13/gas/run.sh --check    # CI: same, against gas/budgets.json
```

`gas/run.sh` needs scarb 2.18.0, snforge 0.59.0 and universal-sierra-compiler 2.10.2, as
bench/pf14/gas.

## Remaining plan steps

6 key backup profile v0.2, 9 docs and manifest, 10 Sepolia receipts (needs
authorization). Step 5 (signer adapter) is in: `signer/mldsa_adapter.mjs`.
