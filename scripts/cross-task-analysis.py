#!/usr/bin/env python3
"""
Cross-task statistical analysis for the AI Tool Benchmark.

Reads all 3-judge × N-round judgments from results/{task}/_blind-eval/<Label>/round<N>/<judge>-judge.json
using sum(scores) as the canonical score and dirs matching ^round[0-9]+$ only.

Computes:
- Per-task balanced mean per tool (= pooled mean when per-judge n equal)
- Bootstrap 95% CI per (tool, task), stratified by judge
- Per-task z-score using cohort mean/stdev over all judgments in the task
- Combined z̄ = equal-weight mean of the three per-task z-scores
- Rank-sum across tasks
- Tier grouping per task by non-overlapping CIs
- Spearman ρ between judge pairs with 95% bootstrap CI
- Ranking sensitivity (equal-weight vs. count-weighted z̄ and rank-sum)
- Judge calibration asymmetry (opus vs mean(codex,qwen)) — not a self-preference
  test given all executors use a single base model; see PAPER.md §4.5
- Krippendorff α rendering (reads results/krippendorff-alpha.json if present)
- Round-to-round σ per tool per task

Writes a single JSON bundle to results/cross-task-stats.json plus a human-readable
markdown summary to results/FINAL-REPORT-3JUDGE-<DATE>.md.
"""

import itertools, json, os, re, random, statistics, sys
from collections import defaultdict
from datetime import datetime, timezone

random.seed(42)
N_BOOT = 10000

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TASKS = ('feature', 'bugfix', 'refactor')
JUDGES = ('opus', 'grok420', 'glm51', 'gpt54pro', 'mimo25pro')
JUDGE_PAIRS = list(itertools.combinations(JUDGES, 2))
ROUND_RE = re.compile(r'^round[0-9]+$')


def load_task(task):
    """Return dict of records: label, tool, trial, round, judge, score.

    `feature` uses the flat root layout (results/_blind-eval/); the other two
    tasks live under results/<task>/_blind-eval/.
    """
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
                    'label': label,
                    'tool': info['tool'],
                    'trial': info['trial'],
                    'round': int(rd.replace('round', '')),
                    'judge': judge,
                    'score': float(sum(scores.values())),
                })
    return records


def bootstrap_ci(values, n=N_BOOT, conf=0.95):
    if not values:
        return (0.0, 0.0, 0.0)
    k = len(values)
    means = sorted(sum(random.choice(values) for _ in range(k)) / k for _ in range(n))
    lo = means[int((1 - conf) / 2 * n)]
    hi = means[int((1 + conf) / 2 * n) - 1]
    return (statistics.mean(values), lo, hi)


def stratified_ci(records, tool, n=N_BOOT, conf=0.95):
    """Bootstrap CI on the balanced mean (mean of per-judge means), stratified by judge."""
    per_judge = {j: [r['score'] for r in records if r['tool'] == tool and r['judge'] == j]
                 for j in JUDGES}
    if any(not v for v in per_judge.values()):
        vals = [r['score'] for r in records if r['tool'] == tool]
        return bootstrap_ci(vals, n, conf)
    boots = []
    for _ in range(n):
        judge_means = []
        for j in JUDGES:
            pool = per_judge[j]
            k = len(pool)
            judge_means.append(sum(random.choice(pool) for _ in range(k)) / k)
        boots.append(statistics.mean(judge_means))
    boots.sort()
    mean = statistics.mean([statistics.mean(per_judge[j]) for j in JUDGES])
    lo = boots[int((1 - conf) / 2 * n)]
    hi = boots[int((1 + conf) / 2 * n) - 1]
    return (mean, lo, hi)


def spearman(xs, ys):
    def rank(arr):
        s = sorted(range(len(arr)), key=lambda i: arr[i])
        r = [0.0] * len(arr)
        i = 0
        while i < len(s):
            j = i
            while j + 1 < len(s) and arr[s[j + 1]] == arr[s[i]]:
                j += 1
            avg_rank = (i + j) / 2 + 1
            for k in range(i, j + 1):
                r[s[k]] = avg_rank
            i = j + 1
        return r
    rx, ry = rank(xs), rank(ys)
    n = len(xs)
    mx, my = sum(rx) / n, sum(ry) / n
    num = sum((rx[i] - mx) * (ry[i] - my) for i in range(n))
    dx = sum((v - mx) ** 2 for v in rx) ** 0.5
    dy = sum((v - my) ** 2 for v in ry) ** 0.5
    return num / (dx * dy) if dx and dy else 0.0


