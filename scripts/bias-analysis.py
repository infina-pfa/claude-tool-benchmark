#!/usr/bin/env python3
"""
Self-preference bias analysis — v2 5-judge panel.

All 9 candidate tools ran on claude-opus-4-6. opus-4-7 is one of 5 judges.
Zheng 2023 quantifies same-family bias at +0.8±0.3 on a 10-pt scale
(~+16 pts on the 200-pt rubric) — potentially exceeding the ~9.5-pt MDE.

This script computes:
  1. per-tool mean by judge (opus vs each non-Anthropic judge)
  2. opus-vs-others delta per tool (others = non-opus pool)
  3. Reference delta as control (human-authored, non-Claude origin)
  4. bias-corrected ranking (subtract mean opus-bias)
"""

import json, os
from collections import defaultdict

# --- QUARANTINED 2026-05-18 (AUDIT-FINDINGS-2026-05-18-JUDGE-VALIDITY.md) ---
# CRITICAL: this script (a) appends d['total'] — the forbidden drift-prone
# field the canonical pipeline explicitly bans (use sum(scores.values())),
# and (b) iterates ROUNDS=[1..5] reading round{n}/ dirs that do not exist
# (actual layout is root + round1 + round2), so it silently computes on a
# non-canonical, partial sample. Its output must NOT be cited. Re-enable only
# after porting to sum_scores() and the canonical root+roundN union.
import sys as _sys
_sys.stderr.write(
    "bias-analysis.py is QUARANTINED (forbidden `total` field + wrong round set). "
    "See AUDIT-FINDINGS-2026-05-18-JUDGE-VALIDITY.md.\n"
)
_sys.exit(2)


BASE = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                     '..', 'results', '_blind-eval'))
TOOLS = ['superpower', 'bmad', 'gstack', 'pure', 'omc',
         'ecc', 'compound', 'claudekit']
JUDGES = ['opus', 'grok420', 'glm51', 'gpt54pro', 'mimo25pro']
OTHERS = [j for j in JUDGES if j != 'opus']
ROUNDS = [1, 2, 3, 4, 5]


def load_mapping():
    with open(os.path.join(BASE, '.mapping-DO-NOT-OPEN.json')) as f:
        return json.load(f)['mapping']


def load(label, rnd, judge):
    path = os.path.join(BASE, label, f'round{rnd}', f'{judge}-judge.json')
    if not os.path.exists(path):
        return None
    with open(path) as f:
        return json.load(f)


def mean(xs):
    return sum(xs) / len(xs) if xs else 0.0


def collect_tool_scores(mapping):
    """→ {tool: {judge: [totals...]}}"""
    out = {t: {j: [] for j in JUDGES} for t in TOOLS}
    for label, meta in mapping.items():
        tool = meta['tool']
        if tool not in out:
            continue
        for rnd in ROUNDS:
            for judge in JUDGES:
                d = load(label, rnd, judge)
                if d:
                    out[tool][judge].append(d['total'])
    return out


def collect_reference_scores():
    out = {j: [] for j in JUDGES}
    for rnd in ROUNDS:
        for judge in JUDGES:
            d = load('Reference', rnd, judge)
            if d:
                out[judge].append(d['total'])
    return out


def section(title):
    print(f'\n{"=" * 72}')
    print(f'  {title}')
    print('=' * 72)


