#!/usr/bin/env python3
"""
Aggregate the comparative-rank Opus-1M judge outputs into per-tool rank stats
and compute Spearman ρ against the existing panel's weighted-mean rank.

Reads:
  results/<task>/_comparative-eval/t<N>/round<R>/{opus1m-ranking.json, .mapping-DO-NOT-OPEN.json}
  results/<task>/_blind-eval/{.mapping-DO-NOT-OPEN.json, <NATO>/<judge>-judge.json}

Writes (per task):
  results/<task>/_comparative-eval/_aggregate.json    structured summary
  results/<task>/_comparative-eval/_aggregate.md      paste-into-report fragment

Aggregation rule per task:
  - For each (trial, round), comparative-judge emits a 1..N rank per tool.
  - Per-tool comparative rank = mean across (trials × rounds) for that tool.
  - Per-tool comparative rank σ = stdev across the same.
  - Final reported comparative ranking sorts tools by ascending mean-rank (rank 1 = best).

Validity probe (the headline number):
  - Compute panel weighted-mean per tool (same rule as scripts/aggregate-results.sh).
  - Rank tools by weighted-mean (desc = rank 1).
  - Spearman ρ between (panel_rank, comparative_rank).
  - Flag tools where |panel_rank − comparative_rank| ≥ 2.
"""
from __future__ import annotations
import argparse, hashlib, json, os, statistics, sys
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Tuple

JUDGES = ('opus', 'grok420', 'glm51', 'gpt54pro', 'mimo25pro')
JUDGE_WEIGHTS = {'opus': 3, 'gpt54pro': 2, 'grok420': 1, 'glm51': 1, 'mimo25pro': 1}

# Comparative lanes. Each lane = one model judging the side-by-side ranking.
# `ranking_filename` is what judge-<lane>-comparative.sh writes per cell.
# `aggregate_suffix` keeps opus1m at the legacy `_aggregate.{json,md}` paths so
# PAPER.md and final-report references don't move; new lanes get a suffix.
LANES = {
    'opus1m': {
        'ranking_filename': 'opus1m-ranking.json',
        'aggregate_suffix': '',
        'display_name': 'Opus-1M',
    },
    'gpt54': {
        'ranking_filename': 'gpt54-ranking.json',
        'aggregate_suffix': '.gpt54',
        'display_name': 'GPT-5.4',
    },
}


def panel_weighted_mean(blind_dir: Path, mapping_path: Path) -> Dict[str, float]:
    """Reimplements scripts/aggregate-results.sh balanced_mean(): weighted mean of per-judge
    per-tool means using JUDGE_WEIGHTS. Reads union of (label root + roundN/ subdirs)."""
    mapping = json.load(open(mapping_path))['mapping']
    import re
    round_re = re.compile(r'^round[0-9]+$')

    per_judge: Dict[str, Dict[str, List[float]]] = defaultdict(lambda: defaultdict(list))
    for label, info in mapping.items():
        tool = info['tool']
        label_dir = blind_dir / label
        if not label_dir.is_dir():
            continue
        locs = [label_dir]
        for sub in label_dir.iterdir():
            if sub.is_dir() and round_re.match(sub.name):
                locs.append(sub)
        for judge in JUDGES:
            for loc in locs:
                p = loc / f'{judge}-judge.json'
                if not p.is_file() or p.stat().st_size == 0:
                    continue
                try:
                    d = json.load(open(p))
                except Exception:
                    continue
                scores = d.get('scores') if isinstance(d.get('scores'), dict) else None
                if not scores:
                    p2 = (d.get('phase2') or {}).get('scores')
                    scores = p2 if isinstance(p2, dict) else None
                if not scores:
                    continue
                per_judge[tool][judge].append(float(sum(scores.values())))

    out: Dict[str, float] = {}
    for tool, jd in per_judge.items():
        num = den = 0.0
        for j in JUDGES:
            vals = jd.get(j) or []
            if not vals:
                continue
            w = JUDGE_WEIGHTS.get(j, 1)
            num += w * statistics.mean(vals)
            den += w
        out[tool] = num / den if den else 0.0
    return out


def spearman_rho(rank_a: List[int], rank_b: List[int]) -> float:
    """Spearman ρ via Pearson-on-ranks (rank inputs already; assumes no ties).
    For ties, would need average-rank handling; comparative ranks are 1..N with no ties.
    Panel ranks may have float-mean ties but they're dense-ordinal here too."""
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


