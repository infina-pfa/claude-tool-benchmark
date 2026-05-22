#!/usr/bin/env python3
"""
Three-way Spearman ρ triangulation across the comparative lanes.

For each task, computes ρ between:
  - panel weighted-mean rank ↔ Opus-1M comparative rank   (already in opus1m _aggregate.json)
  - panel weighted-mean rank ↔ GPT-5.4 comparative rank   (already in gpt54 _aggregate.json)
  - Opus-1M comparative rank ↔ GPT-5.4 comparative rank   (NEW — computed here)

Separates regime drift (both comparative lanes diverge from panel together) from
vendor bias (one comparative lane diverges, the other agrees with panel).

Reads:
  results/<task>/_comparative-eval/_aggregate.json         (opus1m lane)
  results/<task>/_comparative-eval/_aggregate.gpt54.json   (gpt54 lane)

Writes:
  results/_comparative-eval/_triangulation.json
  results/_comparative-eval/_triangulation.md
"""
from __future__ import annotations
import json, sys
from pathlib import Path
from typing import Dict, List


def spearman_rho(rank_a: List[int], rank_b: List[int]) -> float:
    n = len(rank_a)
    if n < 2:
        return float('nan')
    mean_a = sum(rank_a) / n
    mean_b = sum(rank_b) / n
    num = sum((a - mean_a) * (b - mean_b) for a, b in zip(rank_a, rank_b))
    den_a = sum((a - mean_a) ** 2 for a in rank_a) ** 0.5
    den_b = sum((b - mean_b) ** 2 for b in rank_b) ** 0.5
    if den_a == 0 or den_b == 0:
        return float('nan')
    return num / (den_a * den_b)


def classify(rho_panel_opus: float, rho_panel_gpt: float, rho_opus_gpt: float) -> str:
    """One-line read across the three correlations.

    Thresholds chosen to be readable, not load-bearing:
      |ρ| < 0.3   → weak / noise
      0.3 ≤ |ρ|  → meaningful
      0.7 ≤ |ρ|  → strong
    """
    def bucket(r: float) -> str:
        if r != r:  # NaN
            return 'na'
        ar = abs(r)
        if ar < 0.3:
            return 'weak'
        if ar < 0.7:
            return 'mid'
        return 'strong'

    pb_o = bucket(rho_panel_opus)
    pb_g = bucket(rho_panel_gpt)
    oo_g = bucket(rho_opus_gpt)

    # Regime drift: panel disagrees with both comp lanes, but the two comp lanes agree with each other.
    if pb_o in ('weak', 'mid') and pb_g in ('weak', 'mid') and oo_g == 'strong':
        return 'regime drift — head-to-head re-orders independent of vendor'
    # Vendor bias: one comp lane tracks panel, the other doesn't.
    if pb_o == 'strong' and pb_g in ('weak', 'mid'):
        return 'vendor bias — gpt-comp diverges, opus-comp tracks panel'
    if pb_g == 'strong' and pb_o in ('weak', 'mid'):
        return 'vendor bias — opus-comp diverges, gpt-comp tracks panel'
    # All three strong: robust ordering.
    if pb_o == 'strong' and pb_g == 'strong' and oo_g == 'strong':
        return 'robust — ordering survives regime and vendor swap'
    # All three weak/mid and inter-comp also low: orderings unreliable across regimes.
    if oo_g in ('weak',) and pb_o in ('weak',) and pb_g in ('weak',):
        return 'unreliable — neither regime agrees with panel or each other'
    return 'mixed — partial agreement, see per-row ρ'


def triangulate_task(task: str, results_root: Path) -> dict:
    task_dir = results_root if task == 'feature' else results_root / task
    comp_dir = task_dir / '_comparative-eval'
    opus_p = comp_dir / '_aggregate.json'
    gpt_p = comp_dir / '_aggregate.gpt54.json'

    if not opus_p.is_file() or not gpt_p.is_file():
        return {'task': task, 'error': f'missing aggregate(s): opus={opus_p.exists()} gpt={gpt_p.exists()}'}

    opus = json.load(open(opus_p))
    gpt = json.load(open(gpt_p))

    if 'error' in opus or 'error' in gpt:
        return {'task': task, 'error': f'aggregate has error: opus={opus.get("error")} gpt={gpt.get("error")}'}

    # ρ(panel, opus) and ρ(panel, gpt) are already on the aggregates.
    rho_panel_opus = opus.get('spearman_rho', float('nan'))
    rho_panel_gpt = gpt.get('spearman_rho', float('nan'))

    # ρ(opus, gpt) — compute over the common tool set across both comparative lanes.
    opus_rank = opus['comparative_rank']
    gpt_rank = gpt['comparative_rank']
    common = sorted(set(opus_rank.keys()) & set(gpt_rank.keys()))
    rho_opus_gpt = spearman_rho([opus_rank[t] for t in common], [gpt_rank[t] for t in common])

    read = classify(rho_panel_opus, rho_panel_gpt, rho_opus_gpt)

    # Per-tool rank deltas across all three rankings.
    panel_rank = opus['panel_rank']  # same panel in both aggregates by construction
    rows = []
    for t in sorted(common, key=lambda x: panel_rank.get(x, 99)):
        rows.append({
            'tool': t,
            'panel_rank': panel_rank.get(t),
            'opus_comp_rank': opus_rank.get(t),
            'gpt_comp_rank': gpt_rank.get(t),
            'opus_vs_panel': (panel_rank.get(t) - opus_rank.get(t)) if t in panel_rank and t in opus_rank else None,
            'gpt_vs_panel': (panel_rank.get(t) - gpt_rank.get(t)) if t in panel_rank and t in gpt_rank else None,
            'opus_vs_gpt': (opus_rank.get(t) - gpt_rank.get(t)),
        })

    return {
        'task': task,
        'n_tools': len(common),
        'tools_common': common,
        'rho_panel_opus': rho_panel_opus,
        'rho_panel_gpt': rho_panel_gpt,
        'rho_opus_gpt': rho_opus_gpt,
        'read': read,
        'rows': rows,
    }


