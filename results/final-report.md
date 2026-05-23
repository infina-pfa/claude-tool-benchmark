# feature — Per-Task Aggregation

Generated: 2026-05-19T04:05:40Z

## Inputs and source artifacts

Everything fed into this aggregation is committed; no private state.

- **Trial input (task PRD).** The exact prompt every tool saw for this task: `_blind-eval/prd.md` (omitted from public release).
- **Per-tool prompt prefix.** The tool-specific slash command bound to that PRD lives in [`scripts/manual-bench.sh`](../scripts/manual-bench.sh).
- **Judge input (verbatim request payload).** What each of the 5 judges received per label per round — same blinded diff + rubric, varying only by model: `_blind-eval/Alpha/round1/` (omitted from public release) (`<judge>-judge.json.request.json`).
- **Judge prompt template.** ``scripts/generate-judge-prompt-combined-v2.sh`` (omitted from public release).
- **Methodology and threats to validity.** [`PAPER.md`](../PAPER.md) (§1 methodology, §4 limitations) · [`README.md`](../README.md) · [landing page](https://claude-tool-benchmark.pages.dev/).

## Methodology
- Tools under test: 8
- Blind labels: 40
- Layout: 3 rounds per (artifact, judge) — the canonical run (judge files flat at the label root) plus `round1/` and `round2/` rerun directories. The aggregator reads the label root plus `^round[0-9]+$` subdirs in union; pilot/sample dirs (e.g. `roundcotsample*`) are excluded.
- Judges: opus, grok420, glm51, GPT-5.4, mimo25pro (5-judge panel; each artifact scored 3 times — once per round — by every judge)
- Rubric: 20 items × 0–10 pts = 200 pt max
- Canonical score per judge file: `sum(scores.values())` (not the stored `total` field)
- Reported tool mean: **weighted mean of per-judge means** (weights: opus×3, GPT-5.4×2, grok420×1, glm51×1, mimo25pro×1)
- Total judgments aggregated: 600

## Caveats / threats to validity

- **Judge weights are pre-registered, not derived.** The 3 / 2 / 1 / 1 / 1 weighting is stored as `judges.*.weight` in `versions.lock.json` (committed 2026-05-12) and reflects the operator's prior trust in the Anthropic (opus) and OpenAI (`GPT-5.4`) reviewers. An equal-weight aggregation is emitted alongside this report as `final-report.equal-weight.md`; the in-report `Pooled Mean` column is also the equal-weight comparator and lets readers verify rank-stability without leaving this file.
- **Judge scorer asymmetries.** `GPT-5.4` is consistently the harshest scorer in the panel (lowest mean across labels). `mimo25pro` is the most lenient and occasionally emits 200/200 saturations; its weight of 1 dilutes the impact, but right-tail scores should be read in that context.
- **σ decomposition.** The per-tool standard deviation column is split into `within_σ` (within-judge spread — mean of the per-judge stdev across the 15 samples per (tool, judge): 5 trials × 3 rounds) and `between_σ` (judge base-rate spread — stdev of per-judge means). `within_σ` now bundles trial-to-trial output variance with round-to-round judge-sampler variance; the latter is small where temperature=0 is honored (OpenRouter, OpenCode Go) and absorbed in `within_σ` where it is not (Claude CLI, OpenAI `/v1/responses`). Within > between would indicate the tool's output (combined with sampler drift) is unstable; the reverse means most variance is judge base-rate disagreement.
- **Judge sampling not pinned.** Temperature is fixed to 0 where the provider exposes it (OpenRouter, OpenCode Go). Claude CLI and OpenAI `/v1/responses` do not expose temperature/seed, so residual sampler variance is absorbed in per-judge σ rather than eliminated.
- **R1 mechanical-fact override.** Rubric items with deterministic answers (e.g. `tsc_errors == 0`) are rewritten post-hoc from `auto-metrics.json` to remove LLM arithmetic / classification drift. Items locked per task: `feature` 12/13/16/20, `bugfix` 14/15, `refactor` 13/14. Pre-override scores are preserved under `scores_pre_r1` on every judged file (`scripts/aggregate-results.sh` runs an idempotent R1 sweep before aggregating).
- **Blind eval is structural, not semantic.** Tool identity is hidden via NATO labels and a path-/content-level scrub of tool-specific directories (`.omc/`, `_bmad/`, `_bmad-output/`, `_bmad-core/`, `docs/bmad/`, `docs/superpowers/`, `plans/`, `.claudekit/`, `.gstack/`, `.superpowers/`, `.compound-engineering/`, `.ecc/`, `CLAUDE.md.original`). `auto-metrics.json` is anonymised by stripping `plugin_versions` and `collected_at`. A skilled judge could still infer identity from idiosyncratic code style; we don't claim semantic anonymity.
- **Cohort span:** 181.0h (2026-05-09 → 2026-05-16). Spans >24h indicate the cohort did not complete within a single day; `scripts/audit-cohort-symmetry.py` flags this as a soft warning. The longest spans in this report stem from the leak-fix re-judge pass (see `docs/RERUN-PRE-PUBLISH.md`).

## Aggregate Scores per Tool

**Column glossary — read this first.** One row per tool; the columns are:

- **Tool** — the setup under test. Eight rows: `bmad`, `claudekit`, `compound`, `ecc`, `gstack`, `omc`, `pure` (no-addon baseline), `superpower`.
- **Weighted Mean** *(bold; canonical rank column)* — weighted average over judges: `(3·opus + 2·`GPT-5.4` + grok420 + glm51 + mimo25pro) / 8`. Weights pre-registered in `versions.lock.json` and reflect operator trust in the Anthropic / OpenAI judges.
- **Pooled Mean** — straight equal-weight average over all 75 judgments (every judge counts the same, 1×). Quick sensitivity check: if Weighted and Pooled order the top tools the same way, the ranking is robust to the weighting scheme. The dedicated `final-report.equal-weight.md` is the full equal-weight comparator.
- **Pooled σ** — overall standard deviation across all 75 judgments (raw score spread before splitting variance sources).
- **within_σ** — within-judge spread. For each judge, compute σ across its 15 samples per tool (5 trials × 3 rounds), then average across the 5 judges. High `within_σ` means the same judge gave the tool different scores across runs — either the tool's output varies trial-to-trial or judge sampler drift (where temperature=0 isn't honored).
- **between_σ** — between-judge spread. Compute each judge's mean for this tool, then take σ across those 5 per-judge means. High `between_σ` means judges systematically disagree (lenience drift). `within_σ` < `between_σ` is the healthy case: most of the noise is judge base-rate, not tool flakiness.
- **N** — total judgments aggregated for this tool. Should equal 75 when complete (5 trials × 5 judges × 3 rounds).
- **n(opus) … n(mimo25pro)** — how many of those judgments came from each judge. In a complete cohort each equals 15 (5 trials × 3 rounds); a lower value exposes a missing or in-progress backfill for that judge (not silently averaged away — the weighted mean drops absent slots from both numerator and denominator).

