# PF-01: baseline and candidate reproduction

Local measurements of OpenZeppelin's Falcon-512 SHAKE-256 verifier and the two pinned
Provably Fast candidates (issue #2). Provenance, digests and contributors are in
[`vendor/provably-fast/falcon-512/PROVENANCE.md`](../../vendor/provably-fast/falcon-512/PROVENANCE.md).

These are bare-verifier figures from the challenge's own harness, not costs of this project's
hybrid account; account-level costs are PF-04 (issue #5).

## Reproduce

```sh
# scarb 2.18.0, snforge 0.59.0 and universal-sierra-compiler 2.9.1 on PATH
bench/pf01/reproduce.sh /tmp/pf01-work
```

The script checks the patch digests, clones the baseline commit, checks that
`vendor/cairo-pq-verifiers` is identical to it, makes one git worktree per variant, applies the
patch, switches the account crate to the audited libfunc list (as the challenge does), runs
`snforge test` for `pqbench_falcon_512` and `pqbench_ntt`, builds `pq_accounts`, and rewrites
`results.json`. It takes about 80 seconds on an M-series Mac.

To regenerate the corpus (not needed to reproduce; the committed one is the pinned artifact):

```sh
python3 -I bench/pf01/gen_corpus.py --falcon-py /path/to/falcon.py \
  --reference /path/to/falcon512.py   # https://postquantum.provably.fast/reference/falcon512.py
```

## Corpus

`corpus.json`: 27 signatures on three tprest/falcon.py keys (commit `5145a818`), 11 needing eight
SHAKE blocks and 16 needing nine, the mix the challenge's held-out set uses. Salts were searched
to hit each block count before signing. The last vector is the most expensive of 2,000
nine-block salts (569 words read). Every vector is accepted by the challenge's reference
verifier (`falcon512.py`, SHA-256 `54624238…ce713e2`). The held-out challenge corpus is private,
so these means are not an exact reproduction of the board's.

## Results

Run on 2026-10-26, Darwin arm64, scarb 2.18.0 / cairo 2.18.0 / Sierra 1.8.0, snforge 0.59.0,
universal-sierra-compiler 2.9.1. L2 gas is Sierra gas from snforge, `verify_N - baseline_N`
(the upstream paired-test method). Account sizes are upstream's `Falcon512ShakeAccount` built
with the audited libfunc list.

| Variant | Mean L2 gas | 8-block mean | 9-block mean | Worst valid | vs baseline | Account CASM felts | Sierra class bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| baseline | 48,401,490 | 45,826,113 | 50,172,062 | 50,182,988 | 1.000x | 52,315 | 2,142,604 |
| compact `fj_3a0b1c78` | 24,437,264 | 23,457,254 | 25,111,022 | 25,920,529 | 1.981x | 72,908 | 3,760,793 |
| record `fj_c3459a8b` | 24,136,013 | 23,155,454 | 24,810,148 | 25,620,242 | 2.005x | 81,152 | 4,025,263 |

Limits: 81,920 CASM felts, 4,089,446 Sierra class bytes, 100M L2 gas for validation.

### Against the board (external figures, from the 2026-10-26 snapshot)

| Variant | Board mean | Local mean | Difference | Board CASM / Sierra bytes | Local |
| --- | ---: | ---: | ---: | --- | --- |
| baseline | 48,398,466 | 48,401,490 | +0.006% | 52,315 / 2,142,604 | identical |
| compact | 24,399,230 | 24,437,264 | +0.16% | 72,908 / 3,760,793 | identical |
| record | 24,097,870 | 24,136,013 | +0.16% | 81,152 / 4,025,263 | identical |

The 8-block means agree with the board to within 0.02% for all three. The candidates' 9-block
means are about 0.25% higher than the board's because this corpus includes the 569-word vector;
without it they are within 0.05%.

### Tests

The upstream `pqbench_falcon_512` (plus the corpus) and `pqbench_ntt` suites pass for all three
variants: 108 and 20 tests for the baseline, 114 and 20 for each candidate (the patches add
tests). Building `pq_accounts` with either patch makes `Falcon512ShakeDirectAccount` exceed the
CASM limit (86,621 felts); the hint-variant account used here still fits.

## Findings

1. **Worst-case gas is higher than the board shows.** Among nine-block vectors, candidate gas rises
   about 3.1k-3.3k per extra word read (baseline: about 0.7k) up to 559 words, then jumps by about 840k at 569 words, on both candidates. The
   baseline barely moves (50.16M-50.18M across all nine-block vectors). From 200,000 random salts,
   about 1.2% read more than 560 words and the maximum seen was 575. The board's worst valid
   figures (25.06M compact, 24.76M record) come from its held-out set; the measured worst here
   is 25.92M and 25.62M. Both stay far below the 1.25x rejection rule and the 100M validation
   cap, but PF-03 and PF-04 should include high-word salts.
2. **The record likely does not fit as a full hybrid account.** This project's
   `HybridShakeAccount` is 53,237 CASM felts against upstream's 52,315 for the same verifier, so
   the hybrid wrapper adds about 922 felts. The record account is already 81,152 of 81,920;
   adding the wrapper would land near 82,070. Sizes do not add exactly, so PF-02/PF-04 must
   build it, but the margin is 768 felts against an overhead of about 900.
3. **Review cost.** Both patches are largely minified and use `bounded-int-utils` and a
   specialised `keccak_syscall` path. Neither had withstood an attack round when pinned.

## Provisional recommendation

**Compact (`fj_3a0b1c78`).** It costs 301k gas (1.2%) more per verification than the record but
leaves about 9,000 CASM felts of headroom, against 768 for the record, which the hybrid wrapper
probably exceeds. Keep the record for comparison in PF-02/PF-04: a verifier-only class (PF-02)
could still bring it under the limit. Final selection follows PF-03's correctness gate and PF-04's
account-level measurements.
