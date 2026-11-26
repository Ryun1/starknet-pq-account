# PF-14 Part A: Falcon-1024 (NIST level 5) hybrid verifier

Issue #22. A Falcon-1024 verifier class, `HybridShakeVerifierFalcon1024`, for
`HybridMigratableAccountV2` ([scheme-switch.md](../../contracts/docs/scheme-switch.md)), built on the
Provably Fast Falcon-1024 record `fk_29560355` ([PROVENANCE](../../vendor/provably-fast/falcon-1024/PROVENANCE.md)).
Experimental, unaudited, testnet only. Declared on Sepolia from a scarb 2.22.0 build and pinned in
release [`testnet-v2`](../../release/testnet-v2.json); see [Sepolia receipts](#sepolia-receipts-a9-2026-11-26).
Part B, ML-DSA-87 (no class; the trigger to revisit): [ml-dsa-87.md](ml-dsa-87.md).

Acceptance criterion 1, "Falcon-1024 declare gas and validation gas measured": declare **4.43e9 L2
gas (76.4% of the block cap)**, validation **51.3M mean, 54.6M worst (45% under the 100M cap)**.

## Results

### Validation and calls (`gas/`, snforge L2 gas)

`HybridMigratableAccountV2` on the Falcon-1024 verifier, over the 19 valid vectors of
`vectors.json` (9 falcon.py, 10 noble, on four keys; 8 need 16 SHAKE blocks and 11 need 17).

| Path | L2 gas | of the 100M validation cap |
| --- | ---: | ---: |
| `__validate__`, mean | 51,341,528 | 51.3% |
| `__validate__`, worst (1,130 SHAKE words) | 54,645,625 | 54.6% |
| `__validate__`, mean of 16-block / 17-block vectors | 49,866,542 / 52,414,245 | |
| `__validate__`, the board's 8 : 16 block mix | 51.56M | |
| `__validate_declare__`, worst of selected | 54,640,125 | 54.6% |
| `is_valid_signature`, worst of selected | 55,025,445 | 55.0% |
| rejected signature (valid ECDSA, Falcon-1024 of another message), worst of selected | 47,641,479 | 47.6% |
| `set_pq_key` Falcon-512 → Falcon-1024 (in `__execute__`) | 78,767,109 | not validation |
| `migrate` straight to Falcon-1024 (in `__execute__`) | 84,322,669 | not validation |

Cairo steps on the worst vector: 352,947 (cap 1,000,000). Against the board's own figures for the
record (47,579,680 and 49,908,313 for 16 and 17 blocks), the account adds 2.3–2.5M: reading the
57-felt key, ECDSA and the library call. This matches the plan's estimate of 52–53M.

`set_pq_key` and `migrate` run the new verifier on the proof in `__execute__`, so they do not
count against the validation cap; the transaction around them is validated by the old scheme.

### Declare size

The record's patch in this project's verifier class, measured by `../pf04/screen.sh --lane falcon1024`
(the PF-04 formula: 1,280 L2 gas per code byte, 32 bytes per CASM and Sierra felt plus the ABI):

| Job | Board mean | CASM felts | Sierra felts | Class bytes | Declare L2 gas | of 5.8e9 block cap |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `fk_c4038d6e` | 49,040,871 | 76,723 | 71,897 | 3,775,923 | 6,088,400,640 | 105.0% |
| `fk_7da1a28f` | 49,088,548 | 77,183 | 74,703 | 3,924,115 | 6,222,176,000 | 107.3% |
| `fk_840bc1b4` | 49,098,057 | 77,631 | 74,513 | 3,917,039 | 6,232,743,680 | 107.5% |
| `fk_9918c4fd` | 49,104,657 | 77,712 | 74,545 | 3,920,843 | 6,237,372,160 | 107.5% |
| `fk_29560355` (record, **selected**) | 49,132,102 | 59,762 | 48,437 | 3,077,705 | 4,432,756,480 | 76.4% |
| `fk_f5cc81df` | 49,158,543 | 59,689 | 47,812 | 3,018,060 | 4,404,166,400 | 75.9% |
| `fk_91eb8438` | 49,231,281 | 58,452 | 48,025 | 3,028,444 | 4,362,223,360 | 75.2% |
| `fk_e13dd2c3` | 50,265,081 | 57,189 | 43,212 | 2,830,343 | 4,113,350,400 | 70.9% |
| `fk_1553544a` | 115,218,933 | 38,324 | 46,817 | 2,016,029 | 3,488,300,800 | 60.1% |

The selection rule is the cheapest-to-validate unbroken entry whose declare is at most 95% of the
cap and that builds against both libfunc lists. The four unbroken entries cheaper than the record
(over the board's 75% account budget, so not records) need 105–107.5% of the block cap and cannot
be declared. The record is the cheapest that fits, so it is selected. `HybridMigratableAccountV2` is 593,775,360 (10.2%).

### Correctness (differential, cairo-test)

All 143 vectors give the reference's verdict on both the lane's baseline (`pqbench_falcon_1024`,
`bf7fd87`) and the pinned record. Gas below is cairo-test's estimate of `verify` alone, not L2 gas.

| Verifier | Worst valid | Worst invalid | Ratio | Worst invalid input |
| --- | ---: | ---: | ---: | --- |
| baseline | 144,923,474 | 144,904,004 | 1.000 | salt_b + 1 |
| record | 52,360,780 | 53,489,868 | 1.022 | vector 7: signature felt 8 zero |

The lane counts a rejection costing more than 1.25 times the worst valid verification as a break
(all six breaks in the lane are of that kind), and `summarize.py` fails above that ratio.

## Vectors (143)

`vectors.json`; `expected` is the verdict of the lane's reference,
https://postquantum.provably.fast/reference/falcon1024.py (SHA-256 `0d344416…bd51fe4`, in full in
`vectors.json`), the exact file the evaluator judges with.

| Category | Count | What |
| --- | ---: | --- |
| valid | 19 | 9 falcon.py signatures at n = 1024 (tprest/falcon.py `5145a818`), 10 noble `falcon1024` signatures through `signer/falcon_adapter.mjs` |
| tampered | 25 | per base signature (one falcon.py, one noble): message + 1, each salt half + 1, salts swapped, swapped s1, hint and key felts, s1 and hint swapped, s1[0] + 1 with and without re-hinting, hint[1023] + 1, another key; plus a signature 45 over the norm bound |
| malformed | 39 | each half of the first key, s1 and hint felt at q^9 and q^9 - 1, high half 2^123 - 1, felt p - 1; the sixteen-coefficient last felt (nine low, seven high) at low q^9, high q^7, high q^9 - 1 and the canonical maximum; salt halves 2^160 and p - 1; keys and signatures of the wrong length |
| random | 60 | seeded (`--seed 1`) mutations of valid vectors |

Valid boundary cases: messages 0 and p - 1 (both signers), salt halves 0 and 2^160 - 1, a 16-block
salt reading all 1,088 words, the cheapest and the most expensive 17-block salts of 30,000 (1,089
and 1,130 words), and a signature 20 under the norm bound 70,265,242. The published break vectors
are not public (the board gives digests only), so they are not included.

## Run

```sh
bench/pf14/run.sh          # differential: scarb 2.18.0, python3
bench/pf14/gas/run.sh      # gas, steps, class sizes, network libfuncs; writes gas/results.json
bench/pf14/gas/run.sh --check   # CI: same, against gas/budgets.json
bench/pf04/screen.sh --lane falcon1024 fk_2956035507114a6c89165c8cc8e8fe56 ...   # declare screen
bench/pf04/screen.sh --lane mldsa87 mk_94cd1f15e1c94f189f3a3579bb166377 ...      # Part B
```

**Toolchain change, 2026-11-26.** `results.json` and `budgets.json` were re-measured with scarb 2.22.0
(Sierra 1.10.0), snforge 0.64.1 and universal-sierra-compiler 2.11.0-rc.1, because Sepolia's gateway
now declares only Sierra 1.10.0. The tables below remain the dated 2.18.0 run; under 2.22.0 the same
paths cost up to 5.4% (`set_pq_key`) more L2 gas, and every network limit still holds. Release testnet-v1's declared
classes are the 2.18.0 builds (`release/testnet-v1.json`).

`gas/run.sh` needs scarb 2.22.0, snforge 0.64.1 and universal-sierra-compiler **2.11.0-rc.1**, the
versions `gas/budgets.json` (measured + 1%) was measured with, as bench/pf04. It also builds
`contracts/` against `bench/pf04/network_libfuncs.json` and reads the class sizes from that build.

To regenerate the vectors (the committed file is the pinned artifact):

```sh
(cd signer && npm install --no-package-lock)
node bench/pf14/noble_vectors.mjs > /tmp/noble.json
python3 -I bench/pf14/gen_vectors.py --falcon-py /path/to/falcon.py \
  --reference /path/to/falcon1024.py --noble /tmp/noble.json --seed 1   # about 20 s
```

## Signer

`signer/falcon_adapter.mjs` takes n from the header byte of the key (`0x09` / `0x0A`), signature
(`0x39` / `0x3A`) and secret key (`0x59` / `0x5A`), so the kit's `hybridSignature`, `prepareKeys`,
`setPqKeyCalls` and `migrationArgs` work unchanged with Falcon-1024 keys. Packing at n = 1024 is 56
felts of 18 coefficients and a last felt of sixteen (nine low, seven high). The NTT needs falcon.py's
roots up to n = 1024: `signer/falcon1024_ntt_roots.json` (`scripts/export_ntt_roots.py --max-n 1024`);
`falcon_ntt_roots.json` is unchanged. Backup profile v0.2:
[key-backup-v0.2.md](../../contracts/docs/key-backup-v0.2.md).

## Demo page

`docs/index.html` (GitHub Pages) signs with Falcon-1024 too. It reads the account's on-chain key:
57 felts means Falcon-1024 (backup v0.2), otherwise Falcon-512 (v0.1), so a user's own words work
for either. A second button opens the Falcon-1024 demo account, the public demo words at account
index 1 (`0x6cc8174385000e9451849a43266798b22ad91edd529ba3bc3f1b693e0bc3218`). The page's signing
code, sliced from the built page, gives the same keys as `signer/pq_keys.mjs` and signatures the
board's reference verifiers accept, at both n. A header menu separates two flows: *Hybrid demo*
(send with both keys, then ECDSA only, which is rejected) and *Falcon only* (a valid Falcon
signature with the ECDSA half left as zeros, also rejected with `Account: invalid signature`).

Setting up that account on Sepolia (from the deployer key in `.keys/`):

```sh
(cd contracts && scarb build)
cd signer
node pf04_sepolia.mjs declare HybridMigratableAccountV2
node pf04_sepolia.mjs declare HybridShakeVerifierFalcon1024   # about 4.43e9 L2 gas, ~100 STRK
node pq_demo_setup.mjs falcon-1024   # fund, deploy, [upgrade(V2), migrate] to Falcon-1024, hybrid
                                 # transfer, ECDSA-only transfer rejected; writes sepolia.json
```

## Sepolia receipts (A9, 2026-11-26)

`HybridShakeVerifierFalcon1024` `0x647ae0aa…661d` declared from a scarb 2.22.0 build
([`0x62cffff0…`](https://sepolia.voyager.online/tx/0x62cffff0c2ef735b3537812a4de33dc7f183322202ca726b3ce735bef4ccc62),
about 4.43e9 L2 gas). Each account from its own words (ECDSA key by the wallet's derivation,
Falcon-1024 key by backup profile v0.2):

| Account | Path | Move: L2 gas / L1 data gas / fee | Hybrid transfer: L2 gas / fee |
| --- | --- | ---: | ---: |
| Public demo, OpenZeppelin (demo words index 1) | `[upgrade V2, migrate]` straight to Falcon-1024 ([tx](https://sepolia.voyager.online/tx/0xa9ae3f8f95304e0b60bcc65e93176062384a7fdb9188a712b5d8ef55ffb5ad)) | 171,843,520 / – / 5.16 STRK | 54,223,517 / 1.57 STRK ([tx](https://sepolia.voyager.online/tx/0x5f761f3f269f06a0cfced699ecd1ddde46bedc1d217c1d40c90d82d085ddc95)) |
| Argent 0.5.0 on testnet-v1 Falcon-512 | `[upgrade V2, set_pq_key]`, signed hybrid with Falcon-512 ([tx](https://sepolia.voyager.online/tx/0x7fa616e21dd5cd510393894a30739bf4dd0fe090cd11d605ecb1a357065d34e)) | 115,749,732 / 4,832 / 3.38 STRK | 54,226,127 / 1.58 STRK ([tx](https://sepolia.voyager.online/tx/0x6928ed48b8da1839b23577c9a40fc6850e753e0eb087cf629382a5bc0d24cd4)) |

For both: the account's class is V2 (`0x7c7c9de0…`), a hybrid (ECDSA + Falcon-1024) transfer
succeeded and an ECDSA-only transfer was rejected in `__validate__`. For the moved account the
stored ECDSA and Falcon-1024 keys equal the keys from its words and the balance dropped by exactly
the move's fee. Receipts: [`sepolia.json`](sepolia.json) (demo account) and
[`a9-sepolia.json`](a9-sepolia.json) (the move), the latter from

```sh
cd signer
PQ_TARGET=falcon-1024 node pf13_sepolia.mjs run        # deploy, Falcon-512 migration, move, transfers
PQ_TARGET=falcon-1024 node pf13_sepolia.mjs receipts   # writes bench/pf14/a9-sepolia.json
```

The move (115.7M) is above the local `set_pq_key` figure (78.8M) by the transaction's Falcon-512
validation, the `upgrade` call and the 2.22.0 build. Unlike ML-DSA-44 it writes only the 57-felt
key, so its L1 data gas (4,832) fits a Falcon-sized bound.

## Not done

- Falcon-1024 is pinned in release `testnet-v2` with `scheme: falcon-1024`, but the kit does not
  read that manifest: `KNOWN_VERIFIERS` still lists only the testnet-v1 verifiers, so callers pass
  their own `allowedVerifiers`, and there is no per-scheme allow list yet.
- A review of the record patch. It is minified contest code, attacked (one hammer round) but not
  audited.