| Tool | Weighted Mean | Pooled Mean | Pooled σ | within_σ | between_σ | N | n(opus) | n(grok420) | n(glm51) | n(GPT-5.4) | n(mimo25pro) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| ecc | **153.30** | 157.11 | 16.46 | 8.96 | 15.29 | 75 | 15 | 15 | 15 | 15 | 15 |
| pure | **143.13** | 147.44 | 16.05 | 7.51 | 15.72 | 75 | 15 | 15 | 15 | 15 | 15 |
| bmad | **141.33** | 147.65 | 19.99 | 7.02 | 20.81 | 75 | 15 | 15 | 15 | 15 | 15 |
| superpower | **140.16** | 143.68 | 16.95 | 10.06 | 15.14 | 75 | 15 | 15 | 15 | 15 | 15 |
| omc | **139.49** | 143.59 | 19.00 | 10.88 | 17.29 | 75 | 15 | 15 | 15 | 15 | 15 |
| claudekit | **135.04** | 139.07 | 19.67 | 12.75 | 16.83 | 75 | 15 | 15 | 15 | 15 | 15 |
| compound | **134.67** | 140.11 | 19.65 | 13.26 | 15.99 | 75 | 15 | 15 | 15 | 15 | 15 |
| gstack | **131.98** | 137.80 | 25.02 | 18.35 | 19.41 | 75 | 15 | 15 | 15 | 15 | 15 |

