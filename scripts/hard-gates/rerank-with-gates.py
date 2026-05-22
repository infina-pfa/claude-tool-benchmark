#!/usr/bin/env python3
"""
Apply tier caps based on hard-gate compliance, re-compute per-tool means,
and compare to the current (un-capped) ranking.

Tier rule (on a 6-gate scale where P=1, U=0.5, F=0):
  Tier A (≥4.0 / 6): cap at 115
  Tier B (2.5–3.99): cap at 105
  Tier C (<2.5):     cap at 95

Cap is applied per trial's mean score (not per round), then tool mean is
recomputed across the 4 trials.
"""
import json
import statistics
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
TOOLS = ['pure', 'superpower', 'claudekit', 'bmad', 'gstack', 'compound', 'ecc', 'omc']
GATE_VAL = {'PASS': 1.0, 'UNDETERMINED': 0.5, 'FAIL': 0.0}


def load_mapping() -> dict:
    m = json.loads((REPO / 'results/_blind-eval/.mapping-DO-NOT-OPEN.json').read_text())
    # Each entry: label → {tool, trial}
    return m.get('mapping', m)


JUDGES = ('opus', 'grok420', 'glm51', 'gpt54pro', 'mimo25pro')


def label_scores(label: str) -> list[float]:
    """Return all round×judge scores for a given label (rounds × {len(JUDGES)} judges)."""
    scores = []
    base = REPO / 'results/_blind-eval' / label
    if not base.exists():
        return scores
    for r in (1, 2, 3):
        rdir = base / f'round{r}'
        if not rdir.exists():
            continue
        for judge in JUDGES:
            jpath = rdir / f'{judge}-judge.json'
            if not jpath.exists():
                continue
            try:
                d = json.loads(jpath.read_text())
                if 'total' in d:
                    scores.append(d['total'])
                elif 'scores' in d:
                    scores.append(sum(d['scores'].values()))
            except Exception:
                pass
    return scores


def gate_score(tool: str, trial: int) -> float:
    gpath = REPO / f'results/{tool}/t{trial}/hard-gates.json'
    if not gpath.exists():
        return 0.0
    d = json.loads(gpath.read_text())
    gates = d.get('gates', {})
    return sum(GATE_VAL.get(v, 0) for v in gates.values())


def tier_cap(gscore: float) -> int:
    if gscore >= 4.0:
        return 115
    if gscore >= 2.5:
        return 105
    return 95


def main():
    mapping = load_mapping()
    # Invert: (tool, trial) -> label
    inv = {(v['tool'], v['trial']): k for k, v in mapping.items() if isinstance(v, dict) and 'tool' in v}

    rows = []
    for tool in TOOLS:
        trial_rows = []
        for trial in (1, 2, 3, 4):
            label = inv.get((tool, trial))
            if not label:
                continue
            raw_scores = label_scores(label)
            if not raw_scores:
                continue
            raw_mean = statistics.mean(raw_scores)
            gs = gate_score(tool, trial)
            cap = tier_cap(gs)
            capped_mean = min(raw_mean, cap)
            trial_rows.append({
                'trial': trial, 'label': label,
                'raw_mean': raw_mean, 'gate_score': gs,
                'cap': cap, 'capped_mean': capped_mean,
            })
        if trial_rows:
            rows.append({
                'tool': tool,
                'trials': trial_rows,
                'raw_tool_mean': statistics.mean(r['raw_mean'] for r in trial_rows),
                'capped_tool_mean': statistics.mean(r['capped_mean'] for r in trial_rows),
                'mean_gates_passed': statistics.mean(r['gate_score'] for r in trial_rows),
            })

    # Print ranking comparison
    print(f"\n{'Tool':<12} {'Raw':>7} {'Capped':>8} {'Δ':>7} {'Gates/6':>8}")
    print('-' * 50)

    by_raw = sorted(rows, key=lambda r: -r['raw_tool_mean'])
    by_cap = sorted(rows, key=lambda r: -r['capped_tool_mean'])
    cap_rank = {r['tool']: i + 1 for i, r in enumerate(by_cap)}

    for i, r in enumerate(by_raw, 1):
        delta = r['capped_tool_mean'] - r['raw_tool_mean']
        arrow = ''
        if cap_rank[r['tool']] != i:
            diff = cap_rank[r['tool']] - i
            arrow = f"  ({'↓' if diff > 0 else '↑'}{abs(diff)})"
        print(f"{r['tool']:<12} {r['raw_tool_mean']:>7.2f} {r['capped_tool_mean']:>8.2f} "
              f"{delta:>+7.2f} {r['mean_gates_passed']:>8.2f}{arrow}")

    print(f"\nCapped ranking:")
    for i, r in enumerate(by_cap, 1):
        print(f"  {i}. {r['tool']}: {r['capped_tool_mean']:.2f}")

    # Per-trial cap incidence
    cap_counts = {115: 0, 105: 0, 95: 0}
    for r in rows:
        for t in r['trials']:
            cap_counts[t['cap']] += 1
    print(f"\nTier incidence across {sum(cap_counts.values())} trials:")
    for cap, n in sorted(cap_counts.items(), reverse=True):
        tier = {115: 'A', 105: 'B', 95: 'C'}[cap]
        print(f"  Tier {tier} (cap {cap}): {n} trials")

    out = {
        'tools': rows,
        'by_raw': [(r['tool'], r['raw_tool_mean']) for r in by_raw],
        'by_capped': [(r['tool'], r['capped_tool_mean']) for r in by_cap],
        'tier_rule': 'A≥4.0/6 cap115, B≥2.5 cap105, C<2.5 cap95',
    }
    (REPO / 'results/hard-gates-rerank.json').write_text(json.dumps(out, indent=2, default=float) + '\n')
    print(f"\nSaved: results/hard-gates-rerank.json")


if __name__ == '__main__':
    main()
