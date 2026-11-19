#!/usr/bin/env python3
"""Turn a bench/pf14/gas/run.sh work directory into results.json, and check limits and budgets.

Same method, limits and class measure as bench/pf04/summarize.py (imported): L2 gas is snforge's
figure of the measured test minus its `setup_` twin. Fails if a network limit or a budget in
budgets.json is exceeded, or if a metric has no budget.

Usage: python3 -I bench/pf14/gas/summarize.py WORK_DIR CONTRACTS_TARGET_DIR OUT.json
"""

import json
import statistics
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent.parent / "pf04"))
from summarize import NETWORK_LIMITS, STEPS, class_size, gas_pairs, stats  # noqa: E402

CLASSES = ("HybridShakeVerifierFalcon1024", "HybridMigratableAccountV2")
WORST_VECTOR = 7


def main() -> None:
    work, target, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    vectors = {v["id"]: v for v in json.loads((HERE.parent / "vectors.json").read_text())["vectors"]
               if v["category"] == "valid"}
    d = gas_pairs((work / "gas.log").read_text())

    per = {n: d[f"validate_{n}"] for n in vectors}
    validate = {**stats(list(per.values())),
                "mean_by_blocks": {str(b): round(statistics.mean(g for n, g in per.items() if vectors[n]["blocks"] == b))
                                   for b in (16, 17)},
                "per_vector": per}
    selected = sorted(int(k.rsplit("_", 1)[1]) for k in d if k.startswith("declare_"))
    calls = {kind: {str(n): d[f"{kind}_{n}"] for n in selected} for kind in ("declare", "is_valid", "reject")}
    steps_raw = dict(STEPS.findall((work / "steps.log").read_text()))
    steps = int(steps_raw[f"validate_{WORST_VECTOR}"]) - int(steps_raw[f"setup_validate_{WORST_VECTOR}"])
    sizes = {c: class_size(target, c) for c in CLASSES}

    metrics = {"validate.mean": validate["mean"], "validate.worst": validate["worst"],
               "set_pq_key": d["set_pq_key"], "migrate": d["migrate"], "steps.worst_vector": steps}
    for kind, p in calls.items():
        metrics[f"{kind}.worst"] = max(p.values())
    for c, s in sizes.items():
        for k, val in s.items():
            metrics[f"size.{c}.{k}"] = val

    errors = []
    worst_validation = max(validate["worst"], metrics["declare.worst"])
    if worst_validation > NETWORK_LIMITS["validate_max_sierra_gas"]:
        errors.append(f"validation {worst_validation:,} gas > cap")
    if steps > NETWORK_LIMITS["validate_max_n_steps"]:
        errors.append(f"validation {steps:,} steps > cap")
    for c, s in sizes.items():
        for k, cap in (("casm_bytecode_felts", "max_casm_bytecode_felts"),
                       ("sierra_program_felts", "max_sierra_program_felts"),
                       ("contract_class_object_bytes", "max_contract_class_object_bytes"),
                       ("compiled_class_object_bytes", "max_compiled_class_object_bytes"),
                       ("declare_code_l2_gas", "max_receipt_l2_gas_in_block")):
            if s[k] > NETWORK_LIMITS[cap]:
                errors.append(f"{c} {k} {s[k]:,} > {NETWORK_LIMITS[cap]:,}")
    budgets = json.loads((HERE / "budgets.json").read_text())["max"]
    errors += [f"{k}: {metrics.get(k)} > budget {b}" for k, b in budgets.items()
               if metrics.get(k) is None or metrics[k] > b]
    errors += [f"{k}: {metrics[k]} has no budget" for k in sorted(set(metrics) - set(budgets))]

    env = dict(line.split("=", 1) for line in (work / "env.txt").read_text().splitlines())
    out.write_text(json.dumps({
        "description": "PF-14 Falcon-1024 account-level measurements; see bench/pf14/README.md",
        "env": env,
        "method": "snforge L2 gas (Sierra-gas mode): measured test minus its setup_ twin",
        "network_limits": NETWORK_LIMITS,
        "validate": validate,
        "selected_vectors": selected,
        **calls,
        "set_pq_key_from_falcon512": d["set_pq_key"],
        "migrate_straight_to_falcon1024": d["migrate"],
        "validate_steps_worst_vector": steps,
        "class_sizes": sizes,
        "libfuncs": "every class builds with allowed-libfuncs-deny against bench/pf04/network_libfuncs.json",
        "metrics": metrics,
    }, indent=2) + "\n")

    cap = NETWORK_LIMITS["validate_max_sierra_gas"]
    print("| Path | L2 gas | of the 100M cap |")
    print("| --- | ---: | ---: |")
    for label, g in (("`__validate__`, mean", validate["mean"]), ("`__validate__`, worst", validate["worst"]),
                     ("`__validate__`, mean of 16-block vectors", validate["mean_by_blocks"]["16"]),
                     ("`__validate__`, mean of 17-block vectors", validate["mean_by_blocks"]["17"]),
                     ("`__validate_declare__`, worst of selected", metrics["declare.worst"]),
                     ("`is_valid_signature`, worst of selected", metrics["is_valid.worst"]),
                     ("rejected signature, worst of selected", metrics["reject.worst"])):
        print(f"| {label} | {g:,} | {g / cap:.1%} |")
    for label, g in (("`set_pq_key` Falcon-512 -> Falcon-1024", d["set_pq_key"]),
                     ("`migrate` straight to Falcon-1024", d["migrate"])):
        print(f"| {label} | {g:,} | in `__execute__`, not validation |")
    print(f"\nsteps (vector {WORST_VECTOR}): {steps:,}")
    block = NETWORK_LIMITS["max_receipt_l2_gas_in_block"]
    print("\n| Class | CASM felts | Sierra felts | Class object bytes | Compiled object bytes | Declare L2 gas | of block cap |")
    print("| --- | ---: | ---: | ---: | ---: | ---: | ---: |")
    for c, s in sizes.items():
        print(f"| `{c}` | {s['casm_bytecode_felts']:,} | {s['sierra_program_felts']:,} | "
              f"{s['contract_class_object_bytes']:,} | {s['compiled_class_object_bytes']:,} | "
              f"{s['declare_code_l2_gas']:,} | {s['declare_code_l2_gas'] / block:.1%} |")
    if errors:
        sys.exit("\n".join("LIMIT OR BUDGET: " + e for e in errors))
    print("\nwithin network limits and budgets")


if __name__ == "__main__":
    main()
