#!/usr/bin/env python3
"""
Krippendorff's α — inter-rater reliability across the v2 5-judge panel.

Raters : opus, grok420, glm51, gpt54pro, mimo25pro
Tasks  : feature, bugfix, refactor
Units  : per-item (label × rubric_item) and totals (label)
Level  : interval (0-10 rubric is numeric)

Canonical score rule: sum(scores.values()) per judge file — matches
scripts/cross-task-analysis.py and scripts/aggregate-results.sh.
Round filter: ^round[0-9]+$ (pilot/sample dirs excluded).

Thresholds (Krippendorff / Landis & Koch):
  α ≥ 0.80  EXCELLENT
  α ≥ 0.667 ACCEPTABLE — tentative conclusions OK
  α ≥ 0.61  SUBSTANTIAL
  α ≥ 0.40  MODERATE — do not publish as consensus
  α < 0.40  POOR
"""

import itertools, json, os, re, sys
from collections import defaultdict

import krippendorff
import numpy as np

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TASKS = ('feature', 'bugfix', 'refactor')
JUDGES = ('opus', 'grok420', 'glm51', 'gpt54pro', 'mimo25pro')
ITEMS = [str(i) for i in range(1, 21)]
ROUND_RE = re.compile(r'^round[0-9]+$')


def eval_dir_for(task):
    return (os.path.join(REPO, 'results', '_blind-eval') if task == 'feature'
            else os.path.join(REPO, 'results', task, '_blind-eval'))


def load_mapping(task):
    with open(os.path.join(eval_dir_for(task), '.mapping-DO-NOT-OPEN.json')) as f:
        return json.load(f)['mapping']


def rounds_for(task, label):
    d = os.path.join(eval_dir_for(task), label)
    if not os.path.isdir(d):
        return []
    return sorted(int(x.replace('round', '')) for x in os.listdir(d)
                  if os.path.isdir(os.path.join(d, x)) and ROUND_RE.match(x))


def load_scores(task, label, rnd, judge):
    """Return (scores_dict, total) where total = sum(scores.values()). None if missing."""
    p = os.path.join(eval_dir_for(task), label, f'round{rnd}', f'{judge}-judge.json')
    if not os.path.isfile(p) or os.path.getsize(p) == 0:
        return None
    try:
        with open(p) as f:
            d = json.load(f)
    except Exception:
        return None
    scores = d.get('scores')
    if not isinstance(scores, dict) or not scores:
        ph = d.get('phase2') or {}
        scores = ph.get('scores')
    if not isinstance(scores, dict) or not scores:
        return None
    return scores, float(sum(scores.values()))


def per_item_matrix(task, labels):
    """3 × (labels × items) of judge-mean item scores."""
    rows = {j: [] for j in JUDGES}
    for label in labels:
        rnds = rounds_for(task, label)
        for item in ITEMS:
            for judge in JUDGES:
                vals = []
                for r in rnds:
                    d = load_scores(task, label, r, judge)
                    if d and item in d[0]:
                        vals.append(d[0][item])
                rows[judge].append(float(np.mean(vals)) if vals else np.nan)
    return np.array([rows[j] for j in JUDGES])


def total_matrix(task, labels):
    """3 × labels of judge-mean totals (sum of rubric items)."""
    rows = {j: [] for j in JUDGES}
    for label in labels:
        rnds = rounds_for(task, label)
        for judge in JUDGES:
            vals = []
            for r in rnds:
                d = load_scores(task, label, r, judge)
                if d:
                    vals.append(d[1])
            rows[judge].append(float(np.mean(vals)) if vals else np.nan)
    return np.array([rows[j] for j in JUDGES])


def verdict(a):
    if a >= 0.80: return 'EXCELLENT'
    if a >= 0.667: return 'ACCEPTABLE'
    if a >= 0.61: return 'SUBSTANTIAL'
    if a >= 0.40: return 'MODERATE'
    if a >= 0.20: return 'POOR'
    return 'FAIL (worse than chance)'


def safe_alpha(mat):
    try:
        return krippendorff.alpha(reliability_data=mat, level_of_measurement='interval')
    except Exception as e:
        return float('nan')


def main():
    results = {}
    for task in TASKS:
        mapping = load_mapping(task)
        labels = sorted(mapping.keys())
        m_items = per_item_matrix(task, labels)
        m_tot = total_matrix(task, labels)
        a_items = safe_alpha(m_items)
        a_tot = safe_alpha(m_tot)

        pairwise = {}
        for a, b in itertools.combinations(JUDGES, 2):
            ra, rb = [], []
            for label in labels:
                rnds = rounds_for(task, label)
                va = [load_scores(task, label, r, a)[1] for r in rnds
                      if load_scores(task, label, r, a)]
                vb = [load_scores(task, label, r, b)[1] for r in rnds
                      if load_scores(task, label, r, b)]
                if va and vb:
                    ra.append(float(np.mean(va)))
                    rb.append(float(np.mean(vb)))
            pair_mat = np.array([ra, rb])
            pairwise[f'{a}_{b}'] = {
                'alpha': safe_alpha(pair_mat),
                'n': pair_mat.shape[1],
            }

        results[task] = {
            'n_labels': len(labels),
            'n_units_item': int(m_items.shape[1]),
            'alpha_item_interval': a_items,
            'alpha_total_interval': a_tot,
            'pairwise_total': pairwise,
        }

    # ── Report ──
    print(f'Krippendorff α — {len(JUDGES)}-judge panel ({" / ".join(JUDGES)})\n')
    print('Canonical score rule: sum(scores.values()); round filter: ^round[0-9]+$\n')
    print(f'{"Task":<10} {"n_lbl":>6} {"α item":>8} {"α total":>9}  verdict(total)')
    print('-' * 60)
    for task in TASKS:
        r = results[task]
        print(f'{task:<10} {r["n_labels"]:>6d} '
              f'{r["alpha_item_interval"]:>+8.3f} {r["alpha_total_interval"]:>+9.3f}  '
              f'{verdict(r["alpha_total_interval"])}')
    print()
    pairs = list(itertools.combinations(JUDGES, 2))
    print('Pairwise α on judge-mean totals (label-level):\n')
    header = f'{"Task":<10}' + ''.join(f'  {a[:4]}×{b[:4]:<6}'[:14].rjust(14) for a, b in pairs) + '   n'
    print(header)
    print('-' * len(header))
    for task in TASKS:
        p = results[task]['pairwise_total']
        n_any = next(iter(p.values()))['n']
        cells = ''.join(f' {p[f"{a}_{b}"]["alpha"]:>+12.3f}' for a, b in pairs)
        print(f'{task:<10}{cells}  {n_any}')

    out = os.path.join(REPO, 'results', 'krippendorff-alpha.json')
    with open(out, 'w') as f:
        json.dump(results, f, indent=2, default=str)
    print(f'\nWrote {out}')


if __name__ == '__main__':
    main()
