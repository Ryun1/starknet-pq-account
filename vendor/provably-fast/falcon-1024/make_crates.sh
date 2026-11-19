#!/usr/bin/env bash
# Generate the Falcon-1024 candidate crates in crates/ from the vendored baseline and the pinned
# patch. Same scheme as ../falcon-512/make_crates.sh.
#
#   vendor/provably-fast/falcon-1024/make_crates.sh          # (re)write crates/
#   vendor/provably-fast/falcon-1024/make_crates.sh --check  # fail if crates/ differs
#
# Each candidate is `vendor/cairo-pq-verifiers/crates/{falcon_1024,ntt}` (the lane's baseline,
# bf7fd87) with its patch applied and nothing else changed except the package names:
# `pqbench_falcon_1024` and `pqbench_ntt` become `pqbench_falcon_1024_pf_<name>` and
# `pqbench_ntt_f1024_pf_<name>` in the manifests and in the `use` paths that name them.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
BASE=$HERE/../../cairo-pq-verifiers/crates
CANDIDATES="record:fk_2956035507114a6c89165c8cc8e8fe56"

(cd "$HERE" && shasum -a 256 -c --quiet SHA256SUMS)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/out"

for entry in $CANDIDATES; do
  name=${entry%%:*}
  job=${entry#*:}
  src=$tmp/$name
  mkdir -p "$src/crates"
  cp -R "$BASE/falcon_1024" "$BASE/ntt" "$src/crates/"
  (cd "$src" && git apply "$HERE/$name-$job.patch")

  falcon=falcon_1024_pf_$name
  ntt=ntt_f1024_pf_$name
  mv "$src/crates/falcon_1024" "$tmp/out/$falcon"
  mv "$src/crates/ntt" "$tmp/out/$ntt"
  find "$tmp/out/$falcon" "$tmp/out/$ntt" -type f \( -name '*.cairo' -o -name '*.toml' -o -name '*.md' \) \
    -exec perl -pi -e "s/\\bpqbench_falcon_1024\\b/pqbench_${falcon}/g; s/\\bpqbench_ntt\\b/pqbench_${ntt}/g; s{path = \"\\.\\./ntt\"}{path = \"../${ntt}\"}g" {} +
done

if [ "${1:-}" = "--check" ]; then
  diff -r "$tmp/out" "$HERE/crates"
  echo "crates/ matches baseline + patches + renames"
else
  mkdir -p "$HERE/crates"
  for dir in "$tmp"/out/*; do
    rm -rf "${HERE:?}/crates/$(basename "$dir")"
    cp -R "$dir" "$HERE/crates/"
  done
  echo "wrote $(ls "$HERE/crates" | tr '\n' ' ')"
fi
