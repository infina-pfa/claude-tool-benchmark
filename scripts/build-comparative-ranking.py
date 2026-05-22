#!/usr/bin/env python3
"""
Build a STANDALONE comparative-only ranking — independent of the 5-judge panel
weighted mean. This is a parallel validity signal; it does NOT enter the
canonical benchmark result.

Accumulation method
-------------------
- One comparative judgment = one model ranking all 8 tools 1..8 head-to-head
  in a single prompt.
- Per (task, lane) the lane runs 25 cells (5 trials x 5 rounds), so every tool
  has 25 rank observations per lane.
- Two lanes (Opus-1M, GPT-5.4) -> 50 pooled observations per (tool, task).
  The lanes are pooled with EQUAL weight: the comparative lanes have no
  pre-registered weighting (unlike the panel's 3/2/1/1/1), and each lane has
  exactly n=25, so the pooled mean == the simple average of the two lane means.
- Per-tool comparative score = mean pooled rank (lower = better); spread = the
  stdev across the 50 pooled observations.
- Per-task ranking = sort by ascending pooled mean rank.
- Overall leaderboard = mean of a tool's 3 per-task mean ranks (equal task
  weight, mirroring the panel's cross-task treatment), sorted ascending.

Inputs (per task, both lanes):
  results/<task>/_comparative-eval/_aggregate.json        (lane: opus1m)
  results/<task>/_comparative-eval/_aggregate.gpt54.json  (lane: gpt54)
  (feature is the root task -> results/_comparative-eval/)

Outputs:
  results/_comparative-eval/_comparative-ranking.json
  results/_comparative-eval/_comparative-ranking.md
"""
import json
import statistics
from pathlib import Path

TASKS = ("feature", "bugfix", "refactor")
LANES = (("opus1m", "_aggregate.json"), ("gpt54", "_aggregate.gpt54.json"))
ROOT = Path(__file__).resolve().parent.parent


def task_dir(task: str) -> Path:
    return ROOT / "results" / "_comparative-eval" if task == "feature" \
        else ROOT / "results" / task / "_comparative-eval"


def load_lane(task: str, fname: str) -> dict:
    """Return {tool: [rank, ...]} of raw per-cell observations for one lane."""
    data = json.loads((task_dir(task) / fname).read_text())
    return {
        tool: [o["rank"] for o in pt["observations"]]
        for tool, pt in data["per_tool"].items()
    }


def main() -> None:
    per_task = {}
    tools = None
    for task in TASKS:
        lanes = {lane: load_lane(task, fname) for lane, fname in LANES}
        task_tools = sorted(set().union(*[set(d) for d in lanes.values()]))
        tools = tools or set(task_tools)
        tools &= set(task_tools)
        rows = []
        for tool in task_tools:
            pooled = []
            lane_means = {}
            for lane, _ in LANES:
                obs = lanes[lane].get(tool, [])
                lane_means[lane] = round(statistics.mean(obs), 3) if obs else None
                pooled += obs
            rows.append({
                "tool": tool,
                "mean_rank": round(statistics.mean(pooled), 3),
                "sd_rank": round(statistics.pstdev(pooled), 3),
                "n": len(pooled),
                "opus1m_mean": lane_means["opus1m"],
                "gpt54_mean": lane_means["gpt54"],
            })
        rows.sort(key=lambda r: r["mean_rank"])
        for i, r in enumerate(rows, 1):
            r["comparative_rank"] = i
        per_task[task] = rows

    overall = []
    for tool in sorted(tools):
        task_means = [
            next(r["mean_rank"] for r in per_task[t] if r["tool"] == tool)
            for t in TASKS
        ]
        overall.append({
            "tool": tool,
            "overall_mean_rank": round(statistics.mean(task_means), 3),
            "per_task": {t: tm for t, tm in zip(TASKS, task_means)},
        })
    overall.sort(key=lambda r: r["overall_mean_rank"])
    for i, r in enumerate(overall, 1):
        r["comparative_rank"] = i

    out = {
        "_comment": "Standalone comparative-only ranking. Parallel validity "
                    "signal — NOT the canonical benchmark result (the panel "
                    "weighted mean is). Lower mean rank = better. Two lanes "
                    "(Opus-1M, GPT-5.4) pooled equal-weight, 50 obs per "
                    "(tool, task).",
        "method": "pooled mean of 1..8 head-to-head ranks; per task = 50 obs "
                  "(2 lanes x 25 cells); overall = mean of 3 per-task means",
        "per_task": per_task,
        "overall": overall,
    }
    cmp_dir = ROOT / "results" / "_comparative-eval"
    (cmp_dir / "_comparative-ranking.json").write_text(json.dumps(out, indent=2))

    lines = [
        "# Comparative-only ranking (standalone)",
        "",
        "**Parallel validity signal — NOT the canonical benchmark result.** The",
        "canonical ranking is the 5-judge panel weighted mean (see the per-task",
        "`final-report.md`). This table is built *purely* from the comparative",
        "head-to-head judge lanes and never enters the weighted mean.",
        "",
        "**Method.** One comparative judgment = one model ranking all 8 tools",
        "1–8 in one prompt. Per (task, lane) = 25 cells (5 trials × 5 rounds);",
        "two lanes (Opus-1M + GPT-5.4) pooled equal-weight = **50 observations",
        "per (tool, task)**. Score = mean pooled rank (lower = better). Overall",
        "= mean of the 3 per-task mean ranks.",
        "",
        "## Overall comparative leaderboard",
        "",
        "| Rank | Tool | Comp. mean rank | feature | bugfix | refactor |",
        "|---|---|---:|---:|---:|---:|",
    ]
    for r in overall:
        pt = r["per_task"]
        lines.append(
            f"| {r['comparative_rank']} | `{r['tool']}` | "
            f"**{r['overall_mean_rank']:.2f}** | {pt['feature']:.2f} | "
            f"{pt['bugfix']:.2f} | {pt['refactor']:.2f} |"
        )
    for task in TASKS:
        lines += [
            "",
            f"## {task} — comparative-only ranking",
            "",
            "| Rank | Tool | Mean rank | σ | Opus-1M | GPT-5.4 |",
            "|---|---|---:|---:|---:|---:|",
        ]
        for r in per_task[task]:
            lines.append(
                f"| {r['comparative_rank']} | `{r['tool']}` | "
                f"**{r['mean_rank']:.2f}** | {r['sd_rank']:.2f} | "
                f"{r['opus1m_mean']:.2f} | {r['gpt54_mean']:.2f} |"
            )
    lines += [
        "",
        "Generated by `scripts/build-comparative-ranking.py` from "
        "`results/<task>/_comparative-eval/_aggregate{,.gpt54}.json`.",
        "",
    ]
    (cmp_dir / "_comparative-ranking.md").write_text("\n".join(lines))
    print("wrote results/_comparative-eval/_comparative-ranking.{json,md}")
    print("\nOverall:")
    for r in overall:
        print(f"  {r['comparative_rank']}. {r['tool']:<11} "
              f"{r['overall_mean_rank']:.2f}")


if __name__ == "__main__":
    main()