def aggregate_task(task: str, results_root: Path, lane: str) -> dict:
    task_dir = results_root if task == 'feature' else results_root / task
    comp_dir = task_dir / '_comparative-eval'
    blind_dir = task_dir / '_blind-eval'
    blind_map = blind_dir / '.mapping-DO-NOT-OPEN.json'

    if not blind_map.is_file():
        return {'task': task, 'lane': lane, 'error': f'blind mapping missing: {blind_map}'}
    if not comp_dir.is_dir():
        return {'task': task, 'lane': lane, 'error': f'comparative dir missing: {comp_dir}'}

    ranking_filename = LANES[lane]['ranking_filename']

    # Collect per-tool ranks across all (trial, round) cells
    tool_ranks: Dict[str, List[Tuple[int, int, int]]] = defaultdict(list)  # tool -> [(trial, round, rank)]
    cells_seen: List[dict] = []
    blinding_warnings: List[dict] = []

    for trial_dir in sorted(comp_dir.iterdir()):
        if not trial_dir.is_dir() or not trial_dir.name.startswith('t'):
            continue
        try:
            trial = int(trial_dir.name[1:])
        except ValueError:
            continue
        for round_dir in sorted(trial_dir.iterdir()):
            if not round_dir.is_dir() or not round_dir.name.startswith('round'):
                continue
            try:
                round_n = int(round_dir.name[5:])
            except ValueError:
                continue
            map_p = round_dir / '.mapping-DO-NOT-OPEN.json'
            rank_p = round_dir / ranking_filename
            if not map_p.is_file() or not rank_p.is_file():
                continue
            try:
                with open(map_p, 'rb') as _mf:
                    map_bytes = _mf.read()
                rmap = json.loads(map_bytes)['mapping']
                rdata = json.load(open(rank_p))
            except Exception as e:
                cells_seen.append({'trial': trial, 'round': round_n, 'error': str(e)})
                continue
            # Provenance check: if the ranking JSON recorded the mapping hash at
            # judging time, verify it still matches. Mismatch = the mapping was
            # mutated after judging (re-shuffled, edited) and label→tool attributions
            # are no longer trustworthy. Absent hash = legacy data from before the
            # hash was introduced — skip the check.
            recorded_hash = rdata.get('mapping_sha256')
            if recorded_hash:
                current_hash = hashlib.sha256(map_bytes).hexdigest()
                if current_hash != recorded_hash:
                    msg = f'mapping_sha256 mismatch (recorded={recorded_hash[:12]}… current={current_hash[:12]}…)'
                    print(f'  [CORRUPTION] {task} t{trial} round{round_n}: {msg}', file=sys.stderr)
                    cells_seen.append({'trial': trial, 'round': round_n, 'error': msg})
                    continue
            for entry in rdata['ranking']:
                lbl = entry['label']; rk = entry['rank']
                tool = rmap[lbl]['tool']
                tool_ranks[tool].append((trial, round_n, rk))
            cells_seen.append({'trial': trial, 'round': round_n, 'ok': True})
            bc = (rdata.get('blinding_concerns') or '').strip()
            if bc:
                blinding_warnings.append({'trial': trial, 'round': round_n, 'concern': bc})

    if not tool_ranks:
        return {'task': task, 'lane': lane, 'error': 'no comparative ranking cells found'}

    # Per-tool mean / stdev
    per_tool = {}
    for tool, rs in tool_ranks.items():
        ranks = [r for (_, _, r) in rs]
        per_tool[tool] = {
            'mean_rank': statistics.mean(ranks),
            'stdev_rank': statistics.stdev(ranks) if len(ranks) > 1 else 0.0,
            'n_observations': len(ranks),
            'observations': [{'trial': t, 'round': r, 'rank': rk} for (t, r, rk) in rs],
        }

    # Comparative final rank: sort by mean_rank ascending (rank 1 = lowest mean)
    comp_order = sorted(per_tool.keys(), key=lambda t: per_tool[t]['mean_rank'])
    comp_rank = {t: i + 1 for i, t in enumerate(comp_order)}

    # Panel weighted-mean rank (existing pipeline)
    panel_means = panel_weighted_mean(blind_dir, blind_map)
    panel_order = sorted(panel_means.keys(), key=lambda t: -panel_means[t])
    panel_rank = {t: i + 1 for i, t in enumerate(panel_order)}

    # Restrict to tools present in BOTH (comparative may not cover all 8 tools yet during pilot)
    common = [t for t in comp_order if t in panel_rank]
    rho = spearman_rho([panel_rank[t] for t in common], [comp_rank[t] for t in common])

    # Flag tools with rank disagreement ≥ 2
    flags = []
    for t in common:
        delta = panel_rank[t] - comp_rank[t]
        if abs(delta) >= 2:
            flags.append({
                'tool': t,
                'panel_rank': panel_rank[t],
                'comparative_rank': comp_rank[t],
                'delta': delta,
                'panel_weighted_mean': panel_means[t],
                'comparative_mean_rank': per_tool[t]['mean_rank'],
            })

    return {
        'task': task,
        'lane': lane,
        'lane_display_name': LANES[lane]['display_name'],
        'cells_processed': len(cells_seen),
        'cells': cells_seen,
        'tools_covered': sorted(per_tool.keys()),
        'tools_in_panel': sorted(panel_rank.keys()),
        'tools_common': common,
        'per_tool': per_tool,
        'panel_weighted_means': panel_means,
        'comparative_rank': comp_rank,
        'panel_rank': panel_rank,
        'spearman_rho': rho,
        'rank_disagreement_flags': flags,
        'blinding_warnings': blinding_warnings,
    }


