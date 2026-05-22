# bugfix — Per-Task Aggregation

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
- **Cohort span:** 149.7h (2026-05-10 → 2026-05-16). Spans >24h indicate the cohort did not complete within a single day; `scripts/audit-cohort-symmetry.py` flags this as a soft warning. The longest spans in this report stem from the leak-fix re-judge pass (see `docs/RERUN-PRE-PUBLISH.md`).

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
| claudekit | **178.93** | 181.53 | 14.33 | 11.42 | 9.35 | 75 | 15 | 15 | 15 | 15 | 15 |
| ecc | **172.31** | 175.40 | 17.20 | 13.54 | 11.70 | 75 | 15 | 15 | 15 | 15 | 15 |
| pure | **169.53** | 172.03 | 14.64 | 12.05 | 9.58 | 75 | 15 | 15 | 15 | 15 | 15 |
| superpower | **166.41** | 169.43 | 14.03 | 7.48 | 13.28 | 75 | 15 | 15 | 15 | 15 | 15 |
| compound | **166.25** | 169.33 | 13.79 | 9.57 | 11.27 | 75 | 15 | 15 | 15 | 15 | 15 |
| bmad | **165.72** | 169.13 | 17.15 | 12.75 | 12.94 | 75 | 15 | 15 | 15 | 15 | 15 |
| omc | **164.80** | 167.97 | 20.35 | 15.66 | 13.74 | 75 | 15 | 15 | 15 | 15 | 15 |
| gstack | **159.97** | 164.69 | 17.18 | 9.13 | 16.12 | 75 | 15 | 15 | 15 | 15 | 15 |

## Inter-rater agreement (Krippendorff α)

**α = 0.284** (interval level, judges as coders, blind labels as units, N=40 labels × 5 judges = 200 observations).

Krippendorff α measures how much the 5 judges agree on the *absolute* score for the same artifact. Conventional thresholds (Krippendorff 2011): α ≥ 0.800 supports firm conclusions; ≥ 0.667 supports tentative ones; < 0.667 is unreliable for absolute claims. **Caveat:** α punishes per-judge lenience drift hard — `GPT-5.4` (panel-low) and mimo25pro (panel-high) are far apart on most artifacts even when they *order* tools the same way. The benchmark's weighted-mean aggregation is less sensitive to any single judge's base rate, but it does not make raw scores robust to per-judge lenience drift — the per-judge z-normalized table below is the actual mitigation for that; α surfaces the drift as a separate honesty metric.

**Upper-bound caveat:** α is computed on each (label, judge)'s *mean across rounds*, so round-to-round judge-sampler noise is averaged out before the reliability calculation. The reported α therefore **overstates** raw round-level inter-judge agreement — true per-round α is lower than the values shown here. Read these as a generous ceiling, not a point estimate.

## Power analysis & detection threshold (MDE)

**MDE ≈ 22.17 pts** at α=0.05 (two-sided), power=0.80, n=5 trials per arm, σ_pool=11.14 pts (pooled across 8 tools using trial-level weighted means).

Two tool means whose gap is below MDE cannot be statistically distinguished at the standard α=0.05 / 80%-power threshold. The current cohort uses **n=5 trials per cell**, which is the binding constraint — judgments within a cell are correlated (same judge across rounds, same trial across rounds), so trials are the real degree of freedom.

- **Rank-1 lead:** 6.62 pts → **below MDE — read as a tie**
- **Gaps rank-1 vs each lower tool** (✓ = exceeds MDE, ⚠ = below MDE):
    - claudekit − ecc: **6.62 pts** ⚠
    - claudekit − pure: **9.40 pts** ⚠
    - claudekit − superpower: **12.53 pts** ⚠
    - claudekit − compound: **12.68 pts** ⚠
    - claudekit − bmad: **13.22 pts** ⚠
    - claudekit − omc: **14.13 pts** ⚠
    - claudekit − gstack: **18.97 pts** ⚠

