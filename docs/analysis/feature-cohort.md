# Feature Cohort — Cross-Tool Analysis

**Cohort**: 8 tools × 5 trials × 5 judges × 3 rounds = 600 valid judgments
**Base model**: claude-opus-4-7 (all tools)
**Task**: greenfield feature implementation on a private TypeScript NX monorepo (financial-services domain)
**Generated**: 2026-05-18 (re-aggregated after the t4/t5 trial expansion + 2 stability rounds)

## Ranking (equal-weight 5-judge pooled mean / 200)

> **Metric note.** This page ranks by **equal-weight pooled mean** so the score column is directly comparable to the cost / effort columns below (every judgment carries weight 1). The **canonical** benchmark ranking — used in [`PAPER.md`](../../PAPER.md), [`README.md`](../../README.md), and [`results/final-report.md`](../../results/final-report.md) — is the **weighted mean** with pre-registered panel weights (opus×3, gpt54pro×2, others×1). The two rankings agree on rank-1 (`ecc`) but swap ranks 2–3; see the paragraph below for the mechanical reason.

Values are the `Pooled Mean` column from [`results/final-report.md`](../../results/final-report.md). The weighted-mean ranking (the canonical one, with pre-registered 3 / 2 / 1 / 1 / 1 weights) and the equal-weight ranking shown below agree on rank-1 (`ecc`) and rank-4 (`superpower`) but swap ranks 2↔3 — under weighted mean the order is ecc / pure / bmad / superpower, while under equal weighting bmad edges ahead of pure (ecc / bmad / pure / superpower). Mechanically, equal pooling moves every judge to weight 0.20 (vs the weighted scheme's opus = 0.375, gpt54pro = 0.25, others = 0.125), so it **downweights the harsh judges (`opus`, `gpt54pro`)** and **upweights `grok420` / `glm51` / `mimo25pro`** — tools with weaker opus / gpt54pro marks but stronger grok420 / mimo25pro scores (`bmad`, `compound`) rise once the harsh judges' share of the average shrinks.

| Rank | Tool | Pooled Mean | Pooled σ |
|---|---|---|---|
| 1 | ecc | **157.11** | 16.46 |
| 2 | bmad | **147.65** | 19.99 |
| 3 | pure | **147.44** | 16.05 |
| 4 | superpower | **143.68** | 16.95 |
| 5 | omc | **143.59** | 19.00 |
| 6 | compound | **140.11** | 19.65 |
| 7 | claudekit | **139.07** | 19.67 |
| 8 | gstack | **137.80** | 25.02 |

Spread: 19.3 pts. ecc leads rank-2 `bmad` by 9.5 pts; ranks 2–5 sit within 4.1 pts. Lowest pooled σ: pure (16.05), then ecc (16.46). (Pooled σ mixes within-judge and between-judge variance — for trial-to-trial-plus-round-to-round consistency see the `within_σ` column in [`results/final-report.md`](../../results/final-report.md), where the leader on feature is now bmad at 7.02.)

## Effort & Cost (per-trial mean)

Score is the **equal-weight pooled mean** (5 trials × 5 judges × 3 rounds = 75 judgments per row), matching the ranking table above; the canonical weighted-mean score for each tool lives in [`results/final-report.md`](../../results/final-report.md). Files / +Lines / Cost / Wall / Turns / Subagents are per-trial run-time stats from the n=3 session-audit subsystem and are unchanged by the trial/round expansion.

| Tool | Score | Files | +Lines | Cost | Wall (s) | Turns | Subagents |
|---|---|---|---|---|---|---|---|
| ecc | 157.1 | 27.0 | 1924 | $156.6 | 13313 | 216 | 1.7 |
| bmad | 147.7 | 8.3 | 521 | $43.6 | 1148 | 156 | 1.0 |
| pure | 147.4 | 16.3 | 821 | $73.8 | 1822 | 138 | 1.0 |
| superpower | 143.7 | 36.0 | 2706 | $172.0 | 5079 | 183 | 18.3 |
| omc | 143.6 | 34.3 | 1837 | $554.7 | 5046 | 171 | 10.7 |
| compound | 140.1 | 13.7 | 960 | $68.8 | 1317 | 165 | 1.7 |
| claudekit | 139.1 | 33.0 | 1940 | $93.8 | 2330 | 116 | 2.3 |
| gstack | 137.8 | 12.7 | 1000 | $63.6 | 1992 | 156 | 2.7 |

## Cost-efficiency (pts per $)

| Tool | Score / $ |
|---|---|
| **bmad** | **3.39** |
| gstack | 2.17 |
| compound | 2.04 |
| pure | 2.00 |
| claudekit | 1.48 |
| ecc | 1.00 |
| superpower | 0.84 |
| omc | 0.26 |

bmad delivers 94% of ecc's score at 28% of the cost. omc burns 13× more than bmad for ~4 fewer points.

## Key observations

### Quality vs verbosity is non-monotonic
Top scorer (ecc, 1924 lines, $156) and bottom scorer (gstack, 1000 lines, $63) ship comparable code volume yet rank 19.3 pts apart. bmad lands within ~9.5 pts of ecc on under half the lines and ~28% of the cost — judges weight design choices over diff size.

### Hard-gate pass ≠ judge score
- superpower: highest gate pass rate (5.0/6) but rank-4 in judge score
- gstack, bmad: 2.0/6 gates avg yet bmad ranks 2nd
Hard gates measure mechanical compliance (G1-G7); judges weight reasoning, structure, test design — orthogonal axes.

### Multi-agent fan-out doesn't predict quality
- superpower: 18.3 subagents/trial → rank 4
- omc: 10.7 subagents/trial → rank 5
- bmad, pure: 1.0 subagent → ranks 2 and 3
Subagent expansion is a cost multiplier, not a quality multiplier on this task.

### omc is the cost outlier
$554.7/trial — 6.6× the cohort median ($84). 10.7 subagents × deep cache reuse drives it (see [`session-audit.md`](../../results/_audits/session-audit.md)). Not justified by score (rank 5).

### Judge harshness gradient
| Judge | Cohort mean |
|---|---|
| gpt54pro | 117.8 |
| opus | 139.3 |
| glm51 | 149.8 |
| mimo25pro | 156.2 |
| grok420 | 159.8 |

gpt54pro is the floor (42.0 pt range below grok420). The weighted (3/2/1/1/1) and equal-weight aggregations both cancel this asymmetry on rank-1; top-3 swaps ranks 2–3 on feature only (see ranking section above).

### Trial-to-trial volatility (pooled σ)
| Tool | Pooled σ |
|---|---|
| pure | 16.05 (most stable) |
| ecc | 16.46 |
| superpower | 16.95 |
| omc | 19.00 |
| compound | 19.65 |
| claudekit | 19.67 |
| bmad | 19.99 |
| gstack | 25.02 (most volatile) |

bmad, claudekit, compound, omc sit near the 20-pt mark and gstack at 25 — most of that is judge disagreement rather than tool instability. The `within_σ` column in [`results/final-report.md`](../../results/final-report.md) shows within-judge noise across the 15 samples per (tool, judge) is much smaller (7.0–18.4 on feature) — the dominant component is `between_σ` (judge base-rate spread).

## Headline takeaways

1. **ecc wins on quality** (equal-weight rank-1, 157.1) but at high cost.
2. **bmad is the value pick** — 94% of ecc's score at 28% of the price, and equal-weight rank-2.
3. **bmad and pure split ranks 2–3** depending on the weighting scheme; both are strong-value picks while compound/claudekit fall to the mid/lower pack.
4. **omc and superpower invest heavily in fan-out** without commensurate judge reward on this task (ranks 5 and 4).
5. **gstack is rank-8 on every aggregation** — the equal-weight gap to #7 (`claudekit`) is only ~1.3 pts and ~2.7 pts under weighted-mean, narrower than the v1 snapshot. At the recomputed n=5 MDE the **only** statistically-significant separation in the whole corpus is `ecc` − `gstack` on **feature** (≈21.3 > the 19.33-pt feature MDE); gstack's dramatic-looking refactor mean (144.92) is driven by a single low-scored trial (t4 ≈ 36/200 vs ~178 on its other four) and is *not* distinguishable at n=5 once that trial's variance enters the refactor σ_pool.

## Caveats

- n=5 trials per tool × 5 judges × 3 rounds = 75 judgments per cell. Pairs within ~5 weighted pts should be read as ties on this n. The two added stability rounds (judging only — not new trials) tighten the per-judge mean estimate, and the cohort now runs the full 5-trial denominator.
- One feature task. Per-tool generalization across the three tasks (feature, bugfix, refactor) is reported in the three per-task `final-report.md` files; cross-task synthesis as a single leaderboard is intentionally not reported (see [README caveat 7](../../README.md#caveats)).
- Judges sample at provider defaults (no temperature pin exposed for opus or gpt54pro).
- gpt54pro is the harshest judge by 40+ pts; rank-1 is stable under both weighted (3/2/1/1/1) and equal-weight aggregation on every task.

## Related

- [`skill-cost-efficiency.md`](skill-cost-efficiency.md) — per-skill output_tokens / score and output_tokens / line on the same feature cohort. ecc is the only tool that ships its +1,924 lines on under 50k skill output tokens; superpower runs 6,353 tok/pt as the cohort outlier.
- [`../../results/_audits/session-audit.md`](../../results/_audits/session-audit.md) — full behavioural fingerprints (subagent dispatch, tool-config reads, cache hit ratio) across all 3 tasks.