def render_markdown(agg: dict) -> str:
    lane_label = agg.get('lane_display_name') or LANES.get(agg.get('lane', 'opus1m'), {}).get('display_name', 'Opus-1M')
    if 'error' in agg:
        return f"## Comparative-rank ({lane_label}) — {agg['task']}\n\n_{agg['error']}_\n"
    lines = []
    task = agg['task']
    lines.append(f"## Comparative-rank ({lane_label}) — {task}")
    lines.append("")
    rho = agg['spearman_rho']
    rho_s = f"{rho:.3f}" if rho == rho else "—"  # NaN check
    n_cells = sum(1 for c in agg['cells'] if c.get('ok'))
    lines.append(f"**Spearman ρ vs panel weighted-mean rank: {rho_s}** (n_cells = {n_cells} comparative-judge runs)")
    lines.append("")
    lines.append(f"Comparative judge is a **parallel signal** — does not enter the weighted mean. Reports the same tools' rank under a different judgment regime (single {lane_label} call comparing all 8 implementations side-by-side, vs the panel's per-artifact absolute scoring). High ρ means the two regimes agree on tool ordering; low ρ would flag a calibration disagreement worth investigating.")
    lines.append("")
    if agg['blinding_warnings']:
        lines.append(f"**[!] Blinding concerns surfaced by {lane_label}** (rounds where the judge flagged identifiable fingerprints — treat as soft warnings):")
        lines.append("")
        for w in agg['blinding_warnings']:
            lines.append(f"- t{w['trial']}/round{w['round']}: {w['concern'][:200]}")
        lines.append("")

    lines.append("### Rank comparison")
    lines.append("")
    lines.append("| Tool | Panel rank | Comparative rank | Δ | Panel weighted-mean | Comparative mean-rank ± σ | n obs |")
    lines.append("|---|---|---|---|---|---|---|")
    common = agg['tools_common']
    for tool in sorted(common, key=lambda t: agg['comparative_rank'][t]):
        pr = agg['panel_rank'][tool]
        cr = agg['comparative_rank'][tool]
        delta = pr - cr
        delta_s = f"{'+' if delta > 0 else ''}{delta}" if delta else "0"
        flag = " ⚠" if abs(delta) >= 2 else ""
        pt = agg['per_tool'][tool]
        lines.append(
            f"| {tool} | {pr} | **{cr}** | {delta_s}{flag} | "
            f"{agg['panel_weighted_means'][tool]:.2f} | "
            f"{pt['mean_rank']:.2f} ± {pt['stdev_rank']:.2f} | "
            f"{pt['n_observations']} |"
        )
    lines.append("")
    lines.append("`Δ = panel_rank − comparative_rank`. Positive Δ means comparative ranks the tool higher than the panel; ⚠ marks |Δ| ≥ 2.")
    lines.append("")
    if agg['rank_disagreement_flags']:
        lines.append("**Tools with rank disagreement ≥ 2 (worth investigating):**")
        lines.append("")
        for f in agg['rank_disagreement_flags']:
            lines.append(f"- `{f['tool']}`: panel rank {f['panel_rank']} vs comparative rank {f['comparative_rank']} (Δ {'+' if f['delta'] > 0 else ''}{f['delta']})")
        lines.append("")
    not_in_comp = sorted(set(agg['tools_in_panel']) - set(common))
    if not_in_comp:
        lines.append(f"_Tools in panel but not yet judged comparatively: {', '.join(not_in_comp)}_")
        lines.append("")
    return '\n'.join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--task', help='single task to aggregate (feature|bugfix|refactor). Default: all 3')
    ap.add_argument('--results-root', default='results', help='results directory (default: ./results)')
    ap.add_argument('--lane', default='opus1m', choices=sorted(LANES.keys()),
                    help='comparative lane to aggregate (default: opus1m)')
    args = ap.parse_args()

    results_root = Path(args.results_root).resolve()
    tasks = [args.task] if args.task else ['feature', 'bugfix', 'refactor']
    lane = args.lane
    suffix = LANES[lane]['aggregate_suffix']

    for task in tasks:
        agg = aggregate_task(task, results_root, lane)
        task_dir = results_root if task == 'feature' else results_root / task
        out_dir = task_dir / '_comparative-eval'
        out_dir.mkdir(parents=True, exist_ok=True)
        json_p = out_dir / f'_aggregate{suffix}.json'
        md_p = out_dir / f'_aggregate{suffix}.md'
        json.dump(agg, open(json_p, 'w'), indent=2)
        md_p.write_text(render_markdown(agg))
        if 'error' in agg:
            print(f"{task} [{lane}]: {agg['error']}")
        else:
            rho = agg['spearman_rho']
            rho_s = f"{rho:.3f}" if rho == rho else "—"
            n_cells = sum(1 for c in agg['cells'] if c.get('ok'))
            print(f"{task} [{lane}]: ρ={rho_s}  n_cells={n_cells}  flags={len(agg['rank_disagreement_flags'])}  → {md_p}")


if __name__ == '__main__':
    main()