def fmt_rho(r: float) -> str:
    return f"{r:.3f}" if r == r else "—"


def render_markdown(results: List[dict]) -> str:
    lines: List[str] = []
    lines.append("# Comparative-rank triangulation — panel vs Opus-1M vs GPT-5.4")
    lines.append("")
    lines.append("Three Spearman ρ values per task across the regime/vendor space:")
    lines.append("")
    lines.append("- **panel ↔ opus-comp** — does the 5-judge per-artifact panel agree with Opus-1M's head-to-head ranking?")
    lines.append("- **panel ↔ gpt-comp** — does the panel agree with GPT-5.4's head-to-head ranking?")
    lines.append("- **opus-comp ↔ gpt-comp** — do the two head-to-head lanes agree *with each other*?")
    lines.append("")
    lines.append("Reading the triangle:")
    lines.append("")
    lines.append("- Both `panel↔comp` low *and* `opus↔gpt` high → **regime drift**: the head-to-head regime re-orders tools regardless of which vendor judges.")
    lines.append("- One `panel↔comp` high, the other low, with `opus↔gpt` low → **vendor bias**: the dissenting lane is the outlier.")
    lines.append("- All three high → **robust** ordering across regime and vendor.")
    lines.append("- All three low → **unreliable** — the lanes disagree among themselves and with the panel.")
    lines.append("")
    lines.append("## Triangle")
    lines.append("")
    lines.append("| Task | panel↔opus | panel↔gpt | opus↔gpt | n tools | Read |")
    lines.append("|---|---|---|---|---|---|")
    for r in results:
        if 'error' in r:
            lines.append(f"| {r['task']} | — | — | — | — | _{r['error']}_ |")
            continue
        lines.append(
            f"| {r['task']} | {fmt_rho(r['rho_panel_opus'])} | "
            f"{fmt_rho(r['rho_panel_gpt'])} | {fmt_rho(r['rho_opus_gpt'])} | "
            f"{r['n_tools']} | {r['read']} |"
        )
    lines.append("")
    lines.append("## Per-tool rank, all three rankings")
    lines.append("")
    for r in results:
        if 'error' in r:
            continue
        lines.append(f"### {r['task']}")
        lines.append("")
        lines.append("| Tool | Panel | Opus-comp | GPT-comp | Opus−panel | GPT−panel | Opus−GPT |")
        lines.append("|---|---|---|---|---|---|---|")
        def fmt_delta(d):
            if d is None:
                return "—"
            return f"{'+' if d > 0 else ''}{d}"
        for row in r['rows']:
            lines.append(
                f"| {row['tool']} | {row['panel_rank']} | {row['opus_comp_rank']} | "
                f"{row['gpt_comp_rank']} | {fmt_delta(row['opus_vs_panel'])} | "
                f"{fmt_delta(row['gpt_vs_panel'])} | {fmt_delta(row['opus_vs_gpt'])} |"
            )
        lines.append("")
    return '\n'.join(lines)


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--results-root', default='results')
    args = ap.parse_args()

    results_root = Path(args.results_root).resolve()
    tasks = ['feature', 'bugfix', 'refactor']
    results = [triangulate_task(t, results_root) for t in tasks]

    out_dir = results_root / '_comparative-eval'
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / '_triangulation.json').write_text(json.dumps(results, indent=2))
    (out_dir / '_triangulation.md').write_text(render_markdown(results))

    for r in results:
        if 'error' in r:
            print(f"{r['task']}: {r['error']}")
        else:
            print(
                f"{r['task']}: panel↔opus={fmt_rho(r['rho_panel_opus'])}  "
                f"panel↔gpt={fmt_rho(r['rho_panel_gpt'])}  "
                f"opus↔gpt={fmt_rho(r['rho_opus_gpt'])}  → {r['read']}"
            )
    print(f"\nWritten: {out_dir / '_triangulation.md'}")


if __name__ == '__main__':
    main()
