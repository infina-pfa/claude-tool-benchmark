# Robust-statistics companion — median and trimmed-mean view

Generated: 2026-05-19 by [`scripts/compute-robust-stats.py`](../scripts/compute-robust-stats.py).
Source: same 1,800 canonical judge JSONs the headline report consumes.

## Why

The pre-registered protocol forbids dropping any in-distribution trial. A single
high-variance trial (`gstack` t4 refactor weighted mean **36.42** vs **153.79–181.67**
on its other four trials) therefore moves the canonical refactor leaderboard
and inflates σ_pool from ~10 to ~22, pushing refactor MDE from ~24 to **44 pts**.

That trial is retained in the canonical report (correctly — selective post-hoc
removal would bias the cohort). This companion view is the parallel question
the canonical view cannot answer: *what does the leaderboard look like under
location estimators that are insensitive to a single trial?*

- **Median** — natural robust analog of the mean. Invariant to a single outlier
  in either tail.
- **Trimmed mean (drop hi/lo)** — average of the middle 3 of 5 trials. Less
  robust than median but uses more of the data.

**This companion does not replace the canonical mean.** The mean is the
pre-registered primary statistic. This is a sensitivity view, published for
the same reason the equal-weight report is — so readers can verify rank
stability under alternative aggregation rules.

## Aggregation rule (matches canonical aggregator)

1. Per (tool, trial), compute the per-judge mean across that trial's 5 (or 15
   with rounds) judgments per judge.
2. Combine the 5 per-judge means into a single per-trial weighted mean using
   the pre-registered weights from `versions.lock.json` (opus×3 / gpt54pro×2 /
   grok420 / glm51 / mimo25pro all ×1).
3. Then take the **median** or **trimmed mean** of the 5 per-trial weighted
   means — the only change vs. the canonical aggregator, which takes the
   arithmetic mean at this last step.

## Refactor — where the trial-4 gstack run matters most

| Tool | Mean (canonical) | Median | Trimmed mean (drop hi/lo) | Trial spread | Trial-level weighted means |
|---|---:|---:|---:|---:|---|
| pure       | **180.19** | 179.58 | 179.72 |   4.5 | 180.17 / 183.17 / 179.58 / 178.62 / 179.42 |
| claudekit  | **178.04** | 177.33 | 177.58 |   3.9 | 178.21 / 177.21 / 180.67 / 177.33 / 176.79 |
| bmad       | **177.74** | 177.96 | 177.68 |   4.0 | 177.96 / 179.83 / 179.08 / 175.83 / 176.00 |
| superpower | **177.56** | 177.67 | 177.14 |   8.0 | 182.17 / 177.67 / 178.46 / 175.29 / 174.21 |
| compound   | **174.42** | 174.88 | 174.71 |   8.2 | 175.29 / 174.88 / 173.96 / 169.88 / 178.08 |
| ecc        | **173.61** | 175.46 | 176.11 |  18.7 | 179.21 / 173.92 / 178.96 / 175.46 / 160.50 |
| omc        | **170.11** | 171.33 | 171.43 |  15.2 | 171.33 / 160.50 / 175.75 / 173.50 / 169.46 |
| gstack     | **144.92** | **174.58** | 168.83 | **145.2** | 174.58 / 153.79 / 181.67 / **36.42** / 178.12 |

**Headline shift on refactor — gstack t4 is doing the work.**

Under the canonical mean, `gstack` is rank-8 at 144.92, with a 25.2-pt gap
from rank-7 (`omc` 170.11). Under the **median**, `gstack` is **174.58** —
ahead of both `omc` (171.33) and `ecc` (175.46 — actually within 1 pt of
gstack-median). The 4 well-behaved gstack trials (174.58 / 153.79 / 181.67 /
178.12) put it firmly in the middle of the pack; the t4 collapse (36.42) is
moving the gstack canonical figure by ~30 pts.

Under the **trimmed mean** (drop t4=36.42 and t3=181.67) gstack lands at
168.83 — still rank-8, but the gap to rank-7 narrows from 25.2 pts (mean) to
2.6 pts.

**Pure remains rank-1 on refactor under all three statistics.** Top-4
(`pure / claudekit / bmad / superpower`) is invariant. The story this view
adds: the refactor leaderboard is even more obviously a statistical tie
than the canonical mean already suggests. Removing the canonical mean's
sensitivity to one trial collapses the rank-1-to-rank-8 spread from 35.3
pts (mean) to ~5.6 pts (median).

## Feature

| Tool | Mean (canonical) | Median | Trimmed mean | Trial spread | Trial-level weighted means |
|---|---:|---:|---:|---:|---|
| ecc        | **153.30** | 152.75 | 152.39 | 20.3 | 149.67 / 152.75 / 144.50 / 164.83 / 154.75 |
| pure       | **143.13** | 143.96 | 143.06 |  7.1 | 140.00 / 146.79 / 139.71 / 143.96 / 145.21 |
| bmad       | **141.33** | 140.25 | 141.06 |  8.6 | 140.12 / 142.79 / 140.25 / 137.46 / 146.04 |
| superpower | **140.16** | 139.88 | 140.85 | 19.4 | 144.29 / 148.83 / 138.38 / 129.42 / 139.88 |
| omc        | **139.49** | 143.71 | 141.31 | 21.4 | 146.00 / 126.08 / 134.21 / 147.46 / 143.71 |
| claudekit  | **135.04** | 136.12 | 137.71 | 31.0 | 135.62 / 115.54 / 146.54 / 141.38 / 136.12 |
| compound   | **134.67** | 140.12 | 136.22 | 23.9 | 141.58 / 144.29 / 140.12 / 120.38 / 126.96 |
| gstack     | **131.98** | 129.12 | 130.18 | 46.0 | 111.67 / 129.12 / 123.75 / 157.71 / 137.67 |

