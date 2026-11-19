#!/usr/bin/env bash
# Generate the ML-DSA-44 record crate in crates/ from the vendored baseline, the pinned patch and
# this project's cache module. Same scheme as ../falcon-1024/make_crates.sh.
#
#   vendor/provably-fast/ml-dsa-44/make_crates.sh          # (re)write crates/
#   vendor/provably-fast/ml-dsa-44/make_crates.sh --check  # fail if crates/ differs
#
# The crate is `vendor/cairo-pq-verifiers/crates/ml_dsa_44` (the lane's baseline, 78c8359) with the
# patch applied, `cache.cairo` added as `src/verx/cache.cairo` (a child of the record's `verx`, so it
# can call that module's private `ead`), one `pub mod cache;` line appended to `src/verx.cairo`, and
# the package renamed `pqbench_ml_dsa_44` -> `pqbench_ml_dsa_44_pf_record`.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
BASE=$HERE/../../cairo-pq-verifiers/crates
CANDIDATES="record:mj_2e2f9ddebbcc4281b07d84937ae0ffbc"

(cd "$HERE" && shasum -a 256 -c --quiet SHA256SUMS)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/out"

for entry in $CANDIDATES; do
  name=${entry%%:*}
  job=${entry#*:}
  src=$tmp/$name
  mkdir -p "$src/crates"
  cp -R "$BASE/ml_dsa_44" "$src/crates/"
  (cd "$src" && git apply "$HERE/$name-$job.patch")
  mkdir -p "$src/crates/ml_dsa_44/src/verx"
  cp "$HERE/cache.cairo" "$src/crates/ml_dsa_44/src/verx/cache.cairo"
  printf '\npub mod cache;\n' >> "$src/crates/ml_dsa_44/src/verx.cairo"

  crate=ml_dsa_44_pf_$name
  mv "$src/crates/ml_dsa_44" "$tmp/out/$crate"
  find "$tmp/out/$crate" -type f \( -name '*.cairo' -o -name '*.toml' -o -name '*.md' \) \
    -exec perl -pi -e "s/\\bpqbench_ml_dsa_44\\b/pqbench_${crate}/g" {} +
done

if [ "${1:-}" = "--check" ]; then
  diff -r "$tmp/out" "$HERE/crates"
  echo "crates/ matches baseline + patch + cache + renames"
else
  mkdir -p "$HERE/crates"
  for dir in "$tmp"/out/*; do
    rm -rf "${HERE:?}/crates/$(basename "$dir")"
    cp -R "$dir" "$HERE/crates/"
  done
  echo "wrote $(ls "$HERE/crates" | tr '\n' ' ')"
fi
