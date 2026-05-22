#!/usr/bin/env python3
"""
R1 mechanical-fact override per v2-plan §3c R1 + §3.5.2.

Task-aware. Each task pins a different set of rubric item IDs to
deterministic values read from `auto-metrics.json`:

  feature   12 tsc / 13 eslint / 16 Mode 1 tests / 20 lines_removed scope
  bugfix    14 tsc / 15 new_eslint
  refactor  13 savings-cd tests / 14 core tests

These items have deterministic answers — the judge prompt asks LLMs
to copy them from a `## Mechanical Facts` block, but compliance is
partial, so the override deterministically rewrites them post-hoc.

Usage:
  python3 scripts/apply-r1-override.py <label_dir>      # whole label
  python3 scripts/apply-r1-override.py <judge.json>     # single file

Auto-detects task from `$TASK` env (default: feature). Override with
`--task <name>`. Idempotent.
"""

from __future__ import annotations

import json
import math
import os
import sys
from pathlib import Path


def _targets_for_task(task: str, am: dict) -> dict[str, tuple[int, str]]:
    """Return {item_id: (locked_score, metric_field_used)} for this task."""
    if task == "feature":
        # Item 16 keys off tests_core_failed (Mode-1 only, matches the rubric
        # wording "Does not break existing Mode 1"); item 20 mirrors the
        # judge-prompt formula `max(0, 10 - ceil(lines_removed/10))`.
        lines_removed = int(am.get("lines_removed", 0))
        s20 = 10 if lines_removed == 0 else max(0, 10 - math.ceil(lines_removed / 10))
        return {
            "12": (10 if am["tsc_errors"] == 0 else 0, "tsc_errors"),
            "13": (10 if am["eslint_errors"] == 0 else 0, "eslint_errors"),
            "16": (10 if int(am["tests_core_failed"]) == 0 else 0, "tests_core_failed"),
            "20": (s20, "lines_removed"),
        }
    if task == "bugfix":
        # Item 15 reads from `new_eslint_errors` (diff-aware: errors in touched
        # files at HEAD minus errors in same files at BASE). The cohort-wide
        # `eslint_errors=10` value reflects baseline lint noise in the scope
        # pattern, not tool-introduced regressions, so it would punish every
        # trial uniformly — which is wrong. Populated by compute-new-eslint.py.
        return {
            "14": (10 if am["tsc_errors"] == 0 else 0, "tsc_errors"),
            "15": (10 if am["new_eslint_errors"] == 0 else 0, "new_eslint_errors"),
        }
    if task == "refactor":
        return {
            "13": (10 if int(am["tests_savings_cd_failed"]) == 0 else 0, "tests_savings_cd_failed"),
            "14": (10 if int(am["tests_core_failed"]) == 0 else 0, "tests_core_failed"),
        }
    sys.exit(f"REFUSED: no R1 mapping defined for TASK={task}")


def override(scores: dict, am: dict, task: str) -> tuple[dict, list[tuple[str, int, int]]]:
    new = dict(scores)
    deltas: list[tuple[str, int, int]] = []
    targets = _targets_for_task(task, am)
    for item, (target, _src) in targets.items():
        cur = int(new.get(item, 0))
        if cur != target:
            deltas.append((item, cur, target))
            new[item] = target
    return new, deltas


def apply_to_file(judge_path: Path, am: dict, task: str) -> tuple[int, int, list]:
    d = json.loads(judge_path.read_text())
    if not isinstance(d.get("scores"), dict):
        return 0, 0, []  # legacy schema; skip silently
    old_total = int(sum(d["scores"].values()))
    snapshot_added = "scores_pre_r1" not in d
    if snapshot_added:
        d["scores_pre_r1"] = dict(d["scores"])
    new_scores, deltas = override(d["scores"], am, task)
    d["scores"] = new_scores
    new_total = int(sum(new_scores.values()))
    if old_total != new_total:
        d["total"] = new_total
    if snapshot_added or old_total != new_total:
        judge_path.write_text(json.dumps(d, indent=2))
    return old_total, new_total, deltas


def _header_metrics(task: str, am: dict) -> str:
    if task == "feature":
        return (
            f"tsc={am['tsc_errors']} eslint={am['eslint_errors']} "
            f"tests_core_failed={am.get('tests_core_failed', '?')} "
            f"lines_removed={am.get('lines_removed', '?')}"
        )
    if task == "bugfix":
        return f"tsc={am['tsc_errors']} new_eslint={am['new_eslint_errors']}"
    if task == "refactor":
        return f"savings_failed={am['tests_savings_cd_failed']} core_failed={am['tests_core_failed']}"
    return ""


def apply_to_label(label_dir: Path, task: str) -> None:
    am_path = label_dir / "auto-metrics.json"
    if not am_path.exists():
        sys.exit(f"ERROR: {am_path} missing")
    am = json.loads(am_path.read_text())
    print(f"=== {label_dir.name} [{task}]: {_header_metrics(task, am)} ===")
    judge_files = sorted(label_dir.rglob("*-judge.json"))
    for jf in judge_files:
        # Skip backups and pre-rerun archives.
        if jf.name.endswith(".pre-r1.json") or ".pre-rerun" in jf.name or ".pre-v2-pilot" in jf.name:
            continue
        old, new, deltas = apply_to_file(jf, am, task)
        rel = jf.relative_to(label_dir)
        if deltas:
            d_str = " | ".join(f"i{i}: {o}→{n}" for i, o, n in deltas)
            print(f"  {rel}: {old}→{new}  [{d_str}]")
        else:
            print(f"  {rel}: {old} (no override needed)")


def main(argv: list[str]) -> None:
    if len(argv) < 2:
        sys.exit(__doc__)
    args = list(argv[1:])
    task_override = None
    if "--task" in args:
        i = args.index("--task")
        task_override = args[i + 1]
        del args[i:i + 2]
    task = task_override or os.environ.get("TASK", "feature")
    if not args:
        sys.exit(__doc__)
    target = Path(args[0])
    if target.is_dir():
        apply_to_label(target, task)
    elif target.is_file() and target.name.endswith("-judge.json"):
        # Walk up to find the label dir's auto-metrics.json
        label_dir = target.parent
        while label_dir != label_dir.parent:
            if (label_dir / "auto-metrics.json").exists():
                break
            label_dir = label_dir.parent
        if not (label_dir / "auto-metrics.json").exists():
            sys.exit(f"ERROR: no auto-metrics.json in any ancestor of {target}")
        am = json.loads((label_dir / "auto-metrics.json").read_text())
        old, new, deltas = apply_to_file(target, am, task)
        d_str = " | ".join(f"i{i}: {o}→{n}" for i, o, n in deltas) if deltas else "no change"
        print(f"{target}: {old}→{new}  [{d_str}]")
    else:
        sys.exit(f"ERROR: {target} is not a label dir or judge JSON")


if __name__ == "__main__":
    main(sys.argv)
