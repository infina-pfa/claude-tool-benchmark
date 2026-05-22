#!/usr/bin/env python3
"""
Trial-clustered bootstrap sensitivity analysis (addresses credibility-review #4).

The canonical bootstrap in `scripts/cross-task-analysis.py` resamples within each
judge's flat score pool, treating every (trial, round, judge) triple as an
independent draw. Rounds re-judge the same artifact, so this inflates precision.

This script re-runs the bootstrap under **trial-clustered** resampling:
- For each (tool, task) cell, resample trials (not records) with replacement.
- For each selected trial, carry all its (round, judge) scores as a block.
- The bootstrap statistic is the balanced mean (mean of per-judge means) on
  the resampled pool, matching the canonical estimator.

Output: results/bootstrap-sensitivity.json with per-(tool, task) clustered and
unclustered mean/CI, plus the superpower-bugfix discriminating pair up front.
"""

import json
import os
import random
import statistics
from collections import defaultdict

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TASKS = ('feature', 'bugfix', 'refactor')
JUDGES = ('opus', 'grok420', 'glm51', 'gpt54pro', 'mimo25pro')
N_BOOT = 10000

import re
ROUND_RE = re.compile(r'^round[0-9]+$')

random.seed(42)


def load_task(task):
    if task == 'feature':
        eval_dir = os.path.join(REPO, 'results', '_blind-eval')
    else:
        eval_dir = os.path.join(REPO, 'results', task, '_blind-eval')
    with open(os.path.join(eval_dir, '.mapping-DO-NOT-OPEN.json')) as f:
        mapping = json.load(f)['mapping']
    records = []
    for label, info in mapping.items():
        label_dir = os.path.join(eval_dir, label)
        if not os.path.isdir(label_dir):
            continue
        rounds = sorted(d for d in os.listdir(label_dir)
                        if os.path.isdir(os.path.join(label_dir, d)) and ROUND_RE.match(d))
        for rd in rounds:
            for judge in JUDGES:
                f = os.path.join(label_dir, rd, f'{judge}-judge.json')
                if not os.path.isfile(f) or os.path.getsize(f) == 0:
                    continue
                try:
                    with open(f) as fh:
                        d = json.load(fh)
                except Exception:
                    continue
                scores = d.get('scores')
                if not isinstance(scores, dict) or not scores:
                    ph = d.get('phase2') or {}
                    scores = ph.get('scores')
                    if not isinstance(scores, dict) or not scores:
                        continue
                records.append({
                    'task': task,
                    'tool': info['tool'],
                    'trial': info['trial'],
                    'round': int(rd.replace('round', '')),
                    'judge': judge,
                    'score': float(sum(scores.values())),
                })
    return records


def balanced_mean(records):
    """Mean of per-judge means. Returns None if any judge stratum is empty."""
    per_judge = {j: [r['score'] for r in records if r['judge'] == j] for j in JUDGES}
    if any(not v for v in per_judge.values()):
        return None
    return statistics.mean(statistics.mean(per_judge[j]) for j in JUDGES)


def unclustered_ci(records, tool, n=N_BOOT, conf=0.95):
    """Within-judge stratified resample (matches the canonical estimator)."""
    cell = [r for r in records if r['tool'] == tool]
    per_judge = {j: [r['score'] for r in cell if r['judge'] == j] for j in JUDGES}
    if any(not v for v in per_judge.values()):
        return None
    boots = []
    for _ in range(n):
        jm = []
        for j in JUDGES:
            pool = per_judge[j]
            k = len(pool)
            jm.append(sum(random.choice(pool) for _ in range(k)) / k)
        boots.append(statistics.mean(jm))
    boots.sort()
    mean = balanced_mean(cell)
    lo = boots[int((1 - conf) / 2 * n)]
    hi = boots[int((1 + conf) / 2 * n) - 1]
    return {'mean': mean, 'lo': lo, 'hi': hi}


def clustered_ci(records, tool, n=N_BOOT, conf=0.95):
    """Trial-clustered resample: pick trials with replacement, carry all their
    (round, judge) scores as a block. The statistic is the balanced mean
    (mean of per-judge means) on the resampled block pool.

    If any judge stratum is empty in a bootstrap replicate (can happen if all
    chosen trials happen to be the same one and that trial is missing a judge),
    we skip that replicate and draw again. This preserves the statistic's
    definition without artificially shrinking the CI.
    """
    cell = [r for r in records if r['tool'] == tool]
    if not cell:
        return None
    by_trial = defaultdict(list)
    for r in cell:
        by_trial[r['trial']].append(r)
    trials = sorted(by_trial.keys())
    if len(trials) < 2:
        return None
    boots = []
    attempts = 0
    max_attempts = n * 10
    while len(boots) < n and attempts < max_attempts:
        attempts += 1
        picked = [random.choice(trials) for _ in range(len(trials))]
        pool = []
        for t in picked:
            pool.extend(by_trial[t])
        per_judge = {j: [r['score'] for r in pool if r['judge'] == j] for j in JUDGES}
        if any(not v for v in per_judge.values()):
            continue
        boots.append(statistics.mean(statistics.mean(per_judge[j]) for j in JUDGES))
    boots.sort()
    mean = balanced_mean(cell)
    lo = boots[int((1 - conf) / 2 * n)]
    hi = boots[int((1 + conf) / 2 * n) - 1]
    return {
        'mean': mean,
        'lo': lo,
        'hi': hi,
        'n_trials': len(trials),
        'n_replicates': len(boots),
        'rejected_replicates': attempts - len(boots),
    }


def main():
    out = {'seed': 42, 'n_boot': N_BOOT, 'tasks': {}}
    tools = None
    for task in TASKS:
        records = load_task(task)
        tools = sorted({r['tool'] for r in records})
        out['tasks'][task] = {}
        for tool in tools:
            unc = unclustered_ci(records, tool)
            clu = clustered_ci(records, tool)
            out['tasks'][task][tool] = {'unclustered': unc, 'clustered': clu}

    # Discriminating print: superpower-bugfix clustered CI vs the next-worst-tool
    # cluster above it. We print superpower + the three lowest-mean bugfix tools.
    sp = out['tasks']['bugfix']['superpower']
    print('=== Discriminating cell: superpower-bugfix ===')
    print(f"  unclustered CI: mean={sp['unclustered']['mean']:.2f} "
          f"[{sp['unclustered']['lo']:.2f}, {sp['unclustered']['hi']:.2f}]")
    print(f"    clustered CI: mean={sp['clustered']['mean']:.2f} "
          f"[{sp['clustered']['lo']:.2f}, {sp['clustered']['hi']:.2f}] "
          f"(n_trials={sp['clustered']['n_trials']})")
    print()
    print('=== All bugfix cells, sorted by mean (ascending) — for overlap check ===')
    bf = sorted(out['tasks']['bugfix'].items(), key=lambda kv: kv[1]['clustered']['mean'])
    for tool, c in bf:
        u, k = c['unclustered'], c['clustered']
        print(f"  {tool:12s} unc=[{u['lo']:6.2f},{u['hi']:6.2f}]  "
              f"clu=[{k['lo']:6.2f},{k['hi']:6.2f}]  "
              f"width_ratio={((k['hi']-k['lo'])/(u['hi']-u['lo'])):.2f}")

    path = os.path.join(REPO, 'results', 'bootstrap-sensitivity.json')
    with open(path, 'w') as f:
        json.dump(out, f, indent=2)
    print()
    print(f"Wrote {path}")


if __name__ == '__main__':
    main()
