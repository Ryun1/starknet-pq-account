# PF-13: ML-DSA-44 (FIPS 204) hybrid verifier

Issue #21. ML-DSA-44 for `HybridMigratableAccountV2` ([scheme-switch.md](../../contracts/docs/scheme-switch.md))
as two classes, `HybridMlDsa44Verifier` and `MlDsa44KeySetup` (`contracts/src/mldsa.cairo`), built on
the Provably Fast record `mj_2e2f9dde` ([PROVENANCE](../../vendor/provably-fast/ml-dsa-44/PROVENANCE.md)).
Experimental, unaudited, testnet only. Declared on Sepolia from a scarb 2.22.0 build (see [Sepolia receipts](#sepolia-receipts-plan-step-10-2026-11-26)).

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

**Under scarb 2.22.0** (2026-11-26; Sierra 1.10.0, snforge 0.64.1, universal-sierra-compiler
2.11.0-rc.1, the toolchain the classes were declared with): `__validate__` worst 43.4M (mean 43.2M),
verifier declare 3.88e9 (67.0%), setup 2.11e9 (36.4%), steps 365,029 (validation) and 1,586,724
(`set_pq_key`), `set_pq_key` 427M, `migrate` 431M. Every gate still passes; `gas/results.json` and
`gas/budgets.json` are this run. The tables below are the dated 2.18.0 run.

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

## Sepolia receipts (plan step 10, 2026-11-26)

Complete transactions on Sepolia (Starknet 0.14.4), collected by `signer/pf13_sepolia.mjs` into
[`sepolia.json`](sepolia.json) (hashes and receipts only; the test words stay in `.keys/`). Fees at
an L2 gas price of about 2.87e10 fri.

**Toolchain.** On 2026-11-26 the Sepolia gateway refused our scarb 2.18.0 build ("Sierra versions
older than 1.10.0 or newer than 1.10.0 are not supported"), so these classes are the **scarb 2.22.0
(Sierra 1.10.0)** build of this branch, not the 2.18.0 build the tables above measure. The
public RPC could not estimate a Sierra 1.10.0 declare ("Internal error"), so each declare was
bounded by the code-size formula + 20%.

| Declared class | Class hash | L2 gas | of 5.8e9 block cap | Fee (STRK) | Tx |
| --- | --- | ---: | ---: | ---: | --- |
| `HybridMigratableAccountV2` | `0x7c7c9de0…b154` | 589,502,400 | 10.2% | 17.04 | [`0x531e2875…`](https://sepolia.voyager.online/tx/0x531e2875a033559659bcd9e82030c2a903aea90c7aa87529af97d2c5b2e43e3) |
| `MlDsa44KeySetup` | `0x7aa0d9ef…e088` | 2,112,923,840 | 36.4% | 60.97 | [`0x65cbd374…`](https://sepolia.voyager.online/tx/0x65cbd374c750205134da3561e820eb62e71996c7fb0633b42d2b49dbe12b990) |
| `HybridMlDsa44Verifier` | `0x35cd62ee…5974` | 3,885,496,000 | 67.0% | 112.07 | [`0x55b2e1cf…`](https://sepolia.voyager.online/tx/0x55b2e1cf3bb6962e1778f77c6fce731d77953a12f6bfa59ecdf44a24718514b) |

Accounts, each from fresh words (ECDSA key by the wallet's own derivation, ML-DSA-44 key by
backup profile v0.2):

| Account | Path | Move: L2 gas / L1 data gas / fee | Hybrid transfer: L2 gas / fee |
| --- | --- | ---: | ---: |
| Argent 0.5.0 | `upgrade` straight to V2 + ML-DSA-44 ([tx](https://sepolia.voyager.online/tx/0x5b1aeaa665ba33cbe6ecc672271b4e6d38d9ee088d57e42883536c517c82f3b)) | 459,124,013 / 44,896 / 20.73 STRK | 44,781,406 / 1.32 STRK ([tx](https://sepolia.voyager.online/tx/0x7808144689c22d915638656ac0cc94bcd79048fa1495cb75803a5dca557f32f)) |
| Braavos 1.2.0 | `[upgrade, migrate]` straight to V2 + ML-DSA-44 ([tx](https://sepolia.voyager.online/tx/0x2d9802f35856f6b1f37d1c6d8d92677d83c1cec4460ffd075d54f0cf1ad15fc)) | 458,687,974 / 44,896 / 20.70 STRK | 44,714,230 / 1.32 STRK ([tx](https://sepolia.voyager.online/tx/0x22e7bf8c468de274f1526d2efb611f44716c59b0d19286abcdcc9d0cda5a82f)) |
| Argent 0.5.0 on testnet-v1 Falcon-512 | `[upgrade V2, set_pq_key]`, signed hybrid with Falcon-512 ([tx](https://sepolia.voyager.online/tx/0x9d3675d79dba977285e9327c1e79f581fc68d9f497ac564bb251fe327d0bf0)) | 479,362,058 / 43,712 / 21.07 STRK | 44,712,614 / 1.32 STRK ([tx](https://sepolia.voyager.online/tx/0x26065dfbf1580f339df0e2f3059d7c74f432a549c9f68e01413137e8326bed8)) |

For all three: the account's class is V2 (`0x7c7c9de0…`), the stored ECDSA and ML-DSA-44 keys equal
the keys from the words, the balance dropped by exactly the move's fee, a hybrid (ECDSA + ML-DSA-44)
transfer succeeded, and an ECDSA-only transfer was rejected in `__validate__`.

Finding: **the move costs about 45K L1 data gas**, from writing the key and its 419-slot cache
(the snforge figures above are L2 gas only). The first attempt of each move bounded L1 data gas at
5,000 and reverted after running ("Insufficient max L1DataGas … actual used: 44896"), paying 14.1,
14.1 and 14.7 STRK; `sepolia.json` keeps them under `failedAttempts`. The script now bounds the
move at 80,000. A wallet must set this bound from the scheme, not from a Falcon-sized default.

A hybrid transfer's 44.7M L2 gas is the whole transaction (validation, 40.6M locally, plus the
transfer); the move's 459M is above the local `migrate` figure (420M) by the full transaction's
validation and the 2.22.0 build.

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

`gas/run.sh` needs scarb 2.22.0, snforge 0.64.1 and universal-sierra-compiler 2.11.0-rc.1, as
bench/pf14/gas.

## Release manifest

[`release/testnet-v2.json`](../../release/testnet-v2.json) pins the three declared classes to their
scarb 2.22.0 artifacts, the lane's baseline bundle commit, the vendored patch and cache digests, and the declare transactions
(`node scripts/release_manifest.mjs --check --release testnet-v2`, in CI; `--chain` re-reads the
declarations).