**Implication for this cohort:** at n=5 trials per cell, every per-task rank-1 lead falls below MDE (per-task MDEs and σ_pool for all three tasks are in `results/power-analysis.json`) — the top cluster is a statistical tie, not a ranking. The α/2 critical value is the exact Student-t quantile for df=2(n-1)=8 (≈2.306), not the normal z=1.96 — at n=5 this enlarges every MDE by ~12% (feature ≈19.33, bugfix ≈22.17, refactor ≈44.02). Under the corrected threshold the **only** gap that clears its task MDE anywhere in the corpus is `ecc`−`gstack` on `feature` (≈21.3 vs the 19.33 feature MDE); the previously-cited `ecc`−`claudekit` (≈18.3) and `ecc`−`compound` (≈18.6) feature gaps fall **below** MDE under the exact-t critical and are no longer treated as separations. No rank-1 lead on any task clears MDE; no gap on `bugfix` or `refactor` clears its own task MDE. Trial-to-trial variance (not judge noise) is the binding constraint: the n=3→n=5 expansion *raised* σ_pool on every task, so MDE did not follow the expected 1/√n drop (refactor worsened sharply, driven by `gstack`'s trial-4 refactor diff scoring ≈36/200 against ~178 on its other four). No family-wise correction is applied to the ≥21 pairwise gap tests — they are descriptive detection-threshold comparisons, not confirmatory hypothesis tests. This is exactly why post-hoc selective reruns are pre-registered as invalid. See `docs/IMPROVEMENT-PLAN-NEXT-COHORT.md`.

## Outlier audit & rerun verdict

Round-level outlier check per the pre-registered rerun protocol (`CLAUDE.md` § Rerun): a round-judgment flags when `|score − median(other rounds)| > 15 pts AND > 1.41 × spread(other rounds)` (≈ 2σ on the 2 remaining samples).

- **Outlier rate:** **22 / 600** round-judgments = **3.67%** (vs ~5% expected under 2σ chance) — point estimate below the ~5% 2σ-chance baseline, but the 95% CI [2.43%, 5.49%] straddles it — the result is consistent with chance, not significantly below it. Note the per-round 2σ trigger did fire on these 22 individual rounds; the rerun verdict below is a class-level judgment, not an absence of tripped triggers.
- **Tier-1 skill failures** (non-baseline tool with skills_invoked = subagent_dispatches = 0): **0** across the **21** t1–t3 cells with a `session-audit.json`. t4–t5 session audits were not collected, so this trigger is evaluated over t1–t3 only (not the full n=5 cohort); no audited cell shows a skill failure.
- **Outliers by judge:** GPT-5.4: 8, grok420: 5, glm51: 4, mimo25pro: 4, opus: 1. Outliers cluster on the panel's lenience-extreme judges (`mimo25pro`, `GPT-5.4`) and on `grok420`'s root-round drift — these are judge-sampler artifacts, not tool artifacts.

Sample flagged rounds (first 5):

| Tool | Trial | Judge | Round | Score | Others | Δ from median |
|---|---|---|---|---|---|---|
| ecc | t3 | grok420 | round2 | 174.0 | [191.0, 189.0] | 16.0 |
| omc | t3 | grok420 | round2 | 174.0 | [193.0, 189.0] | 17.0 |
| omc | t1 | opus | round1 | 155.0 | [167.0, 176.0] | 16.5 |
| omc | t1 | glm51 | round2 | 187.0 | [165.0, 149.0] | 30.0 |
| ecc | t2 | gpt54pro | round2 | 139.0 | [154.0, 155.0] | 15.5 |

**Rerun verdict: no action.** No Tier-1 (skill failure, t1–t3 audited) or Tier-3 (harness bug) triggers fired. The Tier-2 per-round 2σ trigger did fire on the individual rounds counted above, but the *aggregate* outlier rate is statistically consistent with the 2σ-chance baseline (point estimate at/below ~5%, 95% CI overlapping it), so this is treated as a class-level no-action decision rather than per-round re-rolling. Selectively re-rolling the flagged rounds would bias the cohort toward the mean (extreme values re-roll closer to median while in-distribution values stay), shrinking the cohort's apparent variance without removing real noise. The correct fix for round-level noise is **deterministic judge sampling** (caveat 09); the correct fix for trial-level variance is **more trials per cell** (see `docs/IMPROVEMENT-PLAN-NEXT-COHORT.md` item #1).

## Robust-statistics sensitivity (median / trimmed-mean companion)

Sensitivity view: per-tool **median** and **trimmed mean** (drop hi/lo) of the 5 trial-level weighted means, instead of the arithmetic mean used above. Rank-1 is invariant on every task under mean / median / trimmed; the largest middle-rank shift in this corpus is `gstack` refactor (rank-8 → rank-7 under median, driven by one bad trial — the canonical mean correctly retains it). Full table: [`../robust-statistics-companion.md`](../robust-statistics-companion.md); raw figures in [`../robust-statistics.json`](../robust-statistics.json); recompute with `scripts/compute-robust-stats.py`. *Not* the pre-registered primary statistic — a sensitivity view alongside the equal-weight companion.

## Per-judge z-normalized sensitivity

Tool ordering when each judge is z-normalized (`(score − judge_mean) / judge_sd`) before averaging — cancels per-judge lenience drift so each judge contributes ordering signal, not absolute lenience. Useful as a sensitivity check against the canonical Weighted Mean: rank-1 should be invariant under both rules.

| Tool | Judge-Z mean | Weighted-Mean rank | Judge-Z rank |
|---|---|---|---|
| claudekit | +0.810 | 1 | **1** |
| ecc | +0.336 | 2 | **2** |
| pure | +0.033 | 3 | **3** |
| superpower | -0.138 | 4 | **4** |
| compound | -0.161 | 5 | **5** |
| bmad | -0.173 | 6 | **6** |
| omc | -0.234 | 7 | **7** |
| gstack | -0.472 | 8 | **8** |

`Δ` is `Weighted-Mean rank − Judge-Z rank`. Δ=0 means the canonical and z-normalized rules agree; |Δ|≥2 means the ordering moves materially under judge normalization (worth investigating).

## Comparative-rank validity probe (Opus-1M, parallel signal)

**Spearman ρ vs panel weighted-mean rank: -0.405** (n_cells = 25 comparative-judge runs; 5 tools flagged with |Δrank| ≥ 2)

Independent of the per-artifact panel above: one Opus-1M call ranks all 8 tools' artifacts for a (task, trial) cell side-by-side, then averaged across 5 rounds with fresh per-round Greek-suffix labels and shuffled prompt order. **Comparative-rank is a parallel signal — it does NOT enter the weighted mean.** High ρ means both judgment regimes agree on tool ordering; low or negative ρ flags a calibration disagreement worth investigating (panel sees artifacts in isolation and can drift; comparative sees the cohort range and recalibrates each round). This in-report table is the **Opus-1M lane only**, shown as a quick signal; the full two-lane (Opus-1M + GPT-5.4) triangulation with all three pairwise Spearman ρ per task lives in `_comparative-eval/_triangulation.md` (omitted from public release). Methodology and per-round outputs: `_comparative-eval/` (omitted from public release).

**[!] Blinding observations volunteered by Opus** (rounds where the judge noted potentially-identifying patterns — treat as soft warnings):

- t1/round4: No confident identification. Weak, non-actionable signal only: R4-Zeta's unusually large multi-file footprint (639+/270-) suggests a heavier agentic harness, but this is speculative and I did not rank on suspected identity.
- t2/round2: No confident identification. Theta's large multi-file churn (776/274, 10 files) and Beta's cross-cutting shared-policy refactor suggest heavier-orchestration tooling, but I cannot map either to a specific named tool with confidence, so I am
- t3/round1: R1-Theta's large multi-file rewrite (10 files, +737/-274) is characteristic of a heavier autonomous-orchestration tool, but this is weak speculation, not a confident identification. No other label exposed identifying style.
- t5/round3: Low confidence. Gamma's 6-file/710-line footprint suggests a heavier multi-agent orchestration setup, and Beta's two-layer engine+inventory fix suggests a more exploratory agent, but neither is specific enough to name a tool. No definitive 
- t5/round5: No confident tool identification. Mild generic observation only: Delta's outsized 710/272-line, 6-file diff for a narrow bugfix suggests a more refactor-prone agentic setup, but this is not specific enough to name a tool, and I did not let 

| Tool | Panel rank | Comparative rank | Δ | Panel weighted-mean | Comparative mean-rank ± σ | n obs |
|---|---|---|---|---|---|---|
| compound | 5 | **1** | +4 ⚠ | 166.25 | 3.00 ± 1.58 | 25 |
| pure | 3 | **2** | +1 | 169.53 | 3.32 ± 1.57 | 25 |
| bmad | 6 | **3** | +3 ⚠ | 165.72 | 3.72 ± 2.35 | 25 |
| gstack | 8 | **4** | +4 ⚠ | 159.97 | 4.36 ± 2.61 | 25 |
| superpower | 4 | **5** | -1 | 166.41 | 4.60 ± 1.87 | 25 |
| omc | 7 | **6** | +1 | 164.80 | 5.00 ± 2.68 | 25 |
| ecc | 2 | **7** | -5 ⚠ | 172.31 | 5.64 ± 2.00 | 25 |
| claudekit | 1 | **8** | -7 ⚠ | 178.93 | 6.36 ± 1.44 | 25 |

`Δ = panel_rank − comparative_rank`. Positive Δ means comparative ranks the tool higher than the panel; ⚠ marks |Δ| ≥ 2.

## Ranking (Weighted Mean)

1. **claudekit** — 178.93/200
2. **ecc** — 172.31/200
3. **pure** — 169.53/200
4. **superpower** — 166.41/200
5. **compound** — 166.25/200
6. **bmad** — 165.72/200
7. **omc** — 164.80/200
8. **gstack** — 159.97/200

## Per-Trial Breakdown

Weighted-mean score for each individual trial (same 3·opus + 2·`GPT-5.4` + others weighting as the canonical column). Surfaces trial-to-trial drift inside a tool — a wide spread means the cohort mean is averaging over disagreeing runs rather than stable ones. The Δ column is `max − min` across all trials; ≥ 15 pts is flagged as **noisy** (the tool's output is bimodal at this sample size).

| Tool | t1 | t2 | t3 | t4 | t5 | Δ (max − min) | Flag | Skills (t1/t2/t3/t4/t5) | Subagents (t1/t2/t3/t4/t5) |
|---|---|---|---|---|---|---|---|---|---|
| claudekit | 188.75 | 189.71 | 172.54 | 184.25 | 159.42 | 30.29 | **noisy** | 134/112/148/—/— | 1/0/1/—/— |
| ecc | 186.04 | 170.38 | 180.83 | 149.21 | 175.08 | 36.83 | **noisy** | 89/77/40/—/— | 1/1/1/—/— |
| pure | 160.96 | 182.33 | 182.00 | 157.37 | 165.00 | 24.96 | **noisy** | 0/0/0/—/— | 0/0/1/—/— |
| superpower | 164.42 | 170.88 | 167.12 | 167.17 | 162.46 | 8.42 |  | 111/117/124/—/— | 0/0/0/—/— |
| compound | 174.96 | 159.04 | 164.12 | 174.83 | 158.29 | 16.67 | **noisy** | 105/75/75/—/— | 0/0/0/—/— |
| bmad | 158.67 | 182.29 | 174.92 | 160.25 | 152.46 | 29.83 | **noisy** | 69/71/110/—/— | 0/0/0/—/— |
| omc | 159.67 | 153.00 | 182.92 | 149.67 | 178.75 | 33.25 | **noisy** | 163/371/157/—/— | 4/6/1/—/— |
| gstack | 156.25 | 162.67 | 153.58 | 165.96 | 161.38 | 12.38 |  | 72/77/67/—/— | 0/0/0/—/— |

Reading: a `noisy` flag here means the cohort mean for that tool is averaging over runs that disagree by ≥ 15 weighted pts. Use this column to read the headline rank with calibration — a tool whose trials cluster tightly is a more reliable signal than one with a wide spread. The pre-registered rerun protocol triggers on **per-round** outliers within a trial (not trial-to-trial), so a wide Δ here is real tool variance, not a harness artifact.

**Skills (t1/t2/t3/t4/t5)** = number of distinct skill / slash-command invocations per trial (from `session-audit.json` → `skills_invoked`). **Subagents (t1/t2/t3/t4/t5)** = sub-agent dispatches per trial. A tool whose primary mechanism is a skill/sub-agent and reads `0` for a trial likely failed to invoke its mechanism — under the rerun protocol this is a Tier-1 trigger ("Skill failure"), distinct from the statistical-outlier trigger. Cross-reference these counts when a trial scores far from its siblings.

## Per-Judge Means

Each cell is one judge's mean score for one tool, averaged over that judge's 15 samples (5 trials × 3 rounds). The columns:

- **Tool** — same 8 setups as above, ordered by Weighted Mean (rank-1 first).
- **opus / grok420 / glm51 / GPT-5.4 / mimo25pro** — that judge's mean score (0–200 rubric) for this tool. Reads vertically to expose **judge base-rate effects**: `GPT-5.4` consistently scores ~20–30 pts below the panel mean (harshest in the panel), `mimo25pro` ~5–15 pts above (most lenient, occasionally saturates at 200). Reads horizontally to see whether the judges agree on the ordering: if a tool is rank-1 under one judge and rank-7 under another, the consensus is weak.

| Tool | opus | grok420 | glm51 | gpt54pro | mimo25pro |
|---|---|---|---|---|---|
| claudekit | 177.9 | 187.5 | 181.8 | 168.1 | 192.5 |
| ecc | 172.1 | 182.9 | 177.0 | 157.3 | 187.7 |
| pure | 169.7 | 177.3 | 174.9 | 156.7 | 181.5 |
| superpower | 168.3 | 175.5 | 173.0 | 147.6 | 182.8 |
| compound | 165.7 | 178.2 | 170.8 | 152.0 | 180.0 |
| bmad | 165.9 | 174.1 | 175.5 | 148.3 | 181.8 |
| omc | 165.0 | 170.4 | 168.9 | 148.5 | 187.0 |
| gstack | 157.3 | 176.3 | 165.7 | 141.6 | 182.5 |


## Provenance Defects (2)

Files whose internal `judge` field disagrees with the filename slot the aggregator dispatched by. The score is still counted (not retroactively pulled); listed here for transparency.

- `_blind-eval/Tango/gpt54pro-judge.json` — slot `gpt54pro` but `.judge` = `openai-o3`
- `_blind-eval/Tango/round1/gpt54pro-judge.json` — slot `gpt54pro` but `.judge` = `gpt-5`
