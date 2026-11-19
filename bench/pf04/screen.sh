#!/usr/bin/env bash
# PF-04: declare size of Provably Fast board entries as this project's verifier class.
#
#   bench/pf04/screen.sh JOB_ID...                    # Falcon-512 lane (fj_ ids)
#   bench/pf04/screen.sh --lane falcon1024 JOB_ID...  # Falcon-1024 lane (fk_ ids, PF-14)
#   bench/pf04/screen.sh --lane mldsa87 JOB_ID...     # ML-DSA-87 lane (mk_ ids, PF-14 Part B)
#
# For each job: download its patch from the board into a temporary copy of this repository, put it
# in the lane's slot (Falcon-512: compact; Falcon-1024: record), build contracts/, and print the
# CASM and Sierra felts of the slot's verifier class and its declare L2 gas against the block cap
# (see summarize.py). The board reports CASM only, which does not predict the declare size. Nothing
# in the repository is changed. Needs scarb 2.18.0, curl, rsync and python3; about 45 seconds per
# job.
#
# mldsa87 has no class in this repository, and the lane scores its own account, so that lane builds
# the lane's baseline bundle with the patch applied and measures `MlDsa87Account` as the board does,
# against bench/pf04/network_libfuncs.json (a libfunc outside it fails the build).
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
LANE=falcon
if [ "${1:-}" = "--lane" ]; then LANE=${2:-}; shift 2; fi
case $LANE in
  falcon)
    API=falcon; ID='^fj_[0-9a-f]{32}$'; CRATES='falcon_512|ntt'; DIR=falcon-512
    SLOT=compact-fj_3a0b1c78817845a68e1e907928a541e4.patch; CLASS=HybridShakeVerifierPfCompact ;;
  falcon1024)
    API=falcon1024; ID='^fk_[0-9a-f]{32}$'; CRATES='falcon_1024|ntt'; DIR=falcon-1024
    SLOT=record-fk_2956035507114a6c89165c8cc8e8fe56.patch; CLASS=HybridShakeVerifierFalcon1024 ;;
  mldsa87)
    API=mldsa87; ID='^mk_[0-9a-f]{32}$'; CRATES='ml_dsa_87'; CLASS=MlDsa87Account
    BASELINE=23d05d6a2412000db2e70a804f5b6cc5a063449a ;;
  *) echo "unknown lane: $LANE" >&2; exit 1 ;;
esac
[ $# -gt 0 ] || { echo "usage: screen.sh [--lane falcon|falcon1024|mldsa87] JOB_ID..." >&2; exit 1; }
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
if [ "$LANE" = mldsa87 ]; then
  curl -sf -o "$WORK/baseline.bundle" "https://postquantum.provably.fast/mldsa87/baseline.bundle"
  git clone -q "$WORK/baseline.bundle" "$WORK/baseline"
  [ "$(git -C "$WORK/baseline" rev-parse HEAD)" = "$BASELINE" ] || { echo "baseline bundle is not $BASELINE" >&2; exit 1; }
fi

for job in "$@"; do
  [[ $job =~ $ID ]] || { echo "not a job id: $job" >&2; exit 1; }
  w=$WORK/$job
  if [ "$LANE" = mldsa87 ]; then
    git clone -q "$WORK/baseline" "$w"
    f=$WORK; SLOT=$job.patch
  else
    mkdir -p "$w"
    rsync -a --exclude target --exclude node_modules --exclude .git --exclude .keys \
      --exclude .snfoundry_cache "$REPO/" "$w/"
    f=$w/vendor/provably-fast/$DIR
  fi
  curl -sf -o "$f/$SLOT" "https://postquantum.provably.fast/api/participation/$API/jobs/$job/patch"
  # Untrusted input: the patch may only modify or create Cairo sources of the two crates. Check the
  # paths git apply itself will write (both sides, via --numstat), and reject renames, copies, mode
  # changes and deletions (--summary), before make_crates.sh applies it.
  allowed="^crates/($CRATES)/src/[A-Za-z0-9_/]+\\.cairo\$"
  paths=$(git -C "$WORK" apply --numstat "$f/$SLOT" | cut -f3-) || { echo "$job: not a valid patch, skipped" >&2; continue; }
  if [ -z "$paths" ] || grep -Ev "$allowed" <<< "$paths" >&2; then
    echo "$job: patch touches other files, skipped" >&2; continue
  fi
  if git -C "$WORK" apply --summary "$f/$SLOT" | grep -Ev "^ create mode 100644 crates/($CRATES)/src/[A-Za-z0-9_/]+\\.cairo\$" | grep . >&2; then
    echo "$job: patch renames, copies, deletes or changes modes, skipped" >&2; continue
  fi
  if [ "$LANE" = mldsa87 ]; then
    git -C "$w" apply "$f/$SLOT"
    c=$w/pq-accounts/contracts
    cp "$REPO/bench/pf04/network_libfuncs.json" "$c/"
    perl -pi -e 's/^allowed-libfuncs-list.name = "experimental"$/allowed-libfuncs-list.path = "network_libfuncs.json"\nallowed-libfuncs-deny = true/' "$c/Scarb.toml"
    grep -q '^allowed-libfuncs-deny = true' "$c/Scarb.toml"
    target=$w/target/dev; prefix=pq_accounts
  else
    (cd "$f" && shasum -a 256 *.patch > SHA256SUMS)
    "$f/make_crates.sh" > /dev/null
    c=$w/contracts; target=$c/target/dev; prefix=pq_hybrid
  fi
  (cd "$c" && scarb build > "$w/build.log" 2>&1) || { echo "$job: build failed" >&2; continue; }
  python3 -I - "$target" "$job" "${prefix}_$CLASS" <<'PY'
import json, os, sys
target, job, name = sys.argv[1], sys.argv[2], sys.argv[3]
sierra = json.load(open(f"{target}/{name}.contract_class.json"))
casm = json.load(open(f"{target}/{name}.compiled_contract_class.json"))
abi = len(json.dumps(sierra["abi"], separators=(",", ":")))
c, s = len(casm["bytecode"]), len(sierra["sierra_program"])
gas = 1280 * (32 * (c + s) + abi)
size = os.path.getsize(f"{target}/{name}.contract_class.json")
print(f"{job} casm={c} sierra={s} class_bytes={size} declare_l2_gas={gas} of_block_cap={gas / 5.8e9:.1%}")
PY
done
