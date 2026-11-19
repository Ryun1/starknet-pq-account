#!/usr/bin/env bash
# ARCH-01: __validate__ L2 gas, hybrid against PQ-only, on HybridMigratableAccountV2.
#
#   bench/arch01/run.sh
#
# Needs scarb 2.18.0, snforge 0.59.0, universal-sierra-compiler 2.10.2 (as bench/pf14/gas).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$HERE/src/fixtures"
for f in tests_wallets_fixture tests_falcon1024_fixture tests_pq_only_fixture; do
  cp "$HERE/../../contracts/src/$f.cairo" "$HERE/src/fixtures/"
  echo "pub mod $f;"
done > "$HERE/src/fixtures.cairo"
mkdir -p "$HERE/target"
(cd "$HERE" && snforge test) | tee "$HERE/target/gas.log" | python3 -I -c '
import sys; sys.path.insert(0, sys.argv[1])
from summarize import gas_pairs
d = gas_pairs(sys.stdin.read())
for k in sorted(d): print(f"{k:28} {d[k]:>12,}")
for n in ("512", "1024"):
    h, p = d[f"validate_hybrid_{n}"], d[f"validate_pq_only_{n}"]
    print(f"saving Falcon-{n:5} {h - p:>12,}  ({(h - p) / h:.2%} of hybrid)")
' "$HERE/../pf04"