def main():
    mapping = load_mapping()
    tool_j = collect_tool_scores(mapping)
    ref_j = collect_reference_scores()

    # ── 1. Per-tool mean by judge ────────────────────────────────────────────
    section(f'1. Per-tool mean score by judge ({len(JUDGES)} judges)')
    judge_cols = ''.join(f' {j[:8]:>8}' for j in JUDGES)
    print(f'{"Tool":<12}{judge_cols} {"Opus-Others":>14}  n_per_judge')
    print('-' * 80)
    biases = {}
    for tool in TOOLS:
        means_by_j = {j: mean(tool_j[tool][j]) for j in JUDGES}
        others_pool = [s for j in OTHERS for s in tool_j[tool][j]]
        delta = means_by_j['opus'] - mean(others_pool)
        biases[tool] = delta
        ns = '/'.join(str(len(tool_j[tool][j])) for j in JUDGES)
        cells = ''.join(f' {means_by_j[j]:8.2f}' for j in JUDGES)
        print(f'{tool:<12}{cells} {delta:+14.2f}  {ns}')

    # Reference control
    ref_means = {j: mean(ref_j[j]) for j in JUDGES}
    ref_others_pool = [s for j in OTHERS for s in ref_j[j]]
    r_delta = ref_means['opus'] - mean(ref_others_pool)
    ref_ns = '/'.join(str(len(ref_j[j])) for j in JUDGES)
    print('-' * 80)
    ref_cells = ''.join(f' {ref_means[j]:8.2f}' for j in JUDGES)
    print(f'{"Reference":<12}{ref_cells} {r_delta:+14.2f}  {ref_ns}')

    # ── 2. Bias summary ──────────────────────────────────────────────────────
    section('2. Self-preference bias summary (opus - others)')
    mean_bias = mean(list(biases.values()))
    bias_sd = (sum((b - mean_bias) ** 2 for b in biases.values())
               / len(biases)) ** 0.5
    print(f'  Mean cohort bias (opus > others)     : {mean_bias:+.2f} pts')
    print(f'  SD across tools                      : {bias_sd:.2f} pts')
    print(f'  Reference bias (human-authored, ctrl): {r_delta:+.2f} pts')
    print(f'  Zheng 2023 expected on 200-pt scale  : +16 ± 6 pts')
    print(f'  Current MDE                          : ~9.5 pts')

    verdict = ('REAL BIAS — exceeds MDE, cohort ranking is NOT defensible'
               if abs(mean_bias) > 9.5 else
               'BORDERLINE — comparable to MDE; treat cohort ordering cautiously'
               if abs(mean_bias) > 5 else
               'NEGLIGIBLE — cohort ordering unaffected by judge-family')
    print(f'  Verdict: {verdict}')

    if abs(mean_bias) > abs(r_delta) + 5:
        print(f'  Control signal: cohort bias ({mean_bias:+.1f}) '
              f'exceeds Reference bias ({r_delta:+.1f}) by '
              f'{mean_bias - r_delta:+.1f} — evidence of same-family preference.')
    else:
        print(f'  Control signal: cohort bias ({mean_bias:+.1f}) ≈ '
              f'Reference bias ({r_delta:+.1f}) — likely judge idiosyncrasy, '
              f'not same-family bias.')

    # ── 3. Rankings: raw vs bias-corrected ───────────────────────────────────
    section('3. Ranking — raw mean vs bias-corrected (subtract mean cohort bias)')
    raw = {t: mean([s for j in JUDGES for s in tool_j[t][j]]) for t in TOOLS}
    # Correction: subtract per-tool bias weighted by opus fraction
    corrected = {}
    for t in TOOLS:
        opus_w = len(tool_j[t]['opus'])
        total_w = sum(len(tool_j[t][j]) for j in JUDGES)
        frac = opus_w / total_w if total_w else 0
        corrected[t] = raw[t] - biases[t] * frac

    raw_rank = sorted(TOOLS, key=lambda t: raw[t], reverse=True)
    cor_rank = sorted(TOOLS, key=lambda t: corrected[t], reverse=True)
    raw_idx = {t: i + 1 for i, t in enumerate(raw_rank)}
    cor_idx = {t: i + 1 for i, t in enumerate(cor_rank)}

    print(f'{"Tool":<12} {"Raw":>8} {"RawRk":>6} {"Corrected":>11} '
          f'{"CorRk":>6} {"DeltaRk":>9}')
    print('-' * 58)
    for tool in raw_rank:
        d = cor_idx[tool] - raw_idx[tool]
        sign = '+' if d > 0 else ''
        print(f'{tool:<12} {raw[tool]:8.2f} {raw_idx[tool]:6d} '
              f'{corrected[tool]:11.2f} {cor_idx[tool]:6d} {sign}{d:8d}')

    moved = [t for t in TOOLS if cor_idx[t] != raw_idx[t]]
    print(f'\n  Tools whose rank shifted under correction: '
          f'{len(moved)} of {len(TOOLS)}')


if __name__ == '__main__':
    main()
