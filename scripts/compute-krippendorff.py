#!/usr/bin/env python3
"""Compute Krippendorff's alpha (interval level) per task across the 5 judges.

Reads judge totals from results/{task}/_blind-eval/<Label>/round*/<judge>-judge.json
plus the canonical root layout. Writes results/krippendorff-alpha.json.

The reliability data are arranged as: each blind label is one "unit," and each
of the 5 judges is one "coder." The judge value per unit is that judge's mean
total across all rounds (root + roundN/) for that label. Missing judge slots
are dropped per Krippendorff's standard handling.
"""

import json
import os
import re
import sys
import statistics
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TASKS = ("feature", "bugfix", "refactor")
JUDGES = ("opus", "grok420", "glm51", "gpt54pro", "mimo25pro")
ROUND_RE = re.compile(r"^round[0-9]+$")


def task_eval_dir(task: str) -> str:
    return (
        f"{ROOT}/results/_blind-eval"
        if task == "feature"
        else f"{ROOT}/results/{task}/_blind-eval"
    )


def sum_scores(d: dict):
    s = d.get("scores")
    if isinstance(s, dict) and s:
        return float(sum(s.values()))
    p = d.get("phase2") or {}
    if isinstance(p.get("scores"), dict) and p["scores"]:
        return float(sum(p["scores"].values()))
    return None


def collect_units(task: str) -> dict:
    """Returns {label: {judge: mean_total_across_rounds}}."""
    eval_dir = task_eval_dir(task)
    mapping_path = f"{eval_dir}/.mapping-DO-NOT-OPEN.json"
    mapping = json.load(open(mapping_path))["mapping"]
    units = {}
    for label in mapping:
        label_dir = f"{eval_dir}/{label}"
        if not os.path.isdir(label_dir):
            continue
        round_dirs = [label_dir] + sorted(
            os.path.join(label_dir, d)
            for d in os.listdir(label_dir)
            if os.path.isdir(os.path.join(label_dir, d)) and ROUND_RE.match(d)
        )
        per_judge: dict[str, list[float]] = defaultdict(list)
        for rd in round_dirs:
            for j in JUDGES:
                fp = f"{rd}/{j}-judge.json"
                if not os.path.isfile(fp) or os.path.getsize(fp) == 0:
                    continue
                try:
                    total = sum_scores(json.load(open(fp)))
                except Exception:
                    total = None
                if total is not None:
                    per_judge[j].append(total)
        unit = {j: statistics.mean(v) for j, v in per_judge.items() if v}
        if len(unit) >= 2:
            units[label] = unit
    return units


def krippendorff_alpha_interval(units: dict) -> dict:
    """Krippendorff's alpha for interval data using the coincidence-matrix shortcut.

    Pairable values per unit u: m_u choose 2 ordered pairs.
    D_o = sum over units of sum over ordered (i,j), i!=j of (v_ui - v_uj)^2 / (m_u - 1)
          all divided by total pairable values × 2  (per the standard derivation;
          we use the equivalent simplified form: D_o = (1/N_pairs) * sum_u sum_{i<j}(...)^2)
    Actually we implement the standard form:
       n_units_pairable = sum_u m_u where m_u >= 2
       D_o numerator: sum_u (1/(m_u - 1)) * sum_{i<j} (v_ui - v_uj)^2 * 2
       D_o = numerator / n_units_pairable
       D_e numerator: sum over all distinct value-pairs (i,j) across the corpus
                      (v_i - v_j)^2,  where the pool flattens all observations.
       D_e = numerator / (n_corpus * (n_corpus - 1))
       alpha = 1 - D_o / D_e
    """
    pairable_units = [list(u.values()) for u in units.values() if len(u) >= 2]
    if not pairable_units:
        return {"alpha": None, "n_units": 0, "n_observations": 0}

    n_units_pairable = sum(len(u) for u in pairable_units)

    do_num = 0.0
    for vals in pairable_units:
        m = len(vals)
        s = 0.0
        for i in range(m):
            for j in range(i + 1, m):
                s += (vals[i] - vals[j]) ** 2
        do_num += (s * 2.0) / (m - 1)
    d_o = do_num / n_units_pairable

    pool = [v for vals in pairable_units for v in vals]
    n_corpus = len(pool)
    de_num = 0.0
    for i in range(n_corpus):
        for j in range(n_corpus):
            if i == j:
                continue
            de_num += (pool[i] - pool[j]) ** 2
    d_e = de_num / (n_corpus * (n_corpus - 1)) if n_corpus > 1 else 0.0

    alpha = 1 - (d_o / d_e) if d_e > 0 else None
    return {
        "alpha": alpha,
        "n_units": len(pairable_units),
        "n_observations": n_units_pairable,
        "d_o": d_o,
        "d_e": d_e,
    }


def main() -> int:
    out: dict = {
        "method": "Krippendorff alpha, interval level, judges-as-coders, labels-as-units",
        "judges": list(JUDGES),
        "tasks": {},
    }
    for task in TASKS:
        units = collect_units(task)
        result = krippendorff_alpha_interval(units)
        out["tasks"][task] = result
        a = result.get("alpha")
        astr = f"{a:.4f}" if a is not None else "—"
        print(
            f"{task:<10} alpha={astr}  units={result['n_units']:>3}  obs={result['n_observations']:>3}",
            file=sys.stderr,
        )

    out_path = f"{ROOT}/results/krippendorff-alpha.json"
    with open(out_path, "w") as f:
        json.dump(out, f, indent=2)
    print(f"Wrote {out_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
