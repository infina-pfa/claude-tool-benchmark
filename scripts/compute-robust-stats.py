#!/usr/bin/env python3
"""Compute robust-statistics companion (median and trimmed mean) for the canonical corpus.

Output: results/robust-statistics.json + (manually edited) results/robust-statistics-companion.md

Same aggregation rule as scripts/aggregate-results.sh (weighted mean of per-judge
means at the trial level), but instead of taking the arithmetic mean of the 5
trial-level weighted means, this script reports the median and trimmed mean
(drop highest and lowest trial) per (task, tool).

This is a SENSITIVITY VIEW, not the pre-registered primary statistic. The canonical
report is the headline; this file lets readers see whether rank ordering is robust
to single-trial outliers. The largest shift in this corpus is gstack refactor
(mean 144.92 → median 174.58) — one bad trial.

Reads versions.lock.json for judge weights.
"""
import collections
import glob
import json
import os
import re
import statistics
import sys


def trial_weighted_mean(per_judge_scores, weights):
    """Given dict {judge: [scores...]} (one trial's judgments), return weighted mean of per-judge means."""
    num = 0.0
    den = 0
    for j, w in weights.items():
        xs = per_judge_scores.get(j) or []
        if not xs:
            continue
        num += w * statistics.mean(xs)
        den += w
    return num / den if den else None


def trimmed_mean(xs):
    """Mean of xs with min and max dropped. Requires len(xs) >= 3."""
    if len(xs) < 3:
        return statistics.mean(xs)
    s = sorted(xs)
    return statistics.mean(s[1:-1])


def task_base_dir(task):
    return "results/_blind-eval" if task == "feature" else f"results/{task}/_blind-eval"


def main():
    lock = json.load(open("versions.lock.json"))
    weights = {j: v["weight"] for j, v in lock["judges"].items() if isinstance(v, dict)}

    out = {
        "method": (
            "Per-trial weighted mean of per-judge means (same rule as canonical aggregator) "
            "then report median and trimmed_mean (drop min and max trial) instead of arithmetic mean. "
            "Sensitivity view; not pre-registered."
        ),
        "weights": weights,
        "tasks": {},
    }

    for task in ("feature", "bugfix", "refactor"):
        base = task_base_dir(task)
        mfile = os.path.join(base, ".mapping-DO-NOT-OPEN.json")
        if not os.path.exists(mfile):
            print(f"warn: {task} missing mapping at {mfile}", file=sys.stderr)
            continue
        mapping = json.load(open(mfile))
        m = mapping.get("mapping", mapping) if isinstance(mapping, dict) else mapping

        per_tool_trial = collections.defaultdict(lambda: collections.defaultdict(list))
        for label, info in m.items():
            if label.startswith("_"):
                continue
            if not isinstance(info, dict):
                continue
            tool, trial = info.get("tool"), info.get("trial")
            if not tool or trial is None:
                continue
            lbl_dir = os.path.join(base, label)
            if not os.path.isdir(lbl_dir):
                continue
            rounds = [lbl_dir] + [
                os.path.join(lbl_dir, d)
                for d in os.listdir(lbl_dir)
                if re.fullmatch(r"round[0-9]+", d) and os.path.isdir(os.path.join(lbl_dir, d))
            ]
            for rd in rounds:
                for jf in glob.glob(os.path.join(rd, "*-judge.json")):
                    slot = os.path.basename(jf).replace("-judge.json", "")
                    try:
                        d = json.load(open(jf))
                    except (OSError, json.JSONDecodeError):
                        continue
                    if d.get("scores"):
                        per_tool_trial[(tool, trial)][slot].append(sum(d["scores"].values()))

        per_tool_means = collections.defaultdict(list)
        for (tool, trial), per_judge in per_tool_trial.items():
            wm = trial_weighted_mean(per_judge, weights)
            if wm is not None:
                per_tool_means[tool].append((trial, wm))

        rows = []
        for tool, lst in per_tool_means.items():
            lst.sort(key=lambda x: x[0])
            trials = [wm for _, wm in lst]
            rows.append({
                "tool": tool,
                "n_trials": len(trials),
                "mean": statistics.mean(trials),
                "median": statistics.median(trials),
                "trimmed_mean": trimmed_mean(trials),
                "min": min(trials),
                "max": max(trials),
                "spread": max(trials) - min(trials),
                "trial_values": [round(x, 4) for x in trials],
            })
        rows.sort(key=lambda r: -r["mean"])
        out["tasks"][task] = rows

    with open("results/robust-statistics.json", "w") as f:
        json.dump(out, f, indent=2)
    print("wrote results/robust-statistics.json")


if __name__ == "__main__":
    main()
