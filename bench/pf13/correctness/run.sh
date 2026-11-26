#!/usr/bin/env bash
# PF-13: every ML-DSA-44 vector in vectors.json through the baseline, the pinned record and the
# record's cached check (precompute + verify_cached), the cache's own tests, and NIST ACVP sigVer
# on the baseline.
#   bench/pf13/correctness/run.sh            # needs scarb 2.22.0 and python3
# Regenerates src/{vectors,cache_tests,acvp}.cairo (not committed), runs cairo-test, then fails
# unless every path agrees with the reference on every vector and no rejection costs more than
# 1.25x the worst acceptance, and rewrites results.json.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
python3 -I "$HERE/gen_tests.py"
log=$(mktemp)
trap 'rm -f "$log"' EXIT
(cd "$HERE" && scarb cairo-test > "$log" 2>&1) || { tail -40 "$log"; exit 1; }
python3 -I "$HERE/summarize.py" "$log"
