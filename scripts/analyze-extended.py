#!/usr/bin/env python3
"""
Extended analysis for AI Tool Benchmark — TD-CD Mode 2 CD Batch
Prints all 8 analysis sections. Run from repo root or any directory.

Sections:
  1. Per-item score matrix (rubric items 1-20)
  2. Diff-leak audit (blind-eval integrity check)
  3. Bootstrap 95% CI on tool means (n=10000, seed=42)
  4. Formal tier cutoff via non-overlapping CIs
  5. Minimum Detectable Effect (MDE)
  6. Spearman rank correlation (opus vs gpt54pro — vendor-distinct pair)
  7. Median aggregation vs mean aggregation
  8. Diff-size bias: LOC vs score Spearman rho
"""

import json, os, re, random, math
from collections import defaultdict

# --- QUARANTINED 2026-05-18 (AUDIT-FINDINGS-2026-05-18-JUDGE-VALIDITY.md) ---
# HIGH: §5 MDE uses a one-sample 1/√n form on n≈75 *correlated* judgments
# (textbook pseudoreplication; SE understated ≈√30×), and the round loop
# reads round{1..5}/ dirs that do not exist (actual: root + round1 + round2).
# Sections 3-4 (bootstrap CI / tier cutoff) inherit the same flat-75 pool.
# Use scripts/bootstrap-sensitivity.py (trial-clustered) instead. Output of
# this script must NOT be cited. Re-enable only after trial-clustering.
import sys as _sys
_sys.stderr.write(
    "analyze-extended.py is QUARANTINED (pseudoreplicated MDE/CI + wrong round set). "
    "See AUDIT-FINDINGS-2026-05-18-JUDGE-VALIDITY.md.\n"
)
_sys.exit(2)

random.seed(42)

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'results', '_blind-eval')
BASE = os.path.normpath(BASE)

TOOLS = ['superpower', 'bmad', 'gstack', 'pure', 'omc', 'ecc', 'compound', 'claudekit']
JUDGES = ('opus', 'grok420', 'glm51', 'gpt54pro', 'mimo25pro')

LEAK_STRINGS = [
    '.omc', '_bmad-output', '.bmad-core', 'everything-claude-code',
    'superpowers', 'claudekit', 'ck/', 'compound-engineering',
    'autoplan', '.ship', 'gstack',
]


def load_mapping():
    with open(os.path.join(BASE, '.mapping-DO-NOT-OPEN.json')) as f:
        return json.load(f)['mapping']


def load_all_scores(mapping):
    rows = []
    for label, meta in mapping.items():
        for rnd in [1, 2, 3, 4, 5]:
            for judge in JUDGES:
                path = os.path.join(BASE, label, f'round{rnd}', f'{judge}-judge.json')
                if not os.path.exists(path) or os.path.getsize(path) == 0:
                    continue
                try:
                    with open(path) as f:
                        d = json.load(f)
                except Exception:
                    continue
                scores = d.get('scores')
                if not isinstance(scores, dict) or not scores:
                    continue
                total = sum(scores.values())
                rows.append({
                    'label': label,
                    'tool': meta['tool'],
                    'trial': meta['trial'],
                    'round': rnd,
                    'judge': judge,
                    'total': total,
                    'scores': {str(k): v for k, v in scores.items()},
                })
    return rows


def parse_loc(label):
    stats = os.path.join(BASE, label, 'diff-stats.txt')
    if os.path.exists(stats):
        with open(stats) as f:
            content = f.read()
        m = re.search(r'(\d+) insertion', content)
        return int(m.group(1)) if m else 0
    patch = os.path.join(BASE, label, 'implementation-diff.patch')
    if os.path.exists(patch):
        with open(patch) as f:
            lines = f.readlines()
        return sum(1 for l in lines if l.startswith('+') and not l.startswith('+++'))
    return 0


def pearson(xs, ys):
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    num = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    den = math.sqrt(sum((x - mx) ** 2 for x in xs) * sum((y - my) ** 2 for y in ys))
    return num / den if den else 0.0


def spearman(xs, ys):
    def rank(arr):
        s = sorted(enumerate(arr), key=lambda x: x[1])
        r = [0] * len(arr)
        for rv, (idx, _) in enumerate(s, 1):
            r[idx] = rv
        return r
    return pearson(rank(xs), rank(ys))


