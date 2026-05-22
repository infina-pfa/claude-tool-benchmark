# refactor — Per-Task Aggregation

Generated: 2026-05-19T04:05:40Z

## Inputs and source artifacts

Everything fed into this aggregation is committed; no private state.

- **Trial input (task PRD).** The exact prompt every tool saw for this task: `_blind-eval/prd.md` (omitted from public release).
- **Per-tool prompt prefix.** The tool-specific slash command bound to that PRD lives in [`scripts/manual-bench.sh`](../../scripts/manual-bench.sh).
- **Judge input (verbatim request payload).** What each of the 5 judges received per label per round — same blinded diff + rubric, varying only by model: `_blind-eval/Alpha/round1/` (omitted from public release) (`<judge>-judge.json.request.json`).
- **Judge prompt template.** ``scripts/generate-judge-prompt-combined-v2.sh`` (omitted from public release).
- **Methodology and threats to validity.** [`PAPER.md`](../../PAPER.md) (§1 methodology, §4 limitations) · [`README.md`](../../README.md) · [landing page](https://claude-tool-benchmark.pages.dev/).

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
- **Cohort span:** 146.6h (2026-05-10 → 2026-05-16). Spans >24h indicate the cohort did not complete within a single day; `scripts/audit-cohort-symmetry.py` flags this as a soft warning. The longest spans in this report stem from the leak-fix re-judge pass (see `docs/RERUN-PRE-PUBLISH.md`).

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
| pure | **180.19** | 182.63 | 13.10 | 4.44 | 13.73 | 75 | 15 | 15 | 15 | 15 | 15 |
| claudekit | **178.04** | 180.76 | 16.25 | 5.29 | 17.01 | 75 | 15 | 15 | 15 | 15 | 15 |
| bmad | **177.74** | 180.08 | 14.86 | 5.48 | 15.28 | 75 | 15 | 15 | 15 | 15 | 15 |
| superpower | **177.56** | 180.51 | 14.74 | 5.09 | 15.39 | 75 | 15 | 15 | 15 | 15 | 15 |
| compound | **174.42** | 177.03 | 15.96 | 6.04 | 16.40 | 75 | 15 | 15 | 15 | 15 | 15 |
| ecc | **173.61** | 176.57 | 16.91 | 8.71 | 16.12 | 75 | 15 | 15 | 15 | 15 | 15 |
| omc | **170.11** | 173.83 | 17.50 | 7.43 | 17.52 | 75 | 15 | 15 | 15 | 15 | 15 |
| gstack | **144.92** | 147.92 | 58.70 | 58.43 | 12.52 | 75 | 15 | 15 | 15 | 15 | 15 |

## Inter-rater agreement (Krippendorff α)

**α = 0.626** (interval level, judges as coders, blind labels as units, N=40 labels × 5 judges = 200 observations).

Krippendorff α measures how much the 5 judges agree on the *absolute* score for the same artifact. Conventional thresholds (Krippendorff 2011): α ≥ 0.800 supports firm conclusions; ≥ 0.667 supports tentative ones; < 0.667 is unreliable for absolute claims. **Caveat:** α punishes per-judge lenience drift hard — `GPT-5.4` (panel-low) and mimo25pro (panel-high) are far apart on most artifacts even when they *order* tools the same way. The benchmark's weighted-mean aggregation is less sensitive to any single judge's base rate, but it does not make raw scores robust to per-judge lenience drift — the per-judge z-normalized table below is the actual mitigation for that; α surfaces the drift as a separate honesty metric.

**Upper-bound caveat:** α is computed on each (label, judge)'s *mean across rounds*, so round-to-round judge-sampler noise is averaged out before the reliability calculation. The reported α therefore **overstates** raw round-level inter-judge agreement — true per-round α is lower than the values shown here. Read these as a generous ceiling, not a point estimate.

## Power analysis & detection threshold (MDE)

**MDE ≈ 44.02 pts** at α=0.05 (two-sided), power=0.80, n=5 trials per arm, σ_pool=22.13 pts (pooled across 8 tools using trial-level weighted means).

Two tool means whose gap is below MDE cannot be statistically distinguished at the standard α=0.05 / 80%-power threshold. The current cohort uses **n=5 trials per cell**, which is the binding constraint — judgments within a cell are correlated (same judge across rounds, same trial across rounds), so trials are the real degree of freedom.

- **Rank-1 lead:** 2.15 pts → **below MDE — read as a tie**
- **Gaps rank-1 vs each lower tool** (✓ = exceeds MDE, ⚠ = below MDE):
    - pure − claudekit: **2.15 pts** ⚠
    - pure − bmad: **2.45 pts** ⚠
    - pure − superpower: **2.63 pts** ⚠
    - pure − compound: **5.78 pts** ⚠
    - pure − ecc: **6.58 pts** ⚠
    - pure − omc: **10.08 pts** ⚠
    - pure − gstack: **35.27 pts** ⚠

**Implication for this cohort:** at n=5 trials per cell, every per-task rank-1 lead falls below MDE (per-task MDEs and σ_pool for all three tasks are in `results/power-analysis.json`) — the top cluster is a statistical tie, not a ranking. The α/2 critical value is the exact Student-t quantile for df=2(n-1)=8 (≈2.306), not the normal z=1.96 — at n=5 this enlarges every MDE by ~12% (feature ≈19.33, bugfix ≈22.17, refactor ≈44.02). Under the corrected threshold the **only** gap that clears its task MDE anywhere in the corpus is `ecc`−`gstack` on `feature` (≈21.3 vs the 19.33 feature MDE); the previously-cited `ecc`−`claudekit` (≈18.3) and `ecc`−`compound` (≈18.6) feature gaps fall **below** MDE under the exact-t critical and are no longer treated as separations. No rank-1 lead on any task clears MDE; no gap on `bugfix` or `refactor` clears its own task MDE. Trial-to-trial variance (not judge noise) is the binding constraint: the n=3→n=5 expansion *raised* σ_pool on every task, so MDE did not follow the expected 1/√n drop (refactor worsened sharply, driven by `gstack`'s trial-4 refactor diff scoring ≈36/200 against ~178 on its other four). No family-wise correction is applied to the ≥21 pairwise gap tests — they are descriptive detection-threshold comparisons, not confirmatory hypothesis tests. This is exactly why post-hoc selective reruns are pre-registered as invalid. See `docs/IMPROVEMENT-PLAN-NEXT-COHORT.md`.

## Outlier audit & rerun verdict

Round-level outlier check per the pre-registered rerun protocol (`CLAUDE.md` § Rerun): a round-judgment flags when `|score − median(other rounds)| > 15 pts AND > 1.41 × spread(other rounds)` (≈ 2σ on the 2 remaining samples).

- **Outlier rate:** **8 / 600** round-judgments = **1.33%** (vs ~5% expected under 2σ chance) — below chance (95% CI [0.68%, 2.61%]). Note the per-round 2σ trigger did fire on these 8 individual rounds; the rerun verdict below is a class-level judgment, not an absence of tripped triggers.
- **Tier-1 skill failures** (non-baseline tool with skills_invoked = subagent_dispatches = 0): **0** across the **21** t1–t3 cells with a `session-audit.json`. t4–t5 session audits were not collected, so this trigger is evaluated over t1–t3 only (not the full n=5 cohort); no audited cell shows a skill failure.
- **Outliers by judge:** mimo25pro: 5, opus: 1, grok420: 1, glm51: 1. Outliers cluster on the panel's lenience-extreme judges (`mimo25pro`, `GPT-5.4`) and on `grok420`'s root-round drift — these are judge-sampler artifacts, not tool artifacts.

Sample flagged rounds (first 5):

| Tool | Trial | Judge | Round | Score | Others | Δ from median |
|---|---|---|---|---|---|---|
| compound | t3 | mimo25pro | root | 200.0 | [180.0, 179.0] | 20.5 |
| bmad | t3 | mimo25pro | round2 | 176.0 | [200.0, 198.0] | 23.0 |
| compound | t2 | opus | root | 170.0 | [189.0, 186.0] | 17.5 |
| bmad | t4 | mimo25pro | root | 179.0 | [192.0, 200.0] | 17.0 |
| omc | t5 | mimo25pro | round1 | 176.0 | [193.0, 198.0] | 19.5 |

**Rerun verdict: no action.** No Tier-1 (skill failure, t1–t3 audited) or Tier-3 (harness bug) triggers fired. The Tier-2 per-round 2σ trigger did fire on the individual rounds counted above, but the *aggregate* outlier rate is statistically consistent with the 2σ-chance baseline (point estimate at/below ~5%, 95% CI overlapping it), so this is treated as a class-level no-action decision rather than per-round re-rolling. Selectively re-rolling the flagged rounds would bias the cohort toward the mean (extreme values re-roll closer to median while in-distribution values stay), shrinking the cohort's apparent variance without removing real noise. The correct fix for round-level noise is **deterministic judge sampling** (caveat 09); the correct fix for trial-level variance is **more trials per cell** (see `docs/IMPROVEMENT-PLAN-NEXT-COHORT.md` item #1).

## Robust-statistics sensitivity (median / trimmed-mean companion)

The canonical Weighted Mean above is sensitive to single-trial outliers. The most consequential example is in this report: `gstack` t4 weighted mean **36.42** vs **153.79–181.67** on its other four trials drags the canonical `gstack` figure down to 144.92 — under the **median** (174.58) `gstack` is rank-7 rather than rank-8, and the rank-1-to-rank-8 spread collapses from 35.3 pts to ~5.6 pts. Pure rank-1 is invariant under mean / median / trimmed mean on every task. Full per-(task, tool) table: [`../robust-statistics-companion.md`](../robust-statistics-companion.md); raw figures in [`../robust-statistics.json`](../robust-statistics.json); recompute with `scripts/compute-robust-stats.py`. *Not* the pre-registered primary statistic — a sensitivity view alongside the equal-weight companion.

## Per-judge z-normalized sensitivity

Tool ordering when each judge is z-normalized (`(score − judge_mean) / judge_sd`) before averaging — cancels per-judge lenience drift so each judge contributes ordering signal, not absolute lenience. Useful as a sensitivity check against the canonical Weighted Mean: rank-1 should be invariant under both rules.

| Tool | Judge-Z mean | Weighted-Mean rank | Judge-Z rank |
|---|---|---|---|
| pure | +0.344 | 1 | **1** |
| claudekit | +0.243 | 2 | **2** |
| superpower | +0.243 | 4 | **3** (Δ +1) |
| bmad | +0.225 | 3 | **4** (Δ -1) |
| compound | +0.083 | 5 | **5** |
| ecc | +0.068 | 6 | **6** |
| omc | -0.057 | 7 | **7** |
| gstack | -1.150 | 8 | **8** |

`Δ` is `Weighted-Mean rank − Judge-Z rank`. Δ=0 means the canonical and z-normalized rules agree; |Δ|≥2 means the ordering moves materially under judge normalization (worth investigating).

## Comparative-rank validity probe (Opus-1M, parallel signal)

**Spearman ρ vs panel weighted-mean rank: 0.310** (n_cells = 25 comparative-judge runs; 5 tools flagged with |Δrank| ≥ 2)

Independent of the per-artifact panel above: one Opus-1M call ranks all 8 tools' artifacts for a (task, trial) cell side-by-side, then averaged across 5 rounds with fresh per-round Greek-suffix labels and shuffled prompt order. **Comparative-rank is a parallel signal — it does NOT enter the weighted mean.** High ρ means both judgment regimes agree on tool ordering; low or negative ρ flags a calibration disagreement worth investigating (panel sees artifacts in isolation and can drift; comparative sees the cohort range and recalibrates each round). This in-report table is the **Opus-1M lane only**, shown as a quick signal; the full two-lane (Opus-1M + GPT-5.4) triangulation with all three pairwise Spearman ρ per task lives in `_comparative-eval/_triangulation.md` (omitted from public release). Methodology and per-round outputs: `_comparative-eval/` (omitted from public release).

**[!] Blinding observations volunteered by Opus** (rounds where the judge noted potentially-identifying patterns — treat as soft warnings):

- t1/round2: Low confidence, no firm identification. R2-Gamma's five per-app idempotent migrations and R2-Eta's full usecase-port plumbing suggest heavier multi-agent orchestration setups, but I cannot map these to specific named tools reliably enough t
- t1/round4: R4-Eta's pervasive Prettier-style reformatting (trailing-comma removal, line rewrapping) across untouched code suggests a format-on-save/lint hook in that tool's harness rather than deliberate edits — a weak environmental signature, not a c
- t3/round4: No confident tool-level identification. Weak signal only: R4-Delta's pervasive prettier-style reflow of untouched code suggests a harness that auto-formats broadly, but this does not map to a specific named tool/setup.
- t3/round5: No strong identity leak. Migration timestamps and comment styles vary but are generic; no label maps confidently to a specific tool/setup.
- t5/round2: Minor: R2-Theta's migration path 'apps/infina-savings-service' and eslint-disable @nx/enforce-module-boundaries deep relative import expose real repo/app naming, but this signals coding behavior, not a specific tool identity. No confident t

| Tool | Panel rank | Comparative rank | Δ | Panel weighted-mean | Comparative mean-rank ± σ | n obs |
|---|---|---|---|---|---|---|
| pure | 1 | **1** | 0 | 180.19 | 1.84 ± 0.69 | 25 |
| bmad | 3 | **2** | +1 | 177.74 | 4.20 ± 1.91 | 25 |
| gstack | 8 | **3** | +5 ⚠ | 144.92 | 4.52 ± 3.11 | 25 |
| omc | 7 | **4** | +3 ⚠ | 170.11 | 4.52 ± 2.24 | 25 |
| claudekit | 2 | **5** | -3 ⚠ | 178.04 | 4.56 ± 2.02 | 25 |
| compound | 5 | **6** | -1 | 174.42 | 4.68 ± 1.70 | 25 |
| superpower | 4 | **7** | -3 ⚠ | 177.56 | 5.20 ± 1.68 | 25 |
| ecc | 6 | **8** | -2 ⚠ | 173.61 | 6.48 ± 1.73 | 25 |

`Δ = panel_rank − comparative_rank`. Positive Δ means comparative ranks the tool higher than the panel; ⚠ marks |Δ| ≥ 2.

## Ranking (Weighted Mean)

1. **pure** — 180.19/200
2. **claudekit** — 178.04/200
3. **bmad** — 177.74/200
4. **superpower** — 177.56/200
5. **compound** — 174.42/200
6. **ecc** — 173.61/200
7. **omc** — 170.11/200
8. **gstack** — 144.92/200

## Per-Trial Breakdown

Weighted-mean score for each individual trial (same 3·opus + 2·`GPT-5.4` + others weighting as the canonical column). Surfaces trial-to-trial drift inside a tool — a wide spread means the cohort mean is averaging over disagreeing runs rather than stable ones. The Δ column is `max − min` across all trials; ≥ 15 pts is flagged as **noisy** (the tool's output is bimodal at this sample size).

| Tool | t1 | t2 | t3 | t4 | t5 | Δ (max − min) | Flag | Skills (t1/t2/t3/t4/t5) | Subagents (t1/t2/t3/t4/t5) |
|---|---|---|---|---|---|---|---|---|---|
| pure | 180.17 | 183.17 | 179.58 | 178.62 | 179.42 | 4.54 |  | 0/0/0/—/— | 1/1/2/—/— |
| claudekit | 178.21 | 177.21 | 180.67 | 177.33 | 176.79 | 3.88 |  | 108/198/196/—/— | 0/0/1/—/— |
| bmad | 177.96 | 179.83 | 179.08 | 175.83 | 176.00 | 4.00 |  | 208/211/94/—/— | 1/1/2/—/— |
| superpower | 182.17 | 177.67 | 178.46 | 175.29 | 174.21 | 7.96 |  | 24/64/88/—/— | 0/1/1/—/— |
| compound | 175.29 | 174.88 | 173.96 | 169.88 | 178.08 | 8.21 |  | 206/141/158/—/— | 0/0/0/—/— |
| ecc | 179.21 | 173.92 | 178.96 | 175.46 | 160.50 | 18.71 | **noisy** | 46/37/56/—/— | 1/1/1/—/— |
| omc | 171.33 | 160.50 | 175.75 | 173.50 | 169.46 | 15.25 | **noisy** | 547/468/164/—/— | 12/15/10/—/— |
| gstack | 174.58 | 153.79 | 181.67 | 36.42 | 178.12 | 145.25 | **noisy** | 406/72/54/—/— | 4/2/2/—/— |

Reading: a `noisy` flag here means the cohort mean for that tool is averaging over runs that disagree by ≥ 15 weighted pts. Use this column to read the headline rank with calibration — a tool whose trials cluster tightly is a more reliable signal than one with a wide spread. The pre-registered rerun protocol triggers on **per-round** outliers within a trial (not trial-to-trial), so a wide Δ here is real tool variance, not a harness artifact.

**Skills (t1/t2/t3/t4/t5)** = number of distinct skill / slash-command invocations per trial (from `session-audit.json` → `skills_invoked`). **Subagents (t1/t2/t3/t4/t5)** = sub-agent dispatches per trial. A tool whose primary mechanism is a skill/sub-agent and reads `0` for a trial likely failed to invoke its mechanism — under the rerun protocol this is a Tier-1 trigger ("Skill failure"), distinct from the statistical-outlier trigger. Cross-reference these counts when a trial scores far from its siblings.

## Per-Judge Means

Each cell is one judge's mean score for one tool, averaged over that judge's 15 samples (5 trials × 3 rounds). The columns:

- **Tool** — same 8 setups as above, ordered by Weighted Mean (rank-1 first).
- **opus / grok420 / glm51 / GPT-5.4 / mimo25pro** — that judge's mean score (0–200 rubric) for this tool. Reads vertically to expose **judge base-rate effects**: `GPT-5.4` consistently scores ~20–30 pts below the panel mean (harshest in the panel), `mimo25pro` ~5–15 pts above (most lenient, occasionally saturates at 200). Reads horizontally to see whether the judges agree on the ordering: if a tool is rank-1 under one judge and rank-7 under another, the consensus is weak.

| Tool | opus | grok420 | glm51 | gpt54pro | mimo25pro |
|---|---|---|---|---|---|
| pure | 184.7 | 185.8 | 189.8 | 158.9 | 193.9 |
| claudekit | 184.5 | 184.0 | 188.3 | 151.5 | 195.5 |
| bmad | 184.1 | 182.9 | 189.2 | 153.4 | 190.8 |
| superpower | 181.9 | 186.1 | 186.5 | 154.1 | 193.9 |
| compound | 180.6 | 180.9 | 182.3 | 149.0 | 192.3 |
| ecc | 178.7 | 182.8 | 182.8 | 148.7 | 189.9 |
| omc | 173.9 | 182.7 | 179.8 | 144.0 | 188.8 |
| gstack | 146.5 | 155.7 | 154.3 | 126.7 | 156.4 |


## Provenance Defects (2)

Files whose internal `judge` field disagrees with the filename slot the aggregator dispatched by. The score is still counted (not retroactively pulled); listed here for transparency.

- `_blind-eval/Juliet/round1/gpt54pro-judge.json` — slot `gpt54pro` but `.judge` = `openai-o3`
- `_blind-eval/Xray/round2/gpt54pro-judge.json` — slot `gpt54pro` but `.judge` = `gpt-5`
