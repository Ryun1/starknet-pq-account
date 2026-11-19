#!/usr/bin/env python3
"""Check a `scarb cairo-test` log of the PF-13 suite and write results.json.

bench/pf14/summarize.py with three paths. Fails unless every (vector, path) test, every cache test
and every ACVP test passed, and unless each path's worst rejection costs at most 1.25 times its
worst acceptance. Gas is cairo-test's estimate (not Starknet L2 gas) minus the vector's
inputs-only test; for `cached` minus the inputs + precompute test, so it is the cost of
`verify_cached` alone, the per-transaction cost.

Usage: python3 -I bench/pf13/correctness/summarize.py LOG
"""

import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).parent
PATHS = {"baseline": "inputs", "record": "inputs", "cached": "precompute"}
MAX_REJECTION_RATIO = 1.25
LINE = re.compile(r"test \S+::v(\d+)_(\w+) \.\.\. (ok|fail)(?: \(gas usage est\.: (\d+)\))?")


def main() -> None:
    log = Path(sys.argv[1]).read_text()
    vectors = json.loads((HERE / "vectors.json").read_text())["vectors"]

    status, gas = {}, {}
    for n, name, result, g in LINE.findall(log):
        status[(int(n), name)] = result
        if g:
            gas[(int(n), name)] = int(g)
    missing = [(v["id"], name) for v in vectors for name in [*PATHS, "inputs", "precompute"]
               if status.get((v["id"], name)) != "ok"]
    if missing:
        raise SystemExit(f"{len(missing)} tests missing or failing, first: {missing[:5]}")
    extra = {kind: len(re.findall(rf"test \S+::{kind}::\w+ \.\.\. ok", log)) for kind in ("acvp", "cache_tests")}
    if extra["acvp"] != 45 or extra["cache_tests"] != 10:
        raise SystemExit(f"expected 45 ACVP and 10 cache tests passing, got {extra}")

    per_path = {}
    for name, base in PATHS.items():
        cost = {v["id"]: gas[(v["id"], name)] - gas[(v["id"], base)] for v in vectors}
        valid = [v for v in vectors if v["expected"]]
        invalid = [v for v in vectors if not v["expected"]]
        worst_valid = max(valid, key=lambda v: cost[v["id"]])
        worst_invalid = max(invalid, key=lambda v: cost[v["id"]])
        per_path[name] = {
            "agrees_with_reference": len(vectors),
            "worst_valid": {"id": worst_valid["id"], "gas": cost[worst_valid["id"]],
                            "description": worst_valid["description"]},
            "worst_invalid": {"id": worst_invalid["id"], "gas": cost[worst_invalid["id"]],
                              "description": worst_invalid["description"]},
            "worst_invalid_over_worst_valid": round(cost[worst_invalid["id"]] / cost[worst_valid["id"]], 4),
            "by_reason_max": {r: max(cost[v["id"]] for v in vectors if v["reason"] == r)
                              for r in sorted({v["reason"] for v in vectors})},
            "per_vector": cost,
        }
    categories = {}
    for v in vectors:
        key = f"{v['category']}.{'valid' if v['expected'] else 'invalid'}"
        categories[key] = categories.get(key, 0) + 1
    (HERE / "results.json").write_text(json.dumps(
        {"vectors": len(vectors), "categories": categories, "acvp_tests": extra["acvp"],
         "cache_tests": extra["cache_tests"], "paths": per_path}, indent=1) + "\n")
    costly = {n: r["worst_invalid_over_worst_valid"] for n, r in per_path.items()
              if r["worst_invalid_over_worst_valid"] > MAX_REJECTION_RATIO}

    print(f"All {len(vectors)} vectors: {', '.join(PATHS)} agree with the reference. "
          f"{extra['acvp']} ACVP (baseline) and {extra['cache_tests']} cache tests pass.")
    print("| Path | Worst valid | Worst invalid | Ratio | Worst invalid input |")
    print("| --- | ---: | ---: | ---: | --- |")
    for name, r in per_path.items():
        print(f"| {name} | {r['worst_valid']['gas']:,} | {r['worst_invalid']['gas']:,} | "
              f"{r['worst_invalid_over_worst_valid']:.3f} | {r['worst_invalid']['description']} |")
    if costly:
        raise SystemExit(f"rejection costs more than {MAX_REJECTION_RATIO}x the worst acceptance: {costly}")


if __name__ == "__main__":
    main()
