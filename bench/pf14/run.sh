#!/usr/bin/env bash
# PF-14: run every Falcon-1024 vector in vectors.json through the baseline and the pinned verifier.
#   bench/pf14/run.sh            # needs scarb 2.18.0 and python3
# Regenerates src/vectors.cairo (not committed), runs cairo-test, then fails unless every
# verifier agrees with the reference on every vector and no rejection costs more than 1.25x the
# worst acceptance, and rewrites results.json.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
python3 -I "$HERE/gen_tests.py"
log=$(mktemp)
trap 'rm -f "$log"' EXIT
(cd "$HERE" && scarb cairo-test > "$log" 2>&1) || { tail -40 "$log"; exit 1; }
python3 -I "$HERE/summarize.py" "$log"