def median(arr):
    s = sorted(arr)
    n = len(s)
    return (s[n // 2 - 1] + s[n // 2]) / 2 if n % 2 == 0 else s[n // 2]


def section(title):
    print(f'\n{"=" * 70}')
    print(f'  {title}')
    print('=' * 70)


def main():
    mapping = load_mapping()
    data = load_all_scores(mapping)

    tool_scores = {t: [r['total'] for r in data if r['tool'] == t] for t in TOOLS}

    # ── 1. Per-item score matrix ──────────────────────────────────────────────
    section('1. Per-item score matrix (items 1-20, mean across 24 samples)')
    items = [str(i) for i in range(1, 21)]
    tool_item = {}
    for tool in TOOLS:
        recs = [r for r in data if r['tool'] == tool]
        tool_item[tool] = {}
        for item in items:
            vals = [r['scores'][item] for r in recs if item in r['scores']]
            tool_item[tool][item] = sum(vals) / len(vals) if vals else 0.0

    item_var = {}
    for item in items:
        vals = [tool_item[t][item] for t in TOOLS]
        mu = sum(vals) / len(vals)
        item_var[item] = sum((v - mu) ** 2 for v in vals) / len(vals)

    sorted_by_var = sorted(items, key=lambda i: item_var[i], reverse=True)
    top3_diff = sorted_by_var[:3]
    shared_str = [i for i in items if min(tool_item[t][i] for t in TOOLS) >= 8]
    shared_weak = [i for i in items if max(tool_item[t][i] for t in TOOLS) <= 4]

    header = f"{'Tool':<14}" + ''.join(f'  I{int(i):02d}' for i in items)
    print(header)
    print('-' * len(header))
    for tool in TOOLS:
        row = f'{tool:<14}' + ''.join(f'{tool_item[tool][i]:5.1f}' for i in items)
        print(row)

    print(f'\nTop 3 differentiators (highest cross-tool variance): items {top3_diff}')
    print(f'Shared strengths (all tools avg >= 8): items {shared_str if shared_str else "none"}')
    print(f'Shared weaknesses (all tools avg <= 4): items {shared_weak}')

    # ── 2. Diff-leak audit ───────────────────────────────────────────────────
    section('2. Diff-leak audit (36 implementation-diff.patch files)')
    leaks = {}
    for label in mapping:
        patch = os.path.join(BASE, label, 'implementation-diff.patch')
        if not os.path.exists(patch):
            print(f'  MISSING patch: {label}')
            continue
        with open(patch) as f:
            content = f.read()
        found = [s for s in LEAK_STRINGS if s in content]
        if found:
            leaks[label] = found
            print(f'  LEAK {label} ({mapping[label]["tool"]}-T{mapping[label]["trial"]}): {found}')
    if not leaks:
        print('  CLEAN — no tool-identifying strings in any of 36 diffs')

    # ── 3. Bootstrap 95% CI ──────────────────────────────────────────────────
    section('3. Bootstrap 95% CI (10,000 resamples, seed=42)')
    boot = {}
    for tool in TOOLS:
        scores = tool_scores[tool]
        n = len(scores)
        means = sorted(sum(random.choice(scores) for _ in range(n)) / n for _ in range(10000))
        lo, hi = means[249], means[9749]
        boot[tool] = {'mean': sum(scores) / n, 'lo': lo, 'hi': hi, 'width': hi - lo}

    print(f"{'Tool':<14} {'Mean':>7} {'Lo 2.5%':>9} {'Hi 97.5%':>10} {'CI Width':>9}")
    print('-' * 52)
    for tool in TOOLS:
        r = boot[tool]
        print(f"{tool:<14} {r['mean']:7.3f} {r['lo']:9.3f} {r['hi']:10.3f} {r['width']:9.3f}")

    # ── 4. Formal tier cutoff ────────────────────────────────────────────────
    section('4. Formal tier cutoff (non-overlapping bootstrap CIs)')
    ranked = sorted(TOOLS, key=lambda t: boot[t]['mean'], reverse=True)
    tiers = []
    current = [ranked[0]]
    for i in range(1, len(ranked)):
        prev, curr = ranked[i - 1], ranked[i]
        if boot[prev]['lo'] > boot[curr]['hi']:
            tiers.append(current[:])
            current = [curr]
        else:
            current.append(curr)
    tiers.append(current)

    for i, tier in enumerate(tiers, 1):
        entries = ', '.join(f"{t}({boot[t]['mean']:.2f})" for t in tier)
        print(f'  Tier {i}: {entries}')
    structure = '/'.join(str(len(t)) for t in tiers)
    print(f'\n  Formal structure: {structure}  (eyeballed: 4/4/1)')

    # ── 5. MDE ───────────────────────────────────────────────────────────────
    section('5. Minimum Detectable Effect (alpha=0.05, power=0.80)')
    pooled_var = sum(
        sum((s - sum(tool_scores[t]) / len(tool_scores[t])) ** 2 for s in tool_scores[t])
        for t in TOOLS
    )
    n_obs = sum(len(tool_scores[t]) for t in TOOLS)
    pooled_sd = math.sqrt(pooled_var / (n_obs - len(TOOLS)))
    n_per = len(tool_scores[TOOLS[0]])
    mde = 2.8 * pooled_sd / math.sqrt(n_per)
    top_spread = boot['superpower']['mean'] - boot['pure']['mean']
    print(f'  Pooled within-tool SD : {pooled_sd:.3f}')
    print(f'  n per group           : {n_per}')
    print(f'  MDE                   : {mde:.3f} points')
    print(f'  Top-cluster spread    : {top_spread:.3f} points (superpower - pure)')
    verdict = 'NOT reliably detectable' if mde >= top_spread else 'detectable'
    print(f'  MDE {"<" if mde < top_spread else ">="} top-cluster spread => differences are {verdict}')

    # ── 6. Spearman rank correlation ─────────────────────────────────────────
    pair = ('opus', 'gpt54pro')  # vendor-distinct pair: Anthropic vs OpenAI
    section(f'6. Spearman rank correlation: {pair[0]} vs {pair[1]} (paired rounds each tool)')
    print(f"{'Tool':<14} {'Pearson r':>10} {'Spearman rho':>13} {'|rho-r|':>9} {'n':>4} {'Flag':>6}")
    print('-' * 60)
    for tool in TOOLS:
        pairs = defaultdict(dict)
        for r in data:
            if r['tool'] == tool:
                pairs[(r['label'], r['round'])][r['judge']] = r['total']
        a_s = [v[pair[0]] for v in pairs.values() if pair[0] in v and pair[1] in v]
        b_s = [v[pair[1]] for v in pairs.values() if pair[0] in v and pair[1] in v]
        if len(a_s) < 3:
            print(f'{tool:<14} {"n/a":>10} {"n/a":>13} {"":>9} {len(a_s):>4} {"":>6}')
            continue
        r_val = pearson(a_s, b_s)
        rho = spearman(a_s, b_s)
        diff = abs(rho - r_val)
        flag = 'FLAG' if diff > 0.2 else ''
        print(f'{tool:<14} {r_val:10.3f} {rho:13.3f} {diff:9.3f} {len(a_s):>4} {flag:>6}')

    # ── 7. Median aggregation ────────────────────────────────────────────────
    section('7. Median vs mean aggregation')
    mean_rank = {t: i + 1 for i, t in enumerate(
        sorted(TOOLS, key=lambda t: sum(tool_scores[t]) / len(tool_scores[TOOLS[0]]), reverse=True))}
    median_rank = {t: i + 1 for i, t in enumerate(
        sorted(TOOLS, key=lambda t: median(tool_scores[t]), reverse=True))}

    print(f"{'Tool':<14} {'Mean':>7} {'MnRk':>6} {'Median':>8} {'MdRk':>6} {'DeltaRk':>9}")
    print('-' * 56)
    for tool in sorted(TOOLS, key=lambda t: mean_rank[t]):
        m = sum(tool_scores[tool]) / len(tool_scores[TOOLS[0]])
        med = median(tool_scores[tool])
        delta = median_rank[tool] - mean_rank[tool]
        sign = '+' if delta > 0 else ''
        print(f'{tool:<14} {m:7.2f} {mean_rank[tool]:6d} {med:8.1f} {median_rank[tool]:6d} {sign}{delta:8d}')

    # ── 8. Diff-size bias: LOC vs score ──────────────────────────────────────
    section('8. Diff-size bias: Spearman rho (LOC vs mean score, 36 labels)')
    locs, scores_by_label = [], []
    label_details = []
    for label in mapping:
        loc = parse_loc(label)
        label_rows = [r for r in data if r['label'] == label]
        ms = sum(r['total'] for r in label_rows) / len(label_rows) if label_rows else 0
        locs.append(loc)
        scores_by_label.append(ms)
        label_details.append((label, mapping[label]['tool'], mapping[label]['trial'], loc, ms))

    rho_loc = spearman(locs, scores_by_label)
    print(f'  Spearman rho (LOC vs mean score): {rho_loc:.3f}')
    print(f'  Interpretation: {"positive correlation — larger diffs score higher" if rho_loc > 0 else "negative / no correlation"}')

    print(f'\n  {"Label":<12} {"Tool":<12} {"Trial":>5} {"LOC":>6} {"Score":>8}')
    print('  ' + '-' * 48)
    for label, tool, trial, loc, score in sorted(label_details, key=lambda x: x[3], reverse=True):
        print(f'  {label:<12} {tool:<12} T{trial:>1}  {loc:6d} {score:8.1f}')


if __name__ == '__main__':
    main()