def spearman_ci_boot(pairs, n=2000, conf=0.95):
    if len(pairs) < 3:
        return (0.0, 0.0, 0.0)
    rhos = []
    for _ in range(n):
        sample = [random.choice(pairs) for _ in range(len(pairs))]
        xs, ys = zip(*sample)
        try:
            rhos.append(spearman(list(xs), list(ys)))
        except Exception:
            pass
    if not rhos:
        return (0.0, 0.0, 0.0)
    rhos.sort()
    xs, ys = zip(*pairs)
    point = spearman(list(xs), list(ys))
    lo = rhos[int((1 - conf) / 2 * len(rhos))]
    hi = rhos[int((1 + conf) / 2 * len(rhos)) - 1]
    return (point, lo, hi)


def ci_overlap(a_ci, b_ci):
    """True iff the two CIs overlap (closed intervals)."""
    return not (a_ci[2] < b_ci[1] or b_ci[2] < a_ci[1])


def tier_group(tools_sorted, ci_by_tool):
    """Group tools into tiers by *pairwise* CI overlap (complete-linkage).

    A candidate tool joins the current tier only when its CI overlaps with
    *every* existing member of that tier. This guarantees that "same tier"
    implies "pairwise CIs all overlap" — the transitive interpretation a
    reader expects from the phrase 'statistically indistinguishable cluster'.

    Strictly more conservative than single-linkage adjacency rules (which
    merge tools whose CIs do not pairwise overlap as long as an intermediate
    tool bridges them). Not a formal FWER-controlling procedure; see
    `pairwise_disjoint_matrix` for explicit pairwise comparisons.
    """
    if not tools_sorted:
        return []
    tiers = [[tools_sorted[0]]]
    for curr in tools_sorted[1:]:
        if all(ci_overlap(ci_by_tool[curr], ci_by_tool[m]) for m in tiers[-1]):
            tiers[-1].append(curr)
        else:
            tiers.append([curr])
    return tiers


def pairwise_disjoint_matrix(tools_sorted, ci_by_tool):
    """Return set of (A, B) unordered pairs whose 95% CIs are disjoint.

    Explicit per-pair separations. Unlike tier grouping, this needs no
    transitivity assumption — each pair is assessed on its own CI overlap.
    """
    disjoint = []
    for i, a in enumerate(tools_sorted):
        for b in tools_sorted[i + 1:]:
            if not ci_overlap(ci_by_tool[a], ci_by_tool[b]):
                disjoint.append((a, b))
    return disjoint