## Inter-rater agreement (Krippendorff α)

**α = 0.124** (interval level, judges as coders, blind labels as units, N=40 labels × 5 judges = 200 observations).

Krippendorff α measures how much the 5 judges agree on the *absolute* score for the same artifact. Conventional thresholds (Krippendorff 2011): α ≥ 0.800 supports firm conclusions; ≥ 0.667 supports tentative ones; < 0.667 is unreliable for absolute claims. **Caveat:** α punishes per-judge lenience drift hard — `GPT-5.4` (panel-low) and mimo25pro (panel-high) are far apart on most artifacts even when they *order* tools the same way. The benchmark's weighted-mean aggregation is less sensitive to any single judge's base rate, but it does not make raw scores robust to per-judge lenience drift — the per-judge z-normalized table below is the actual mitigation for that; α surfaces the drift as a separate honesty metric.

**Upper-bound caveat:** α is computed on each (label, judge)'s *mean across rounds*, so round-to-round judge-sampler noise is averaged out before the reliability calculation. The reported α therefore **overstates** raw round-level inter-judge agreement — true per-round α is lower than the values shown here. Read these as a generous ceiling, not a point estimate.

## Power analysis & detection threshold (MDE)

**MDE ≈ 19.33 pts** at α=0.05 (two-sided), power=0.80, n=5 trials per arm, σ_pool=9.72 pts (pooled across 8 tools using trial-level weighted means).

Two tool means whose gap is below MDE cannot be statistically distinguished at the standard α=0.05 / 80%-power threshold. The current cohort uses **n=5 trials per cell**, which is the binding constraint — judgments within a cell are correlated (same judge across rounds, same trial across rounds), so trials are the real degree of freedom.

- **Rank-1 lead:** 10.17 pts → **below MDE — read as a tie**
- **Gaps rank-1 vs each lower tool** (✓ = exceeds MDE, ⚠ = below MDE):
    - ecc − pure: **10.17 pts** ⚠
    - ecc − bmad: **11.97 pts** ⚠
    - ecc − superpower: **13.14 pts** ⚠
    - ecc − omc: **13.81 pts** ⚠
    - ecc − claudekit: **18.26 pts** ⚠
    - ecc − compound: **18.63 pts** ⚠
    - ecc − gstack: **21.32 pts** ✓