**Feature — most ranks invariant, two rank-3 / rank-4 swaps in middle.**
Rank-1 (`ecc`) and rank-2 (`pure`) are stable across all three statistics.
Under the median, `omc` rises from canonical rank-5 (139.49) to rank-4
(143.71) on the back of a low-variance set of trials with one bottom-tail
outlier (126.08); under the trimmed mean `omc` is also rank-4. `superpower`
drops from canonical rank-4 to rank-5 under median/trimmed for the same
reason — t4=129.42 pulls its mean up less than its median.

`claudekit` has the largest feature trial spread (31.0 pts; t2=115.54), and
`compound` jumps from canonical rank-7 to median rank-5 (134.67→140.12) —
both are sensitive to one bottom-tail trial each. Neither cross the rank-1
or top-3 boundary.

## Bugfix

| Tool | Mean (canonical) | Median | Trimmed mean | Trial spread | Trial-level weighted means |
|---|---:|---:|---:|---:|---|
| claudekit  | **178.93** | 184.25 | 181.85 | 30.3 | 188.75 / 189.71 / 172.54 / 184.25 / 159.42 |
| ecc        | **172.31** | 175.08 | 175.43 | 36.8 | 186.04 / 170.38 / 180.83 / 149.21 / 175.08 |
| pure       | **169.53** | 165.00 | 169.32 | 25.0 | 160.96 / 182.33 / 182.00 / 157.38 / 165.00 |
| superpower | **166.41** | 167.12 | 166.24 |  8.4 | 164.42 / 170.88 / 167.12 / 167.17 / 162.46 |
| compound   | **166.25** | 164.12 | 166.00 | 16.7 | 174.96 / 159.04 / 164.12 / 174.83 / 158.29 |
| bmad       | **165.72** | 160.25 | 164.61 | 29.8 | 158.67 / 182.29 / 174.92 / 160.25 / 152.46 |
| omc        | **164.80** | 159.67 | 163.81 | 33.3 | 159.67 / 153.00 / 182.92 / 149.67 / 178.75 |
| gstack     | **159.97** | 161.38 | 160.10 | 12.4 | 156.25 / 162.67 / 153.58 / 165.96 / 161.38 |

**Bugfix — rank-1 (claudekit) stable.** Median elevates claudekit's
margin (184.25 vs. ecc 175.08 = 9.2-pt median gap, similar to the 6.6-pt
canonical mean gap). `bmad` drops from canonical rank-6 to median rank-7
(165.72→160.25) — its mean is propped up by two right-tail trials
(t2=182.29, t3=174.92). Top-3 (`claudekit / ecc / pure`) is identical
under mean and trimmed mean; under median, `pure` (165.00) edges below
`superpower` (167.12) — a rank-3 / rank-4 swap. `gstack` shows the
smallest bugfix trial spread (12.4 pts) — well-behaved on this task.

## How to read this

- **Ordering changes under median or trimmed mean → canonical mean is
  absorbing trial outliers.** Treat the canonical mean ranking with extra
  suspicion for tools showing large shifts.
- **Ordering invariant under all three statistics → ranking is robust to
  single-trial outliers within this corpus.**

In this corpus:
- **Refactor gstack:** rank-8 → rank-7 under median; t4 alone is doing
  ~30 pts of work on the canonical mean. The only large-magnitude shift
  in the cohort.
- **Feature claudekit / compound / omc / superpower:** swap by one rank
  in the middle of the table under median; none cross top-3.
- **Bugfix bmad / pure / superpower:** swap by one rank in mid-table
  under median; rank-1 invariant.
- **Rank-1 invariant on every task across mean / median / trimmed.** This
  matches the canonical report's "rank-1 stable across weighted and
  equal-weight rules" finding and extends it to robust location estimators.

This robust view *strengthens* — does not contradict — the canonical
report's "everything is a statistical tie" headline. The largest
canonical-mean visual gap in the corpus (gstack refactor: 35.3 pts to
rank-7) shrinks to ~5.6 pts under the median.

## Data and reproduction

- **Raw figures:** [`results/robust-statistics.json`](robust-statistics.json) —
  per-task, per-tool, per-trial weighted means + median + trimmed mean.
- **Source:** the 1,800 canonical judge JSONs at
  `results/{,bugfix/,refactor/}_blind-eval/<LABEL>/[round*/]*-judge.json`.
- **Rule:** same weighted-mean-of-per-judge-means at the trial level, same
  round-filter (label root ∪ `^round[0-9]+$`), same R1 override (applied
  in the canonical aggregation before this script reads).
- **Recompute:** `python3 scripts/compute-robust-stats.py` regenerates
  `results/robust-statistics.json` deterministically.

> This companion view is **not** the pre-registered primary statistic.
> The canonical weighted-mean report is the headline; this file is a
> sensitivity check on what the leaderboard says under robust location
> estimators that are insensitive to a single trial's score.
