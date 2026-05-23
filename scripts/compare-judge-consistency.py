#!/usr/bin/env python3
"""Compare per-judge round-to-round consistency for a single blind-eval label.

For each judge with per-round files in results/$TASK/_blind-eval/<Label>/round*/
(default judges: opus, codex, qwen, deepseek), report:

  - n rounds available
  - total score per round (sum of scores.values())
  - mean, stdev, range
  - per-item stdev summary (mean and max across the 20 rubric items)

This is the primary consistency diagnostic when deciding whether a new judge
belongs on the panel: we want small round-to-round σ and per-item stability
comparable to the judges already in use.

Usage:
  TASK=feature scripts/compare-judge-consistency.py Alpha
  TASK=feature scripts/compare-judge-consistency.py Alpha --judges qwen deepseek
"""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import statistics
import sys
from pathlib import Path

DEFAULT_JUDGES = ["opus", "codex", "qwen", "deepseek"]


def task_results_dir(task: str) -> Path:
    home = Path(os.environ.get("BENCH_HOME") or Path(__file__).resolve().parent.parent)
    if task == "feature":
        return home / "results"
    return home / "results" / task


def load_round_scores(label_dir: Path, judge: str) -> dict[int, dict[str, int]]:
    """Return {round_index: {item_id: score}} for the canonical judge file per round."""
    rounds: dict[int, dict[str, int]] = {}
    for child in sorted(label_dir.iterdir()):
        if not child.is_dir():
            continue
        m = re.fullmatch(r"round(\d+)", child.name)
        if not m:
            continue
        judge_file = child / f"{judge}-judge.json"
        if not judge_file.exists() or judge_file.stat().st_size == 0:
            continue
        try:
            with judge_file.open() as f:
                data = json.load(f)
        except json.JSONDecodeError:
            continue
        scores = data.get("scores")
        if not isinstance(scores, dict) or not scores:
            continue
        rounds[int(m.group(1))] = {k: int(v) for k, v in scores.items()}
    return rounds


def summarize(rounds: dict[int, dict[str, int]]) -> dict:
    if not rounds:
        return {"n": 0}
    ordered = sorted(rounds.items())
    totals = [sum(sc.values()) for _, sc in ordered]
    out = {
        "n": len(totals),
        "rounds": [r for r, _ in ordered],
        "totals": totals,
        "total_mean": statistics.fmean(totals),
        "total_stdev": statistics.stdev(totals) if len(totals) > 1 else 0.0,
        "total_range": max(totals) - min(totals),
    }
    # Per-item stdev: only include items present in ALL rounds.
    item_keys = set.intersection(*(set(sc.keys()) for _, sc in ordered))
    if len(ordered) > 1 and item_keys:
        item_stdevs = []
        for k in sorted(item_keys, key=lambda s: int(s) if s.isdigit() else s):
            series = [rounds[r][k] for r, _ in ordered]
            item_stdevs.append(statistics.stdev(series))
        out["per_item_stdev_mean"] = statistics.fmean(item_stdevs)
        out["per_item_stdev_max"] = max(item_stdevs)
    return out


def format_row(judge: str, s: dict) -> str:
    if not s.get("n"):
        return f"  {judge:<10} (no data)"
    totals = ",".join(str(t) for t in s["totals"])
    line = (
        f"  {judge:<10} n={s['n']}  rounds={s['rounds']}  totals=[{totals}]  "
        f"mean={s['total_mean']:6.2f}  σ={s['total_stdev']:5.2f}  range={s['total_range']}"
    )
    if "per_item_stdev_mean" in s:
        line += f"  item-σ: mean={s['per_item_stdev_mean']:.2f} max={s['per_item_stdev_max']:.2f}"
    return line


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("label", help="Blind-eval label (e.g. Alpha)")
    ap.add_argument("--judges", nargs="*", default=DEFAULT_JUDGES,
                    help=f"Judges to include (default: {' '.join(DEFAULT_JUDGES)})")
    ap.add_argument("--task", default=os.environ.get("TASK", "feature"),
                    help="Task id (feature | bugfix | refactor). Defaults to $TASK.")
    args = ap.parse_args()

    label_dir = task_results_dir(args.task) / "_blind-eval" / args.label
    if not label_dir.is_dir():
        print(f"ERROR: {label_dir} not found", file=sys.stderr)
        return 1

    print(f"Label: {args.label}  Task: {args.task}")
    print(f"Dir:   {label_dir}")
    print()
    print("Round-to-round consistency (sum-of-scores across rounds):")
    for judge in args.judges:
        rounds = load_round_scores(label_dir, judge)
        print(format_row(judge, summarize(rounds)))

    print()
    print("Interpretation:")
    print("  σ = stdev across rounds (lower = more consistent).")
    print("  item-σ mean = average per-rubric-item stdev (lower = tighter per-item scoring).")
    print("  Compare a candidate judge's σ to the incumbent panel to gauge fitness.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