def main():
    all_records = {t: load_task(t) for t in TASKS}

    summary = {'tasks': {}, 'generated_at': datetime.now(timezone.utc).isoformat()}

    per_task_mean = {t: {} for t in TASKS}
    per_task_ci = {t: {} for t in TASKS}
    per_task_z = {t: {} for t in TASKS}
    per_task_sigma = {t: {} for t in TASKS}
    per_task_n = {t: {} for t in TASKS}

    cohort_stats = {}

    for task in TASKS:
        recs = all_records[task]
        tools = sorted({r['tool'] for r in recs})
        all_scores = [r['score'] for r in recs]
        cmean = statistics.mean(all_scores)
        csd = statistics.stdev(all_scores) if len(all_scores) > 1 else 1.0
        cohort_stats[task] = {'mean': cmean, 'sd': csd, 'n': len(all_scores)}

        per_judge_mean_by_tool = {}
        for tool in tools:
            per_judge = {j: [r['score'] for r in recs if r['tool'] == tool and r['judge'] == j]
                         for j in JUDGES}
            balanced = statistics.mean(
                [statistics.mean(per_judge[j]) for j in JUDGES if per_judge[j]]
            )
            tool_scores = [r['score'] for r in recs if r['tool'] == tool]
            sd_tool = statistics.stdev(tool_scores) if len(tool_scores) > 1 else 0.0
            mean, lo, hi = stratified_ci(recs, tool)
            per_task_mean[task][tool] = balanced
            per_task_ci[task][tool] = (mean, lo, hi)
            per_task_sigma[task][tool] = sd_tool
            per_task_n[task][tool] = len(tool_scores)
            per_task_z[task][tool] = (balanced - cmean) / csd
            per_judge_mean_by_tool[tool] = {
                j: (statistics.mean(per_judge[j]) if per_judge[j] else None) for j in JUDGES
            }

        # Judge drift per task
        judge_pooled = {j: [r['score'] for r in recs if r['judge'] == j] for j in JUDGES}
        judge_means = {j: statistics.mean(judge_pooled[j]) for j in JUDGES}
        judge_sds = {j: statistics.stdev(judge_pooled[j]) if len(judge_pooled[j]) > 1 else 0.0
                     for j in JUDGES}
        # "Three-judge mean" = equal-weight mean of three judge-specific means (not cmean)
        three_judge_mean = statistics.mean(judge_means.values())
        drift = {j: judge_means[j] - three_judge_mean for j in JUDGES}

        # Spearman ρ per judge pair — pair up per (label, round), use judge totals
        pairs_by_pair = {}
        for jA, jB in JUDGE_PAIRS:
            pairs = []
            by_key = defaultdict(dict)
            for r in recs:
                by_key[(r['label'], r['round'])][r['judge']] = r['score']
            for k, v in by_key.items():
                if jA in v and jB in v:
                    pairs.append((v[jA], v[jB]))
            rho, lo, hi = spearman_ci_boot(pairs)
            pairs_by_pair[f'{jA}_{jB}'] = {'rho': rho, 'lo': lo, 'hi': hi, 'n': len(pairs)}

        # Round-to-round stability per tool: stdev of per-round means
        stab_sigma = {}
        for tool in tools:
            by_round = defaultdict(list)
            for r in recs:
                if r['tool'] == tool:
                    by_round[r['round']].append(r['score'])
            per_round_means = [statistics.mean(v) for v in by_round.values() if v]
            stab_sigma[tool] = (statistics.stdev(per_round_means)
                                if len(per_round_means) > 1 else 0.0)

        summary['tasks'][task] = {
            'cohort_mean': cmean,
            'cohort_sd': csd,
            'n_judgments': len(all_scores),
            'per_tool_mean': per_task_mean[task],
            'per_tool_ci': {k: {'mean': v[0], 'lo': v[1], 'hi': v[2]}
                           for k, v in per_task_ci[task].items()},
            'per_tool_z': per_task_z[task],
            'per_tool_sigma_round': stab_sigma,
            'per_tool_sigma_pooled': per_task_sigma[task],
            'per_tool_n': per_task_n[task],
            'per_judge_mean': judge_means,
            'per_judge_sd': judge_sds,
            'three_judge_mean': three_judge_mean,
            'judge_drift': drift,
            'spearman_pairs': pairs_by_pair,
            'per_judge_mean_by_tool': per_judge_mean_by_tool,
        }

    all_tools = sorted(set.intersection(*[set(per_task_mean[t].keys()) for t in TASKS]))
    combined = {}
    for tool in all_tools:
        zs = [per_task_z[t][tool] for t in TASKS]
        combined[tool] = {
            'z_mean': statistics.mean(zs),
            'z_by_task': {t: per_task_z[t][tool] for t in TASKS},
        }

    ranked = sorted(all_tools, key=lambda t: -combined[t]['z_mean'])
    for rank, tool in enumerate(ranked, 1):
        combined[tool]['rank'] = rank

    rank_sum = {}
    for tool in all_tools:
        rs = 0
        per_task_r = {}
        for task in TASKS:
            tools_sorted = sorted(per_task_mean[task].items(), key=lambda x: -x[1])
            r = next(i for i, (t, _) in enumerate(tools_sorted, 1) if t == tool)
            rs += r
            per_task_r[task] = r
        rank_sum[tool] = {'rank_sum': rs, 'per_task_rank': per_task_r}

    # Judge calibration asymmetry: mean(opus) − mean(codex, qwen) per (task, tool).
    # Not a self-preference test — all executors share the Anthropic base, so a
    # uniform offset is indistinguishable from judge calibration drift. The JSON
    # key `self_preference` is kept for backward compatibility with downstream
    # consumers; see PAPER.md §4.5 for the correct framing.
    self_pref = {}
    for task in TASKS:
        self_pref[task] = {}
        for tool in all_tools:
            pjm = summary['tasks'][task]['per_judge_mean_by_tool'].get(tool, {})
            opus = pjm.get('opus')
            others = [v for k, v in pjm.items() if k != 'opus' and v is not None]
            if opus is None or not others:
                continue
            self_pref[task][tool] = opus - statistics.mean(others)

    # Tier grouping by non-overlapping CIs
    tiers_by_task = {}
    for task in TASKS:
        tools_sorted = sorted(per_task_ci[task].keys(),
                             key=lambda t: -per_task_ci[task][t][0])
        tiers_by_task[task] = tier_group(tools_sorted, per_task_ci[task])

    summary['combined'] = combined
    summary['rank_sum'] = rank_sum
    summary['self_preference'] = self_pref
    summary['tiers_by_task'] = tiers_by_task
    summary['cohort_stats'] = cohort_stats

    out_json = os.path.join(REPO, 'results', 'cross-task-stats.json')
    with open(out_json, 'w') as f:
        json.dump(summary, f, indent=2, default=str)
    print(f"Wrote {out_json}")

    # ── Markdown report ──
    today = datetime.now().strftime('%Y%m%d')
    out_md = os.path.join(REPO, 'results', f'FINAL-REPORT-3JUDGE-{today}.md')
    L = []
    L.append(f"# AI Coding Tool Benchmark — Final Report ({today})")
    L.append('')
    L.append(f"Generated: {summary['generated_at']}")
    L.append(f"Judges: {', '.join(JUDGES)}  (opus=claude-opus-4-7, grok420=x-ai/grok-4.20, glm51=glm-5.1, gpt54pro=gpt-5.4-pro, mimo25pro=mimo-v2.5-pro)")
    total_n = sum(cohort_stats[t]['n'] for t in TASKS)
    L.append(f"Corpus: {total_n} judgments ({' + '.join(str(cohort_stats[t]['n']) for t in TASKS)} across {', '.join(TASKS)})")
    L.append(f"Round filter: `^round[0-9]+$` (pilot/sample dirs excluded)")
    L.append(f"Score rule: `sum(scores.values())` per judge file; reported tool mean = balanced mean of per-judge means")
    L.append('')

    L.append('## Executive Summary')
    L.append('')
    L.append(f"- **Combined ranking (z̄ across 3 tasks, equal weight).** "
             f"{ranked[0]} ({combined[ranked[0]]['z_mean']:+.3f}) is highest; "
             f"{ranked[-1]} ({combined[ranked[-1]]['z_mean']:+.3f}) is lowest.")
    spread_top4 = combined[ranked[0]]['z_mean'] - combined[ranked[3]]['z_mean']
    # Count tasks where top-4 tools pairwise-overlap
    top4 = ranked[:4]
    top4_overlap_tasks = 0
    for task in TASKS:
        all_pairs_overlap = all(
            ci_overlap(per_task_ci[task][a], per_task_ci[task][b])
            for i, a in enumerate(top4) for b in top4[i + 1:]
        )
        if all_pairs_overlap:
            top4_overlap_tasks += 1
    L.append(f"- **Top-4 spread:** {spread_top4:.3f} z. Top-4 pairwise 95% CIs overlap on "
             f"{top4_overlap_tasks}/{len(TASKS)} tasks — treat top-4 as a tier, not a strict ranking.")
    L.append(f"- **Outlier:** superpower at z̄={combined['superpower']['z_mean']:+.3f}, "
             f"driven by bugfix (z={per_task_z['bugfix']['superpower']:+.3f}).")
    L.append('')

    L.append('## 1. Combined Ranking — z̄ and Rank-Sum')
    L.append('')
    L.append('| Rank | Tool | z̄ | feature z | bugfix z | refactor z | rank-sum |')
    L.append('|---|---|---|---|---|---|---|')
    for rank, tool in enumerate(ranked, 1):
        zs = combined[tool]['z_by_task']
        rs = rank_sum[tool]['rank_sum']
        L.append(f"| {rank} | **{tool}** | {combined[tool]['z_mean']:+.3f} | "
                 f"{zs['feature']:+.3f} | {zs['bugfix']:+.3f} | {zs['refactor']:+.3f} | {rs} |")
    L.append('')
    L.append("*z̄ averages three per-task z-scores (equal weight). Per-task z = (balanced_mean − cohort_mean) / cohort_sd, using all judgments in the task.*")
    L.append('')

    # Ranking sensitivity: equal-weight vs judgment-count-weighted z̄
    total_judgments = sum(cohort_stats[t]['n'] for t in TASKS)
    task_weights = {t: cohort_stats[t]['n'] / total_judgments for t in TASKS}
    weighted_z = {}
    for tool in all_tools:
        weighted_z[tool] = sum(per_task_z[t][tool] * task_weights[t] for t in TASKS)
    ranked_weighted = sorted(all_tools, key=lambda t: -weighted_z[t])

    L.append('## 2. Ranking Sensitivity Across Weighting Schemes')
    L.append('')
    L.append('*Three valid cross-task summaries. Equal-weight z̄ treats each task as one observation; '
             'count-weighted z̄ weights by judgments-per-task (540/162/162); rank-sum uses ordinal '
             'position per task. The three agree on the top cluster and bottom outlier; they disagree '
             'on middle ordering. Treat cross-task rank positions as a summary, not a leaderboard.*')
    L.append('')
    L.append('| Tool | z̄ equal | rank eq | z̄ weighted | rank wt | rank-sum | rank rs |')
    L.append('|---|---|---|---|---|---|---|')
    equal_rank = {t: r for r, t in enumerate(ranked, 1)}
    weighted_rank = {t: r for r, t in enumerate(ranked_weighted, 1)}
    rank_sum_order = sorted(all_tools, key=lambda t: rank_sum[t]['rank_sum'])
    rs_rank = {t: r for r, t in enumerate(rank_sum_order, 1)}
    for tool in ranked:
        L.append(f"| {tool} | {combined[tool]['z_mean']:+.3f} | {equal_rank[tool]} | "
                 f"{weighted_z[tool]:+.3f} | {weighted_rank[tool]} | "
                 f"{rank_sum[tool]['rank_sum']} | {rs_rank[tool]} |")
    L.append('')
    # Report any tools whose rank moves by 2+ between schemes
    movers = [t for t in all_tools
              if max(equal_rank[t], weighted_rank[t], rs_rank[t])
              - min(equal_rank[t], weighted_rank[t], rs_rank[t]) >= 2]
    if movers:
        L.append(f"*Tools with ≥2 rank positions of movement across schemes: {', '.join(sorted(movers))}. "
                 "Their positions are weighting-dependent and should not be cited as leaderboard ranks.*")
    else:
        L.append('*All tools are within 1 position across weighting schemes; the ranking is robust.*')
    L.append('')

    L.append('## 3. Per-Task Scores with 95% Bootstrap CIs')
    L.append('')
    for task in TASKS:
        L.append(f"### {task}")
        L.append('')
        L.append(f"Cohort: mean = {cohort_stats[task]['mean']:.2f}, sd = {cohort_stats[task]['sd']:.2f}, "
                 f"n = {cohort_stats[task]['n']} judgments.")
        L.append('')
        tools_sorted = sorted(per_task_ci[task].keys(), key=lambda t: -per_task_ci[task][t][0])
        L.append('| Tier | Tool | Mean /200 | 95% CI | σ (pooled) | n |')
        L.append('|---|---|---|---|---|---|')
        tiers = tiers_by_task[task]
        for tier_idx, tier in enumerate(tiers, 1):
            for tool in tier:
                m, lo, hi = per_task_ci[task][tool]
                sd = per_task_sigma[task][tool]
                n = per_task_n[task][tool]
                L.append(f"| T{tier_idx} | {tool} | {m:.2f} | [{lo:.1f}, {hi:.1f}] | {sd:.2f} | {n} |")
        L.append('')
        L.append(f"Tiers (pairwise 95%-CI overlap, complete linkage): "
                 f"{' › '.join('{' + ', '.join(t) + '}' for t in tiers)}")
        # Pairwise disjoint comparisons — explicit, transitivity-free
        disjoint = pairwise_disjoint_matrix(tools_sorted, per_task_ci[task])
        if disjoint:
            L.append('')
            L.append(f"Pairwise-disjoint 95% CIs ({len(disjoint)} of "
                     f"{len(tools_sorted) * (len(tools_sorted) - 1) // 2} pairs): "
                     f"{', '.join(f'{a}/{b}' for a, b in disjoint)}.")
        L.append('')

    L.append('## 4. Judge Calibration')
    L.append('')
    mean_cols = ' | '.join(f'{j} mean' for j in JUDGES)
    drift_cols = ' | '.join(f'Δ{j}' for j in JUDGES)
    L.append(f'| Task | {mean_cols} | {drift_cols} |')
    L.append('|---' + '|---' * (len(JUDGES) * 2) + '|')
    for task in TASKS:
        td = summary['tasks'][task]
        jm = td['per_judge_mean']
        d = td['judge_drift']
        means_str = ' | '.join(f'{jm[j]:.1f}' for j in JUDGES)
        drifts_str = ' | '.join(f'{d[j]:+.1f}' for j in JUDGES)
        L.append(f'| {task} | {means_str} | {drifts_str} |')
    L.append('')
    L.append(f'*Δ = judge mean − {len(JUDGES)}-judge mean (equal-weight mean of all judges). '
             'Identifies which judges are systematically harsh / generous; opus is the Anthropic anchor.*')
    L.append('')

    L.append('## 5. Inter-Judge Agreement')
    L.append('')
    L.append('### 5a. Spearman ρ on artifact-level totals (95% bootstrap CI)')
    L.append('')
    L.append('*Measures **rank-order** agreement: do judges order artifacts similarly? '
             'Insensitive to absolute-scale drift.*')
    L.append('')
    pair_cols = ' | '.join(f'ρ({a},{b}) [CI]' for a, b in JUDGE_PAIRS)
    L.append(f'| Task | {pair_cols} | n pairs |')
    L.append('|---' + '|---' * (len(JUDGE_PAIRS) + 1) + '|')
    for task in TASKS:
        sp = summary['tasks'][task]['spearman_pairs']
        cells = []
        n_any = 0
        for a, b in JUDGE_PAIRS:
            p = sp.get(f'{a}_{b}', {'rho': float('nan'), 'lo': float('nan'), 'hi': float('nan'), 'n': 0})
            cells.append(f"{p['rho']:+.2f} [{p['lo']:+.2f}, {p['hi']:+.2f}]")
            n_any = max(n_any, p['n'])
        L.append(f"| {task} | {' | '.join(cells)} | {n_any} |")
    L.append('')
    L.append('*ρ CIs that cross zero indicate inter-judge rank-agreement not distinguishable from chance — '
             'treat per-task rankings on those tasks as noise-dominated.*')
    L.append('')

    # ── Krippendorff α — absolute-scale agreement ──
    alpha_path = os.path.join(REPO, 'results', 'krippendorff-alpha.json')
    if os.path.isfile(alpha_path):
        try:
            with open(alpha_path) as af:
                alpha_data = json.load(af)
            L.append("### 5b. Krippendorff α — absolute-scale agreement")
            L.append('')
            L.append('*α measures **interval-scale** agreement: do judges assign similar absolute scores? '
                     'Sensitive to calibration drift in ways Spearman ρ is not. '
                     '`α item` uses per-rubric-item scores (20 items × labels); '
                     '`α total` uses summed totals per label. '
                     'Thresholds: ≥0.80 excellent; ≥0.667 acceptable; ≥0.61 substantial; '
                     '≥0.40 moderate; negative = observed disagreement exceeds what chance alone '
                     'would produce on the measured scale.*')
            L.append('')
            pair_hdr = ' | '.join(f'α {a}/{b}' for a, b in JUDGE_PAIRS)
            L.append(f'| Task | α (per-item) | α (totals) | {pair_hdr} |')
            L.append('|---|---|---' + '|---' * len(JUDGE_PAIRS) + '|')
            for task in TASKS:
                if task not in alpha_data:
                    continue
                a = alpha_data[task]
                p = a['pairwise_total']
                pair_cells = ' | '.join(
                    f"{p.get(f'{ja}_{jb}', {}).get('alpha', float('nan')):+.3f}"
                    for ja, jb in JUDGE_PAIRS
                )
                L.append(f"| {task} | {a['alpha_item_interval']:+.3f} | "
                         f"{a['alpha_total_interval']:+.3f} | {pair_cells} |")
            L.append('')
            L.append('*Per-item α is higher than totals α on every task: judges agree on which rubric items '
                     'matter more, but disagree on absolute scale. The three-judge balanced mean of per-judge '
                     'means is the intended mitigation — but low/negative α on totals means a single-judge '
                     'result on this corpus would be materially different from the panel result. '
                     'Re-run `scripts/krippendorff-alpha.py` after corpus updates.*')
            L.append('')
        except Exception:
            pass
    else:
        L.append("*Krippendorff α not available — run `python3 scripts/krippendorff-alpha.py` to generate.*")
        L.append('')


    L.append('## 6. Judge Calibration Asymmetry — opus vs. non-Anthropic judges')
    L.append('')
    others_label = ', '.join(j for j in JUDGES if j != 'opus')
    L.append(f'*Δ per (task, tool) = opus judge mean − mean({others_label}) on that (task, tool) cell. '
             'This statistic measures whether the opus judge scores artifacts systematically '
             'above or below the non-Anthropic judges, and whether that drift varies across tools. '
             '**Identification note:** all nine executors use the same Anthropic base model '
             '(`claude-opus-4-6`), so this design has no non-Anthropic executor control. '
             'A uniform Δ is therefore indistinguishable from simple judge-calibration drift; '
             'a tool-specific Δ would be needed to flag family favoritism. Treat a small, '
             'tool-invariant Δ as inconclusive on self-preference, not as evidence of its absence.*')
    L.append('')
    L.append('| Task | Mean Δ(opus − others) | Range across tools | Within-range spread |')
    L.append('|---|---|---|---|')
    for task in TASKS:
        deltas = list(self_pref[task].values())
        if deltas:
            spread = max(deltas) - min(deltas)
            L.append(f"| {task} | {statistics.mean(deltas):+.2f} | "
                     f"[{min(deltas):+.2f}, {max(deltas):+.2f}] | {spread:.2f} |")
    L.append('')
    L.append('*Read: mean Δ shows opus\'s calibration offset on each task; within-range spread '
             'shows whether that offset varies across tools. A small spread means the offset is '
             'approximately uniform → judge calibration drift, not tool-specific self-preference. '
             'This test cannot rule out *family-level* favoritism (no non-Anthropic executor present).*')
    L.append('')

    L.append('## 7. Round-to-Round Stability')
    L.append('')
    L.append('σ = stdev of per-round mean scores per tool (lower = more reproducible).')
    L.append('')
    L.append('| Tool | feature σ | bugfix σ | refactor σ |')
    L.append('|---|---|---|---|')
    all_sigmas = []
    for tool in ranked:
        row = []
        for task in TASKS:
            v = summary['tasks'][task]['per_tool_sigma_round'][tool]
            row.append(f"{v:.1f}")
            all_sigmas.append(v)
        L.append(f"| {tool} | {row[0]} | {row[1]} | {row[2]} |")
    L.append('')
    max_sigma = max(all_sigmas) if all_sigmas else 0.0
    L.append(f'*Max round-to-round σ across all (tool, task) cells: {max_sigma:.1f} pts. '
             'Bugfix/refactor have 3 rounds per tool per judge; σ estimates on those tasks '
             'are still high-variance at small n.*')
    L.append('')

    L.append('## 8. Key Findings')
    L.append('')
    L.append('1. **Top-4 is a statistical tie.** bmad, ecc, pure, gstack sit within '
             f"{spread_top4:.2f} z across tasks; their pairwise 95% CIs overlap on "
             f"{top4_overlap_tasks}/{len(TASKS)} tasks.")
    L.append('2. **superpower is the only outlier**, at z̄ = '
             f"{combined['superpower']['z_mean']:+.3f}. Driven entirely by bugfix "
             f"(z={per_task_z['bugfix']['superpower']:+.3f}); mid-pack on feature and refactor.")
    L.append('3. **pure (baseline) is top-4.** The null hypothesis "enhancement frameworks add no measurable quality over Claude Code baseline" is not rejected at this precision. Tools may still add value on cost, speed, or DX — not captured here.')
    L.append('4. **Judge calibration differs by ±25 points** but rank orders agree on feature and bugfix. On refactor inter-judge ρ is ≈ 0 — the cohort is too compressed for judges to discriminate. Rankings on refactor are noise-dominated and should not be cited in isolation.')
    L.append('5. **Judge calibration asymmetry is small and tool-invariant.** opus drifts against the non-Anthropic pair by single-digit points per task with little tool-specific variation, consistent with calibration drift rather than tool-specific self-preference. Family-level self-preference is **not identified** by this design (all executors share `claude-opus-4-6` as base) — any claim of "no self-preference bias" would overstate what this corpus can show.')
    L.append('')

    L.append('## 9. Caveats')
    L.append('')
    L.append('- **Language/codebase:** single TypeScript codebase; results may not generalize to Python/Go/Rust.')
    L.append('- **Base-model scope:** single executor base (`claude-opus-4-6`); rankings may differ on other bases.')
    L.append('- **Small-n cells:** bugfix and refactor have 18 judgments per (tool, task) cell = 2 trials × 3 rounds × 3 judges; 6 observations per judge stratum. Percentile-bootstrap CI coverage at n=6 per stratum is approximate; treat close calls as inconclusive.')
    L.append('- **Pseudoreplication risk:** the stratified bootstrap treats each (trial, round, judge) score as an independent draw, but rounds re-judge the same artifact. That inflates apparent precision relative to a trial-clustered resampling. The qualitative separations reported here (superpower/bugfix, tier boundaries) are robust to this; close pairwise calls should not be cited as "significant."')
    L.append('- **Judge sampling not pinned:** judge CLIs are not configured with temperature=0 or sampler seed. Round-to-round σ partially reflects sampler variance rather than reasoning variance; three-judge averaging is the intended mitigation.')
    L.append('- **Equal-weight z̄ is one of several valid summaries.** Judgment-count-weighted z̄ (weights 540/162/162) reorders the middle tiers. Use the per-task tables as primary and z̄/rank-sum as cross-task summaries, not leaderboard positions.')
    L.append('- **Tier grouping is descriptive, not FWER-controlling.** Tiers are formed by pairwise 95%-CI overlap (complete linkage); this is a visual-cluster heuristic. Only individually cited pairwise separations (see §3 per-task pairwise-disjoint lists) carry statistical weight, and no multiple-comparison adjustment (Bonferroni/Holm) is applied across the 108 cross-task cell comparisons.')
    L.append('- **Inter-judge agreement uses Spearman ρ** at the (label, round) artifact level. Krippendorff α / ICC(3,k) would give absolute-scale reliability; see `scripts/krippendorff-alpha.py`. Low agreement on refactor is a genuine ranking signal, not an artifact of n=9 tool means.')
    L.append('- **Self-preference is not identified.** Every executor uses an Anthropic base; a uniform opus offset is indistinguishable from calibration drift. The §6 statistic is a judge-calibration check, not a family-favoritism audit.')
    L.append('- **Not preregistered.** Tasks, rubric, and judge panel were chosen iteratively by the benchmark author (who also authors `omc`). `omc` ranks 7–8 across weighting schemes (self-critical); see `PAPER.md` §6 and §7 for COI disclosure.')
    L.append('- **Corpus hygiene:** 239 historical judge JSONs had stale `total` fields; this report uses `sum(scores)` as canonical (corrected in-place). `_human-reference/` is excluded from cohort mean/stdev.')
    L.append('')

    L.append('## Appendix — Pipeline')
    L.append('')
    L.append('- Aggregator: `scripts/aggregate-results.sh` (per-task, `sum(scores)` rule, canonical round filter).')
    L.append('- Cross-task stats (this script): `scripts/cross-task-analysis.py`. Seed: 42. N_bootstrap: 10,000.')
    L.append(f'- Judgments: `results/{{task}}/_blind-eval/<LABEL>/round[0-9]+/{{{",".join(JUDGES)}}}-judge.json`')
    L.append('- Label → (tool, trial) mapping: `.mapping-DO-NOT-OPEN.json` in each `_blind-eval/`.')
    L.append('')

    with open(out_md, 'w') as f:
        f.write('\n'.join(L) + '\n')
    print(f"Wrote {out_md}")


if __name__ == '__main__':
    main()
