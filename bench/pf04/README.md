# PF-04: account-level benchmarks and limits

Gas, steps, class sizes and libfuncs of this project's hybrid classes with the baseline verifier
and both Provably Fast candidates (issue #5). Bare-verifier figures are in
[`bench/pf01`](../pf01/README.md); correctness is [`bench/pf03`](../pf03/README.md).

Everything here is a **local snforge measurement** (blockifier, Sierra-gas mode), not a Sepolia
receipt. Full-transaction figures from Sepolia are in [Sepolia receipts](#sepolia-receipts).

## Reproduce

```sh
# scarb 2.18.0 and snforge 0.59.0 (with universal-sierra-compiler) on PATH
bench/pf04/run.sh            # rewrites results.json, fails on a limit or budget
bench/pf04/run.sh --check    # what CI runs: same checks, results.json untouched
```

It takes one to five minutes, depending on what is already compiled. Nothing is sent anywhere.

## Method

- **Inputs.** The 27 PF-01 corpus signatures (11 eight-block, 16 nine-block, including the
  569-word worst case) become hybrid signatures with an ECDSA half from an intentionally public
  key (`fixtures.json`, from `gen_fixtures.mjs`; RFC 6979, so reproducible). The migration uses
  the key-possession proof in `contracts/src/tests_wallets_fixture.cairo`.
- **Accounts.** A migrated account is `HybridMigratableAccount` holding both keys and the
  verifier class hash, so `__validate__` library-calls the verifier, exactly as on a migrated
  wallet. The candidates exist only as verifier classes; a directly deployed `HybridShakeAccount`
  is measured for the baseline only.
- **Pairs.** `gen_tests.py` writes every measurement as a test and a `setup_` twin that builds the
  same state and inputs without the call. The figure is the difference of their L2 gas, the
  PF-01 method. Cross-check: snforge's own per-entrypoint figure (`--gas-report`) is exactly
  96,090 gas lower on every vector and verifier, the cost of the test calling into the account.
- **Rejected signature.** Valid ECDSA half, Falcon half of another message: the most expensive way
  to fail (ECDSA is checked first, so a bad ECDSA half costs almost nothing).
- **Migration.** A legacy OpenZeppelin-style account (`src/legacy.cairo`) runs `upgrade` to
  `HybridMigratableAccount` and `migrate` with the proof. Real Argent and Braavos classes are
  measured on Sepolia.
- **Steps** are measured separately in Cairo-steps mode, worst vector only.

## Results

Run on 2026-10-27, Darwin arm64, scarb 2.18.0 / cairo 2.18.0 / Sierra 1.8.0, snforge 0.59.0. Full
figures in `results.json`. L2 gas:

| Path | baseline | compact | record | compact saving |
| --- | ---: | ---: | ---: | ---: |
| `__validate__`, migrated account, mean | 50,396,185 | 26,431,759 | 26,130,688 | 47.6% |
| `__validate__`, migrated account, 8-block mean | 47,820,808 | 25,451,749 | 25,150,129 | 46.8% |
| `__validate__`, migrated account, 9-block mean | 52,166,757 | 27,105,517 | 26,804,823 | 48.0% |
| `__validate__`, migrated account, worst | 52,177,683 | 27,915,024 | 27,614,917 | 46.5% |
| `__validate_declare__`, worst | 52,172,283 | 27,909,624 | 27,609,517 | 46.5% |
| `is_valid_signature`, worst | 52,369,363 | 28,106,704 | 27,806,597 | 46.3% |
| rejected signature, worst | 52,411,463 | 27,231,021 | 26,915,914 | 48.0% |
| migration (`upgrade` + `migrate`) | 69,386,419 | 44,272,637 | 43,971,120 | 36.2% |

`__validate_declare__`, `is_valid_signature` and rejection are measured on vectors 0 (first
eight-block) and 26 (worst nine-block). Directly deployed `HybridShakeAccount` validation: mean
50,045,745, worst 51,827,243, about 350k below the migrated account's (no library call).

Validation steps on the worst vector: 331,338 baseline, 182,602 compact, 179,553 record.

### Limits and headroom

Sepolia and mainnet both ran Starknet 0.14.4 on 2026-10-27 (`starknet_getBlockWithTxHashes`).

| Limit | Value | Source | Worst here | Headroom |
| --- | ---: | --- | ---: | ---: |
| Validation Sierra gas | 100,000,000 | versioned constants 0.14.4 `validate_max_sierra_gas` | 28,106,704 compact | 71.9% |
| Validation steps | 1,000,000 | versioned constants 0.14.4 `validate_max_n_steps` | 182,602 compact | 81.7% |
| CASM bytecode felts | 81,920 | sierra compiler `DEFAULT_MAX_BYTECODE_SIZE` | 71,580 compact / 77,902 record | 10,340 / 4,018 |
| Sierra program felts | 81,920 | gateway `max_contract_bytecode_size` | 71,809 compact / 76,146 record | 10,111 / 5,774 |
| Declared class object bytes | 4,089,446 | gateway `max_contract_class_object_size` | 3,149,439 compact / 3,422,453 record | 23.0% / 16.3% |
| Compiled class object bytes | 4,089,446 | class manager `max_compiled_contract_class_object_size` | 2,141,080 compact / 2,329,159 record | 47.6% / 43.0% |
| Signature felts | 4,000 | gateway `max_signature_length` | 62 | |

Validation with the baseline uses up to 52.4M of the 100M cap (47.6% headroom); with either
candidate, about 28M.

Sources (starkware-libs/sequencer): `crates/blockifier/resources/blockifier_versioned_constants_0_14_4.json`
at `f971cfda`, and `apollo_gateway_config/src/config.rs`,
`apollo_class_manager_config/src/config.rs`, `apollo_sierra_compilation_config/src/config.rs` at
`ced8be53` (main, 2026-10-27). The gateway and class-manager values are defaults; the deployed
configuration is not public, so they are the best available evidence, not a guarantee. "Class
object bytes" is computed the way the gateway does (compact JSON, ABI as a string), so it differs
slightly from the size of the file Scarb writes.

| Class | CASM felts | Sierra felts | Class object bytes | Compiled object bytes |
| --- | ---: | ---: | ---: | ---: |
| `HybridShakeAccount` | 53,237 | 53,532 | 2,038,866 | 1,439,349 |
| `HybridShakeVerifierPfCompact` | 71,580 | 71,809 | 3,149,439 | 2,141,080 |
| `HybridShakeVerifierPfRecord` | 77,902 | 76,146 | 3,422,453 | 2,329,159 |
| `HybridMigratableAccount` | 7,719 | 3,546 | 181,970 | 177,227 |
| `HybridPoseidonAccount` | 49,043 | 51,261 | 1,900,820 | 1,331,138 |
| `VerifierSwitchGuard` | 1,164 | 978 | 36,318 | 27,626 |

### Libfuncs

`contracts/` is built with `allowed-libfuncs-deny = true` against mainnet's audited list. The
sequencer compiles declared classes against its own bundled list (`DEFAULT_ALLOWED_LIBFUNCS_LIST
= Bundled`), which was narrowed on 2026-09-16, so `run.sh` also builds every class from a clean
copy against that list: `network_libfuncs.json`, from
`crates/apollo_compile_to_casm/resources/allowed_libfuncs.json` at `ced8be53` (Apache-2.0,
SHA-256 `3b4ebcfa…eb0ff9dc`). All classes build. Removing `keccak_syscall` from the list makes the
two candidate verifier classes fail, so the check is live. Scarb does not rebuild when only the
list changes, which is why the check uses a fresh copy.

## Selection

**Compact (`fj_3a0b1c78`, `HybridShakeVerifierPfCompact`).** Both candidates pass PF-03 on all
136 vectors and both fit every limit. The record saves about 300k L2 gas (1.1%) per validation;
the compact leaves 10,340 CASM felts of headroom against the record's 4,018 and is 273k bytes
smaller to declare. The record is not excluded: it fits, and is documented above.

## Budgets

`budgets.json` holds a maximum for every metric in `results.json` (`metrics`): the measured value
plus 1%, never above the network limit. `run.sh` fails if a metric exceeds its budget, has no
budget, or any class or validation exceeds a network limit. snforge's figures are deterministic,
so any change is real.

A deliberate change (a new verifier, a compiler upgrade) updates `budgets.json` in the same pull
request, with the old and new figures and the reason in the commit message; the reviewer approves
the budget change with the code. Regenerate with `run.sh`, then set each changed budget to the new
value plus 1%.

## Sepolia receipts

Pending: complete transactions (transfer, declare, migrations from a newer and an older wallet
class) with each verifier.