**Implication for this cohort:** at n=5 trials per cell, every per-task rank-1 lead falls below MDE (per-task MDEs and σ_pool for all three tasks are in `results/power-analysis.json`) — the top cluster is a statistical tie, not a ranking. The α/2 critical value is the exact Student-t quantile for df=2(n-1)=8 (≈2.306), not the normal z=1.96 — at n=5 this enlarges every MDE by ~12% (feature ≈19.33, bugfix ≈22.17, refactor ≈44.02). Under the corrected threshold the **only** gap that clears its task MDE anywhere in the corpus is `ecc`−`gstack` on `feature` (≈21.3 vs the 19.33 feature MDE); the previously-cited `ecc`−`claudekit` (≈18.3) and `ecc`−`compound` (≈18.6) feature gaps fall **below** MDE under the exact-t critical and are no longer treated as separations. No rank-1 lead on any task clears MDE; no gap on `bugfix` or `refactor` clears its own task MDE. Trial-to-trial variance (not judge noise) is the binding constraint: the n=3→n=5 expansion *raised* σ_pool on every task, so MDE did not follow the expected 1/√n drop (refactor worsened sharply, driven by `gstack`'s trial-4 refactor diff scoring ≈36/200 against ~178 on its other four). No family-wise correction is applied to the ≥21 pairwise gap tests — they are descriptive detection-threshold comparisons, not confirmatory hypothesis tests. This is exactly why post-hoc selective reruns are pre-registered as invalid. See `docs/IMPROVEMENT-PLAN-NEXT-COHORT.md`.

## Outlier audit & rerun verdict

Round-level outlier check per the pre-registered rerun protocol (`CLAUDE.md` § Rerun): a round-judgment flags when `|score − median(other rounds)| > 15 pts AND > 1.41 × spread(other rounds)` (≈ 2σ on the 2 remaining samples).

- **Outlier rate:** **25 / 600** round-judgments = **4.17%** (vs ~5% expected under 2σ chance) — point estimate below the ~5% 2σ-chance baseline, but the 95% CI [2.84%, 6.08%] straddles it — the result is consistent with chance, not significantly below it. Note the per-round 2σ trigger did fire on these 25 individual rounds; the rerun verdict below is a class-level judgment, not an absence of tripped triggers.
- **Tier-1 skill failures** (non-baseline tool with skills_invoked = subagent_dispatches = 0): **0** across the **21** t1–t3 cells with a `session-audit.json`. t4–t5 session audits were not collected, so this trigger is evaluated over t1–t3 only (not the full n=5 cohort); no audited cell shows a skill failure.
- **Outliers by judge:** mimo25pro: 11, grok420: 5, glm51: 4, opus: 3, GPT-5.4: 2. Outliers cluster on the panel's lenience-extreme judges (`mimo25pro`, `GPT-5.4`) and on `grok420`'s root-round drift — these are judge-sampler artifacts, not tool artifacts.

Sample flagged rounds (first 5):

| Tool | Trial | Judge | Round | Score | Others | Δ from median |
|---|---|---|---|---|---|---|
| claudekit | t2 | grok420 | root | 163.0 | [141.0, 141.0] | 22.0 |
| claudekit | t2 | mimo25pro | round2 | 120.0 | [139.0, 136.0] | 17.5 |
| claudekit | t3 | opus | round1 | 140.0 | [158.0, 162.0] | 20.0 |
| claudekit | t3 | glm51 | round2 | 134.0 | [147.0, 156.0] | 17.5 |
| claudekit | t3 | mimo25pro | round2 | 145.0 | [163.0, 162.0] | 17.5 |

**Rerun verdict: no action.** No Tier-1 (skill failure, t1–t3 audited) or Tier-3 (harness bug) triggers fired. The Tier-2 per-round 2σ trigger did fire on the individual rounds counted above, but the *aggregate* outlier rate is statistically consistent with the 2σ-chance baseline (point estimate at/below ~5%, 95% CI overlapping it), so this is treated as a class-level no-action decision rather than per-round re-rolling. Selectively re-rolling the flagged rounds would bias the cohort toward the mean (extreme values re-roll closer to median while in-distribution values stay), shrinking the cohort's apparent variance without removing real noise. The correct fix for round-level noise is **deterministic judge sampling** (caveat 09); the correct fix for trial-level variance is **more trials per cell** (see `docs/IMPROVEMENT-PLAN-NEXT-COHORT.md` item #1).

## Robust-statistics sensitivity (median / trimmed-mean companion)

Sensitivity view: per-tool **median** and **trimmed mean** (drop hi/lo) of the 5 trial-level weighted means, instead of the arithmetic mean used above. Rank-1 is invariant on every task under mean / median / trimmed; the largest middle-rank shift in this corpus is `gstack` refactor (rank-8 → rank-7 under median, driven by one bad trial — the canonical mean correctly retains it). Full table: [`robust-statistics-companion.md`](robust-statistics-companion.md); raw figures in [`robust-statistics.json`](robust-statistics.json); recompute with `scripts/compute-robust-stats.py`. *Not* the pre-registered primary statistic — a sensitivity view alongside the equal-weight companion.

## Per-judge z-normalized sensitivity

Tool ordering when each judge is z-normalized (`(score − judge_mean) / judge_sd`) before averaging — cancels per-judge lenience drift so each judge contributes ordering signal, not absolute lenience. Useful as a sensitivity check against the canonical Weighted Mean: rank-1 should be invariant under both rules.

| Tool | Judge-Z mean | Weighted-Mean rank | Judge-Z rank |
|---|---|---|---|
| ecc | +0.948 | 1 | **1** |
| bmad | +0.234 | 3 | **2** (Δ +1) |
| pure | +0.222 | 2 | **3** (Δ -1) |
| superpower | -0.067 | 4 | **4** |
| omc | -0.072 | 5 | **5** |
| compound | -0.341 | 7 | **6** (Δ +1) |
| claudekit | -0.412 | 6 | **7** (Δ -1) |
| gstack | -0.512 | 8 | **8** |

`Δ` is `Weighted-Mean rank − Judge-Z rank`. Δ=0 means the canonical and z-normalized rules agree; |Δ|≥2 means the ordering moves materially under judge normalization (worth investigating).

## Comparative-rank validity probe (Opus-1M, parallel signal)

**Spearman ρ vs panel weighted-mean rank: 0.571** (n_cells = 25 comparative-judge runs; 2 tools flagged with |Δrank| ≥ 2)

Independent of the per-artifact panel above: one Opus-1M call ranks all 8 tools' artifacts for a (task, trial) cell side-by-side, then averaged across 5 rounds with fresh per-round Greek-suffix labels and shuffled prompt order. **Comparative-rank is a parallel signal — it does NOT enter the weighted mean.** High ρ means both judgment regimes agree on tool ordering; low or negative ρ flags a calibration disagreement worth investigating (panel sees artifacts in isolation and can drift; comparative sees the cohort range and recalibrates each round). This in-report table is the **Opus-1M lane only**, shown as a quick signal; the full two-lane (Opus-1M + GPT-5.4) triangulation with all three pairwise Spearman ρ per task lives in `_comparative-eval/_triangulation.md` (omitted from public release). Methodology and per-round outputs: `_comparative-eval/` (omitted from public release).

**Blinding observations volunteered by Opus.** Across the 75 Opus-1M comparative rounds (5 trials × 5 rounds × 3 tasks; the **feature**-task subset shown here), about one third of rounds reported weak observations (low-confidence pattern-matching on scaffold density, in-code comment style, planning-vocabulary leaks, or formatter-hook reflow on untouched code). **None constituted firm tool identification.** Specific quoted leak strings are omitted from this public release.


| Tool | Panel rank | Comparative rank | Δ | Panel weighted-mean | Comparative mean-rank ± σ | n obs |
|---|---|---|---|---|---|---|
| ecc | 1 | **1** | 0 | 153.30 | 2.56 ± 1.53 | 25 |
| claudekit | 6 | **2** | +4 ⚠ | 135.04 | 3.00 ± 1.85 | 25 |
| pure | 2 | **3** | -1 | 143.13 | 3.64 ± 1.91 | 25 |
| omc | 5 | **4** | +1 | 139.49 | 4.04 ± 2.17 | 25 |
| superpower | 4 | **5** | -1 | 140.16 | 4.20 ± 2.29 | 25 |
| compound | 7 | **6** | +1 | 134.67 | 5.72 ± 1.79 | 25 |
| bmad | 3 | **7** | -4 ⚠ | 141.33 | 6.12 ± 1.09 | 25 |
| gstack | 8 | **8** | 0 | 131.98 | 6.72 ± 1.79 | 25 |

`Δ = panel_rank − comparative_rank`. Positive Δ means comparative ranks the tool higher than the panel; ⚠ marks |Δ| ≥ 2.

## Ranking (Weighted Mean)

1. **ecc** — 153.30/200
2. **pure** — 143.13/200
3. **bmad** — 141.33/200
4. **superpower** — 140.16/200
5. **omc** — 139.49/200
6. **claudekit** — 135.04/200
7. **compound** — 134.67/200
8. **gstack** — 131.98/200

## Per-Trial Breakdown

Weighted-mean score for each individual trial (same 3·opus + 2·`GPT-5.4` + others weighting as the canonical column). Surfaces trial-to-trial drift inside a tool — a wide spread means the cohort mean is averaging over disagreeing runs rather than stable ones. The Δ column is `max − min` across all trials; ≥ 15 pts is flagged as **noisy** (the tool's output is bimodal at this sample size).

| Tool | t1 | t2 | t3 | t4 | t5 | Δ (max − min) | Flag | Skills (t1/t2/t3/t4/t5) | Subagents (t1/t2/t3/t4/t5) |
|---|---|---|---|---|---|---|---|---|---|
| ecc | 149.67 | 152.75 | 144.50 | 164.83 | 154.75 | 20.33 | **noisy** | 18/18/46/—/— | 0/0/5/—/— |
| pure | 140.00 | 146.79 | 139.71 | 143.96 | 145.21 | 7.08 |  | 0/0/0/—/— | 1/1/1/—/— |
| bmad | 140.12 | 142.79 | 140.25 | 137.46 | 146.04 | 8.58 |  | 181/215/221/—/— | 0/2/1/—/— |
| superpower | 144.29 | 148.83 | 138.38 | 129.42 | 139.88 | 19.42 | **noisy** | 909/1498/441/—/— | 18/28/9/—/— |
| omc | 146.00 | 126.08 | 134.21 | 147.46 | 143.71 | 21.37 | **noisy** | 185/455/1100/—/— | 11/8/13/—/— |
| claudekit | 135.62 | 115.54 | 146.54 | 141.38 | 136.12 | 31.00 | **noisy** | 228/300/823/—/— | 0/2/5/—/— |
| compound | 141.58 | 144.29 | 140.12 | 120.37 | 126.96 | 23.92 | **noisy** | 106/406/151/—/— | 0/5/0/—/— |
| gstack | 111.67 | 129.12 | 123.75 | 157.71 | 137.67 | 46.04 | **noisy** | 49/76/135/—/— | 2/2/4/—/— |

Reading: a `noisy` flag here means the cohort mean for that tool is averaging over runs that disagree by ≥ 15 weighted pts. Use this column to read the headline rank with calibration — a tool whose trials cluster tightly is a more reliable signal than one with a wide spread. The pre-registered rerun protocol triggers on **per-round** outliers within a trial (not trial-to-trial), so a wide Δ here is real tool variance, not a harness artifact.

**Skills (t1/t2/t3/t4/t5)** = number of distinct skill / slash-command invocations per trial (from `session-audit.json` → `skills_invoked`). **Subagents (t1/t2/t3/t4/t5)** = sub-agent dispatches per trial. A tool whose primary mechanism is a skill/sub-agent and reads `0` for a trial likely failed to invoke its mechanism — under the rerun protocol this is a Tier-1 trigger ("Skill failure"), distinct from the statistical-outlier trigger. Cross-reference these counts when a trial scores far from its siblings.

## Per-Judge Means

Each cell is one judge's mean score for one tool, averaged over that judge's 15 samples (5 trials × 3 rounds). The columns:

- **Tool** — same 8 setups as above, ordered by Weighted Mean (rank-1 first).
- **opus / grok420 / glm51 / GPT-5.4 / mimo25pro** — that judge's mean score (0–200 rubric) for this tool. Reads vertically to expose **judge base-rate effects**: `GPT-5.4` consistently scores ~20–30 pts below the panel mean (harshest in the panel), `mimo25pro` ~5–15 pts above (most lenient, occasionally saturates at 200). Reads horizontally to see whether the judges agree on the ordering: if a tool is rank-1 under one judge and rank-7 under another, the consensus is weak.

| Tool | opus | grok420 | glm51 | gpt54pro | mimo25pro |
|---|---|---|---|---|---|
| ecc | 154.5 | 168.3 | 161.5 | 131.9 | 169.3 |
| pure | 142.5 | 163.5 | 151.3 | 122.9 | 157.0 |
| bmad | 138.7 | 164.5 | 159.3 | 115.1 | 160.8 |
| superpower | 142.5 | 154.8 | 150.3 | 117.9 | 152.9 |
| omc | 141.7 | 158.0 | 149.2 | 114.7 | 154.4 |
| claudekit | 135.9 | 156.8 | 138.7 | 113.1 | 150.7 |
| compound | 129.3 | 155.9 | 144.7 | 118.1 | 152.5 |
| gstack | 129.2 | 156.7 | 143.1 | 108.5 | 151.5 |

