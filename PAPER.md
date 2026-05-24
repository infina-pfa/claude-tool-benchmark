# AI Coding Tool Benchmark: A Multi-Task, 5-Judge Evaluation of Eight Claude Code Setups

**Author:** Randy Tran (randytran8800@gmail.com)
**Date:** 2026-05-12
**Repository:** [`infina-pfa/claude-tool-benchmark`](https://github.com/infina-pfa/claude-tool-benchmark)

---

## Abstract

We benchmark eight Claude Code setups — plugins, skill packs, hook kits, and a no-addon baseline — on three software-engineering tasks from a production TypeScript monorepo (a private TypeScript NX monorepo) under an identical pinned base model (`claude-opus-4-7`). Each (tool, task) pair runs **5 trials**; each trial is judged on a 20-item / 200-point rubric by a **5-judge panel** drawn from five different vendors (Anthropic / xAI / Z.ai / OpenAI / Xiaomi), and each artifact is re-judged across **3 independent rounds** (the canonical run plus two added stability rounds, kept under `_blind-eval/<label>/round{1,2}/`). Aggregation uses a **pre-registered weighted mean** of per-judge means (opus×3, `GPT-5.4`×2, grok420/glm51/mimo25pro×1, declared in `versions.lock.json`) plus an equal-weight companion report for sensitivity. Across **1800 judgments** (3 tasks × 8 tools × 5 trials × 5 judges × 3 rounds) **no rank-1 lead is statistically significant**: under an exact Student-t detection threshold (two-sided α=0.05, power=0.80, n=5 trials per arm, df=2(n-1)=8) every per-task rank-1 gap falls below MDE, and the *only* pairwise gap that clears its task MDE anywhere in the corpus is `ecc`−`gstack` on `feature`. The rankings below are **point-estimate only, statistically tied** (see §4). By point estimate we observe task-specific ordering rather than a single dominant setup: `ecc` is rank-1 on `feature` (153.30/200), `claudekit` on `bugfix` (178.93/200), and `pure` (baseline Claude Code, no addons) on `refactor` (180.19/200) — none of these leads is distinguishable from rank-2 at standard significance. No setup is top-2 on all three tasks; the bare `pure` baseline is top-3 on bugfix and top-1 on refactor, and on both it sits inside the top operational cluster — the only large refactor gap is `gstack`'s collapse to 144.92/200 (an outlier with `within_σ` ≈ 58), so addon-vs-baseline separation is within judge-calibration spread on this corpus, with the caveat that `between_σ` is a per-tool stdev across the 5 judge means, not a formal SE on the between-tool difference (no hypothesis test is performed; see §4). Four mechanical rubric items (TSC errors, ESLint errors, test failures, and the scope-discipline `lines_removed` count) are deterministically rewritten from `auto-metrics.json` (the R1 override) to remove LLM arithmetic drift; in practice the rewrite fires on **67 of 1800** judge files (~3.7%): 8 on `feature`, 18 on `bugfix`, 41 on `refactor`, concentrated on the `lines_removed` and test-count items — judges still comply on the large majority, and the lock remains in the pipeline so any future LLM that diverges is auto-corrected. The pre-override score is preserved on every judged file. Inter-judge calibration drift is large and known: `GPT-5.4` is the harshest scorer in the panel (≈ 19–27 pts below the per-task panel mean: 19 on bugfix, 27 on feature, 27 on refactor), `mimo25pro` the most lenient; full panel spread (max judge − min judge) is 32.0, 42.0, and 39.4 pts on bugfix / feature / refactor respectively. Weighting and equal-weight aggregations agree on the rank-1 tool for every task; top-3 is identical under both rules on bugfix, reorders on feature (equal-weight: ecc / bmad / pure), and swaps at rank-3 on refactor (weighted bmad ↔ equal-weight superpower). **Preregistration scope:** only the judge weights and the per-task rerun protocol are pre-registered (committed in `versions.lock.json` 2026-05-12, before the t4/t5 expansion); the tasks, the 20-item rubric, the choice of judge panel, and the R1 mechanical-fact lock list were chosen iteratively by the operator and are *not* pre-registered (see §4). Results should be read as descriptive — the strongest claim this design supports is the negative result (no rank-1 lead clears MDE on any task); a confirmatory tool-ranking would require a separate, fully pre-registered cohort. The full corpus (judge JSONs, prompts, diffs, mappings, and aggregation scripts) is published for independent re-analysis.

## 1. Methodology

### 1.1 Tasks and base SHAs

| Task | Description | Base SHA (pinned) |
|---|---|---|
| `feature` | Greenfield Mode-2 CD Batch feature from PRD | `<bench-feature-sha>` |
| `bugfix`  | Near-maturity filter bugfix (an internal ticket)       | `<bench-bugfix-sha>` |
| `refactor`| Aggregate-ownership refactor (an internal ticket)      | `<bench-refactor-sha>` |

Each task ships to the tool as `docs/benchmark/TASK.md`. Operator prompt is identical across tools (`scripts/manual-bench.sh`); tools are free to invoke their own sub-pipelines.

### 1.2 Setups evaluated

Eight setups, all layered on the same pinned base model. Versions are captured in [`versions.lock.json`](https://github.com/infina-pfa/claude-tool-benchmark/blob/main/versions.lock.json):

| Setup | Kind | Version |
|---|---|---|
| `pure` | baseline (stock Claude CLI, no addons) | claude-cli 2.1.133 |
| `claudekit` | git fork | a private Infina fork of claudekit @ `cf636d9` |
| `gstack` | git clone | `garrytan/gstack` 1.28.0.0 |
| `bmad` | npm | `bmad-method` 6.6.0 |
| `omc` | Claude plugin | `oh-my-claudecode` 4.13.6 |
| `compound` | Claude plugin | `compound-engineering` 3.7.0 |
| `ecc` | Claude plugin | `everything-claude-code` 1.10.0 |
| `superpower` | Claude plugin | `superpowers` 5.1.0 |

### 1.3 Trial execution

Per `(task, tool)` we run **5 independent trials**. Each trial is a fresh clone of the task's base repository checked out at the pinned SHA with the tool's configuration installed into an isolated `HOME`. The tool implements the task, runs its own test/build commands, and commits. We capture: implementation diff, `auto-metrics.json` (tsc/eslint/test counts, line changes), test/type-check/lint output, session transcripts, wall time, and token usage.

### 1.4 Scoring rubric

A 20-item rubric across four categories (200 pts):

| Category | Max | Items cover |
|---|---|---|
| Correctness of the change | 70 | Behaviour matches spec, edge-case handling, domain-helper reuse |
| Tests | 50 | Spec-branch coverage, assertion quality, test independence |
| Code quality | 40 | Readability, naming, complexity, safe refactors |
| Scope discipline | 40 | No unrelated changes, no new config surface, respects module boundaries |

Judges output a strict JSON object `{"scores": {"1": 0–10, …, "20": 0–10}, "total": int}`. Per task `CLAUDE.md`, the **canonical per-judge-file score is `sum(scores.values())`**; the stored `total` field is ignored (a small fraction of judges historically reported a `total` off-by-one from the per-item sum).

### 1.5 R1 mechanical-fact override

Four rubric items (per task) have deterministic answers that the judge prompt asks LLMs to copy from a `## Mechanical Facts` block. LLM compliance is partial, so `scripts/apply-r1-override.py` rewrites them post-hoc from the canonical `auto-metrics.json`:

| Task | R1-locked items | Source field |
|---|---|---|
| `feature` | 12, 13, 16, 20 | `tsc_errors`, `eslint_errors`, `tests_core_failed`, `lines_removed` |
| `bugfix`  | 14, 15         | `tsc_errors`, `new_eslint_errors` |
| `refactor`| 13, 14         | `tests_savings_cd_failed`, `tests_core_failed` |

For `feature` item 20 (scope discipline), the locked score follows the same formula the judge prompt uses: `s20 = 10 if lines_removed == 0 else max(0, 10 - ceil(lines_removed / 10))`. Pre-override scores are preserved per-file under `scores_pre_r1`; `aggregate-results.sh` runs an idempotent R1 sweep before every aggregation so any single-judge retry that bypassed the wrapper is auto-corrected.

### 1.6 Judge panel

| Judge | Model ID | Vendor | Route | Weight |
|---|---|---|---|---|
| `opus`      | `claude-opus-4-7`  | Anthropic | Claude CLI | **3** |
| `gpt54pro`  | `gpt-5.4-pro`      | OpenAI    | `/v1/responses` | **2** |
| `grok420`   | `x-ai/grok-4.20`   | xAI       | OpenRouter | 1 |
| `glm51`     | `glm-5.1`          | Z.ai      | OpenCode Go | 1 |
| `mimo25pro` | `mimo-v2.5-pro`    | Xiaomi    | OpenCode Go | 1 |

> **`gpt54pro` route note.** The model/route shown is the t1–t3 pin (`gpt-5.4-pro` via `/v1/responses`). From t4 onward this slot answered as `gpt-5.4` via a local cliproxy; the slot key is frozen for aggregation continuity. Full provenance: `versions.lock.json` `judges.gpt54pro.routing_history` and §2.5.

Each artifact is judged **3 times** by each of the 5 judges (the canonical run plus two added stability rounds) → **15 judgments per artifact**, **75 per `(tool, task)` cell** (5 trials × 5 judges × 3 rounds), and **1800 across the corpus** (3 tasks × 8 tools × 5 trials × 5 judges × 3 rounds). Judges are stateless across calls (fresh context each judgment). The canonical round's judge files live flat under `_blind-eval/<label>/`; the two added rounds live under `_blind-eval/<label>/round1/` and `_blind-eval/<label>/round2/`. The aggregator reads `^round[0-9]+$` subdirs plus the root in union, so all three rounds are counted; pilot/sample dirs (`roundcotsample*`, etc.) are excluded. Temperature is fixed to 0 where the provider exposes it (OpenRouter, OpenCode Go); Anthropic CLI and OpenAI `/v1/responses` do not expose temperature/seed, so residual sampler variance (visible as round-to-round drift inside a single judge × artifact cell) is absorbed in per-judge σ rather than eliminated.

### 1.7 Blind evaluation

Labels are NATO-letter pseudonyms (`Alpha`, `Bravo`, …, 40 per task = 8 tools × 5 trials). The mapping `{label → (tool, trial)}` is stored in each task's `_blind-eval/.mapping-DO-NOT-OPEN.json` and read only by the aggregator.

Tool identity is hidden via:
- **Path-level scrub** — `scripts/blind-eval-setup.sh` excludes `.omc/**`, `_bmad/**`, `_bmad-output/**`, `_bmad-core/**`, `docs/bmad/**`, `docs/superpowers/**`, `plans/**`, `.claudekit/**`, `.gstack/**`, `.superpowers/**`, `.compound-engineering/**`, `.ecc/**`, `CLAUDE.md.original`.
- **Content scrub** — an `awk` post-pass strips those prefixes from diff body text so source comments referencing tool-state paths are rewritten.
- **Auto-metrics anonymisation** — `plugin_versions` and `collected_at` are stripped from `auto-metrics.json` before it lands under `_blind-eval/`.

A skilled judge could still infer identity from idiosyncratic code style; we do not claim semantic anonymity.

### 1.8 Aggregation rule

**Reported tool mean:** weighted mean of per-judge means with weights pre-registered in `versions.lock.json` `judges.*.weight` and mirrored as a hardcoded constant in `scripts/aggregate-results.sh` (kept in sync manually; the aggregator does not parse the lockfile). Missing judges drop out of both numerator and denominator. The form preserves judge-drift cancellation when per-judge n is asymmetric (not the case in this corpus but kept for forward compatibility).

**Equal-weight comparator:** the `Pooled Mean` column in every report (and a parallel `final-report.equal-weight.md` per task) gives the unweighted comparator. Rank-1 is identical across weighted and equal-weight aggregations on every task in this corpus.

**Variance decomposition.** Pooled σ is reported alongside two components: `within_σ` (within-judge spread across the 15 samples per (tool, judge) — 5 trials × 3 rounds; mean of the per-judge stdev) and `between_σ` (judge base-rate spread, stdev of per-judge means). With 3 rounds in the cohort, `within_σ` bundles trial-to-trial output variance with round-to-round judge-sampler variance; the round component is small for providers that honor `temperature=0` (OpenRouter, OpenCode Go) and absorbed into `within_σ` for providers that do not (Claude CLI, OpenAI `/v1/responses`). Within > between would indicate the tool's output (combined with sampler drift on the unpinned judges) is unstable; the reverse means most variance is judge base-rate disagreement.

## 2. Results

### 2.1 Per-task rankings

#### feature (Mode-2 CD Batch)

| Rank | Tool | Weighted Mean /200 | Pooled Mean | within_σ | between_σ |
|---|---|---|---|---|---|
| 1 | **ecc** | **153.30** | 157.11 | 8.96 | 15.29 |
| 2 | pure | 143.13 | 147.44 | 7.51 | 15.72 |
| 3 | bmad | 141.33 | 147.65 | 7.02 | 20.81 |
| 4 | superpower | 140.16 | 143.68 | 10.06 | 15.14 |
| 5 | omc | 139.49 | 143.59 | 10.88 | 17.29 |
| 6 | claudekit | 135.04 | 139.07 | 12.75 | 16.83 |
| 7 | compound | 134.67 | 140.11 | 13.26 | 15.99 |
| 8 | gstack | 131.98 | 137.80 | 18.35 | 19.41 |

Cohort weighted-mean = 139.9 ± ~6 pts. `ecc` has the highest feature point estimate (10.2 pts above rank-2 `pure`), but that gap is **below the feature MDE (19.33) and below `ecc`'s own between-judge σ (15.29)** — it is not a statistical separation; ranks 2–8 span just 11.2 weighted points (143.13 → 131.98). The top-4 (ecc / pure / bmad / superpower) span 13.1 weighted points — small relative to between-judge σ (15–21 pts). `between_σ` exceeds `within_σ` on every tool; the dominant uncertainty is judge disagreement, not tool instability.

#### bugfix (near-maturity filter — an internal ticket)

| Rank | Tool | Weighted Mean /200 | Pooled Mean | within_σ | between_σ |
|---|---|---|---|---|---|
| 1 | **claudekit** | **178.93** | 181.53 | 11.42 | 9.35 |
| 2 | ecc | 172.31 | 175.40 | 13.54 | 11.70 |
| 3 | pure | 169.53 | 172.03 | 12.05 | 9.58 |
| 4 | superpower | 166.41 | 169.43 | 7.48 | 13.28 |
| 5 | compound | 166.25 | 169.33 | 9.57 | 11.27 |
| 6 | bmad | 165.72 | 169.13 | 12.75 | 12.94 |
| 7 | omc | 164.80 | 167.97 | 15.66 | 13.74 |
| 8 | gstack | 159.97 | 164.69 | 9.13 | 16.12 |

Bugfix is the easiest of the three tasks (cohort mean ≈ 168) and a compressed cohort (top-to-bottom span 19.0 weighted pts). `claudekit` (178.93) is ≈ 6.6 pts clear of rank-2 `ecc`, which is ≈ 2.8 pts above rank-3 `pure`. **`pure` (baseline) lands rank-3** — the null hypothesis "tools add no value over the bare CLI" is not rejected on bugfix. Bugfix has the most `within_σ > between_σ` cells (`claudekit` 11.42 vs 9.35; `pure` 12.05 vs 9.58; also `ecc` 13.54 vs 11.70 and `omc` 15.66 vs 13.74) — judges agree on absolute scale for those tools, and the residual spread is genuinely trial-to-trial (compounded with round-to-round sampler noise on the unpinned judges).

#### refactor (aggregate-ownership refactor — an internal ticket)

| Rank | Tool | Weighted Mean /200 | Pooled Mean | within_σ | between_σ |
|---|---|---|---|---|---|
| 1 | **pure** | **180.19** | 182.63 | 4.44 | 13.73 |
| 2 | claudekit | 178.04 | 180.76 | 5.29 | 17.01 |
| 3 | bmad | 177.74 | 180.08 | 5.48 | 15.28 |
| 4 | superpower | 177.56 | 180.51 | 5.09 | 15.39 |
| 5 | compound | 174.42 | 177.03 | 6.04 | 16.40 |
| 6 | ecc | 173.61 | 176.57 | 8.71 | 16.12 |
| 7 | omc | 170.11 | 173.83 | 7.43 | 17.52 |
| 8 | gstack | 144.92 | 147.92 | 58.43 | 12.52 |

Top-5 span = 5.8 weighted pts. **`pure` (baseline) is rank-1 on refactor** — the strongest existence-of-null result in the corpus. `within_σ` is low across all tools except `gstack` (58.4 — its refactor diffs are bimodal across trials, dragging the mean to 144.92); for the other seven the refactor variance budget is almost entirely between-judge (within ≤ 8.7, between 13.7–17.5).

### 2.2 Per-judge calibration

Means per `(task, judge)`, averaged across all 8 tools:

| Task | opus | grok420 | glm51 | GPT-5.4 | mimo25pro | spread |
|---|---|---|---|---|---|---|
| feature | 139.3 | 159.8 | 149.8 | 117.8 | 156.1 | 42.0 |
| bugfix | 167.7 | 177.8 | 173.4 | 152.5 | 184.5 | 32.0 |
| refactor| 176.9 | 180.1 | 181.6 | 148.3 | 187.7 | 39.4 |

**`GPT-5.4` is consistently the harshest scorer** (lowest mean on every task; ≈ 19 pts below the panel mean on bugfix, ≈ 27 on feature, ≈ 27 on refactor). **`mimo25pro` is the most lenient** and occasionally emits 200/200 saturations; its weight of 1 dilutes the impact, but right-tail scores should be read in that context. The full panel spread (max judge mean − min judge mean) is 42.0 pts on feature, 32.0 pts on bugfix, and 39.4 pts on refactor. **`opus`** sits near the panel mean on `refactor` (closest, +1.9) and `bugfix` (−3.5) but is the second-harshest on `feature` (−5.3, behind only `GPT-5.4` — a long-artifact task where opus's calibration appears more conservative). **`grok420` and `glm51`** track each other within ~10 pts (1.5 pts on refactor, 4.3 on bugfix, 10.1 on feature — the feature gap is the loosest of the three).

The 3 / 2 / 1 / 1 / 1 weighting de-emphasises `mimo25pro`'s right-tail saturations and the harsh `GPT-5.4` tail, anchoring on `opus`. The equal-weight comparator (`Pooled Mean` column above, and `final-report.equal-weight.md`) shows the same rank-1 tool on every task; mid-pack swaps of 1–2 positions are possible under different weights — see §5.

### 2.3 R1 override impact

Across the 1800 judge files (3 rounds × 600 per round), the R1 sweep rewrote at least one deterministic item on **67 judgments** (~3.7%): 8 on `feature` (items 12 / 13 / 16 / 20), 18 on `bugfix` (items 14 / 15), and 41 on `refactor` (items 13 / 14). The earlier 3-trial cohort saw only 8 hits with `bugfix` at zero; the expanded 5-trial cohort surfaces more non-compliant `lines_removed` / test-count cells, but R1's empirical impact on per-tool means stays small — it rewrites single rubric items, not whole scores, so the headline weighted means move by well under a point. The lock is still load-bearing as a *safety net* — without it, a single non-compliant judge on a key item like "did tsc pass" or "how many lines were removed" would propagate LLM arithmetic drift directly into the cohort mean, and the override is fully auditable (`scores_pre_r1` preserved per file). Worked example: on `feature`, item 20 (`lines_removed` → scope discipline) is locked to `10 - ceil(lines_removed / 10)`. A trial with 80 lines removed gets `s20 = 2` regardless of judge opinion; the affected feature files include such mismatches.

### 2.4 Cohort symmetry

`scripts/audit-cohort-symmetry.py` confirms all 40 labels (8 tools × 5 trials) per task land on the pinned base SHA (`<bench-feature-sha>` / `<bench-bugfix-sha>` / `<bench-refactor-sha>`). Cohort completion span: `feature` 181.0h, `bugfix` 149.7h, `refactor` 146.6h. Spans exceed 24h because the cohort was assembled across the staged t1–t5 trial expansion (t1–t3, then t4/t5 added later) plus the leak-fix re-judge pass for `Grove`/`Delta`/`Mike`/`Xray`/`November`/`Quebec` (see [`docs/RERUN-PRE-PUBLISH.md`](https://github.com/infina-pfa/claude-tool-benchmark/blob/main/docs/RERUN-PRE-PUBLISH.md)); those 6 leak-set labels resolve to 4 tools (claudekit×3, omc×1, gstack×1, superpower×1) — every label with detected leakage was re-judged on a clean diff, while `pure`, `bmad`, `compound`, `ecc` had no labels in the leak set. Pre-leak-fix judge JSONs are retained alongside the new judgments under each affected label dir for audit. The rerun is therefore *coverage-symmetric* (the leak-fingerprint set, not the tool set) — it is not a cohort-wide re-judge of all 40 feature labels.

### 2.5 Comparative-rank validity probe (Opus-1M + GPT-5.4, parallel signals)

The 5-judge panel scores artifacts **in isolation** — each judge sees one tool's output at a time and scores it against the 20-item rubric. This is the right shape for variance estimation (per-(label, judge, round) independent observations) but is vulnerable to *absolute-calibration drift across the cohort*: a judge can be unintentionally lenient on one artifact and harsh on another without ever seeing them side-by-side. We added a complementary **comparative-rank lane** to probe how robust the panel's ordering is under a fundamentally different judgment regime, and we run it under **two independent models** so that a single model's idiosyncrasies cannot be mistaken for a regime effect.

**Method.** For each `(task, trial)`, all 8 implementations are bundled into a single prompt (PRD + per-artifact `auto-metrics.json` + `implementation-diff.patch`; plan files are excluded — see *blinding* below) and sent to two parallel judges:

- **Opus-1M lane.** `claude-opus-4-7` via Claude CLI subscription auth with `effortLevel: high` (extended thinking on), 1M-token context — `scripts/judge-opus1m-comparative.sh`.
- **GPT-5.4 lane.** `gpt-5.4` via a local cliproxy at `localhost:8317/v1/chat/completions` (subscription-relayed, not API-key billed), strict `json_schema` `response_format` with server-side validation — `scripts/judge-gpt54-comparative.sh`. The comparative slot is named `gpt54` to be honest about what cliproxy returns (gpt-5.4, not gpt-5.4-pro); the panel slot retains the legacy name `gpt54pro` for t1-t3 aggregation continuity. The two slots are independent — see `versions.lock.json judges.gpt54pro.routing_history`.

Each judge is asked to **rank the 8 implementations 1-8** with a short per-rank rationale, plus optional `calibration_notes` and a required `blinding_concerns` field. **Five rounds per cell, each with a fresh per-round label namespace** (`R1-Alpha…R1-Theta`, `R2-…`, …, `R5-…` — disjoint from the NATO blind labels used by the panel) and an independently shuffled prompt order. Mapping seed: `sha256(task | trial | round | wall-clock | nanos)`, recorded per-round with `mapping_sha256` provenance embedded in each ranking JSON for tamper-detection.

**Aggregation.** Per tool, per lane: mean rank across 25 cells (5 trials × 5 rounds), with σ; then sort to derive each lane's comparative-rank ordering. The headline numbers are **three Spearman ρ values per task**, computed pairwise across {panel weighted-mean rank, Opus-1M comparative rank, GPT-5.4 comparative rank}. The lanes are *parallel signals* — neither comparative output enters the weighted mean — so the three ρ values together let us separate **regime drift** (both comp lanes disagree with the panel but agree with each other) from **vendor bias** (one comp lane diverges; the other tracks the panel). Implementation: `scripts/aggregate-comparative.py --lane {opus1m,gpt54}` produces per-lane `_aggregate{,.gpt54}.{json,md}`; `scripts/triangulate-comparative.py` joins them into `results/_comparative-eval/_triangulation.{json,md}`.

**Blinding (and the early-pilot leak).** The first round of the original pilot (bugfix t1 r1, Opus-1M lane) included plan files in the bundle. Opus correctly identified three tools from plan formatting vocabulary (`RALPLAN-DR` → OMC; `mode: fast` frontmatter → claudekit; "Implementation Units (U1/U2)" template → compound). **Code-style itself did not identify tools.** Plans were dropped from the bundle for all subsequent rounds across both lanes, and the `blinding_concerns` field was reset clean on the re-run. Across the 150 rounds of the full two-lane run (75 per lane, plans excluded), roughly one third of rounds reported weak observations (low-confidence pattern-matching about scaffold density, in-code comment style, planning-vocabulary leaks, or formatter-hook reflow on untouched code), and none constituted firm tool identification. Notably the *two lanes flag different rounds* as borderline, which is itself evidence that the residual signal is judge-dependent noise rather than a stable code-style leak. The field is doing its job and the residual signal is conservative noise, not contaminating leakage.

**Scope.** v2 only (no cross-base-model mixing with v1 `opus-4-6`), full t1-t5 across all 3 tasks, 5 rounds per cell, **two judges per cell** — **150 comparative-judge calls total**, 25 per (task, lane). The pipeline started as an Opus-1M-only t1 pilot (2026-05-16), expanded to full t1-t5 once it cleared validation, then added the GPT-5.4 lane (2026-05-17) to resolve the regime-vs-vendor question raised by the single-lane results.

**Headline triangle (n_cells = 25 per task, per lane).** Three pairwise Spearman ρ:

| Task | panel ↔ opus-comp | panel ↔ gpt-comp | opus-comp ↔ gpt-comp | Read |
|---|---|---|---|---|
| feature | +0.571 | **+0.833** | **+0.857** | vendor bias — opus-comp mildly diverges, gpt-comp tracks panel |
| bugfix | **−0.405** | +0.167 | +0.667 | mixed — both comp lanes diverge from panel and partly agree with each other |
| refactor | +0.310 | **+0.810** | +0.500 | vendor bias — opus-comp is the outlier; gpt-comp recovers panel ordering |

The two comparative lanes are **internally consistent** (opus ↔ gpt ρ is 0.86, 0.67, 0.50 across the three tasks — never weak), which means the comparative regime as a *whole* is a stable measurement and the disagreement with the panel, where it exists, is concentrated in the opus-comp lane rather than being a property of head-to-head ranking per se.

**Per-task read.**

- **`feature` — vendor bias (opus-comp the mild outlier).** gpt-comp tracks the panel closely (ρ=0.833) while opus-comp only mid-correlates (ρ=0.571), even though the two comp lanes agree strongly with each other (ρ=0.857). The anchors are invariant — `ecc` is rank-1 and `gstack` is rank-8 in all three rankings — and the mid-pack scramble is opus-comp-driven: `claudekit` jumps from panel rank-6 to opus-comp rank-2 (gpt-comp rank-3, milder); `bmad` drops from panel rank-3 to opus-comp rank-7 (gpt-comp rank-5). With the full second lane and the symmetric N=75 panel, the single-lane pilot's "feature = clean regime drift" reading is retired: gpt-comp largely recovers the panel order, so the residual disagreement is an opus-comp vendor effect, not a regime property.
- **`bugfix` — mixed, but the regime story is the dominant one.** Opus-comp and gpt-comp agree with each other at ρ=0.667; neither agrees with the panel (−0.41, +0.17). The panel's top-2 (`claudekit`, `ecc`) drop to comparative rank-8/5 and rank-7/7; comparative's top-1 (`compound`) is panel rank-5 in both lanes. The two comparative judges, independently, prefer minimal-surgery bugfix diffs (`compound`, `pure`) over the panel's preferred high-completeness fixes (`claudekit`, `ecc`). This is no longer "an opus quirk" — both vendors do it, so it's a regime-level finding: panel and comparative regimes are measuring different things on bugfix, with comparative weighting surgical scope more heavily than the panel's per-rubric absolute checklist.
- **`refactor` — vendor bias.** Opus-comp ranks `refactor` idiosyncratically (panel ρ=0.310), but gpt-comp recovers the panel ordering closely (panel ρ=0.810; `pure`/`claudekit` are rank-1/2 in both, with only a `bmad`↔`superpower` swap at panel rank-3/4). Inter-comp ρ is mid (0.50). This pattern flips an earlier reading: the v1 t1-only result of "comparative regime disagrees with panel on refactor" reflected an opus-specific preference, not a regime property. With gpt-comp added, the panel's refactor ordering is the robust one and the opus-comp lane is the outlier on this task. The only persistent cross-lane disagreement is `ecc` (panel rank-6, both comp lanes rank-8) and `gstack` (panel rank-8, comp lanes rank-3/5) — both lanes downgrade `ecc`'s refactor diff and upgrade `gstack`'s, but the rest of the ordering survives the vendor and regime swap.

**Tool-level pattern across all three rankings, panel / opus-comp / gpt-comp (n=25 per lane):**

- **`pure`** — feature 2/3/2, bugfix 3/2/3, refactor 1/1/1. Top-3 in every ranking, every regime, every vendor. The most robust tool in the cohort.
- **`gstack`** — feature 8/8/8 (perfect agreement at the bottom), bugfix 8/4/6, refactor 8/3/5. Panel-bottom on every task; comp lanes are gentler on bugfix and refactor, but never put it in the top half.
- **`ecc`** — feature 1/1/1 (perfect agreement at the top), bugfix 2/7/7, refactor 6/8/8. Both comp lanes agree on dropping `ecc` to the bottom on bugfix and refactor — the regime story is consistent, the vendor question doesn't apply, the panel-vs-comparative gap is real on those two tasks.
- **`claudekit`** — feature 6/2/3, bugfix 1/8/5, refactor 2/5/2. The biggest cross-regime mover. Comparative-regime *upgrades* it on feature and (partly) restores it on refactor; comparative-regime *demotes* it sharply on bugfix in both lanes. Vendor effects are small here — both comp models tell the same story.
- **`compound`** — feature 7/6/7, bugfix 5/1/1 (both comp lanes rank-1), refactor 5/6/6. Effectively stationary except on bugfix, where both comp lanes promote it to rank-1 — the strongest single-cell cross-vendor agreement in the matrix.
- **`bmad`** — feature 3/7/5, bugfix 6/3/4, refactor 3/2/4. Panel mid-pack; opus-comp downgrades it on feature and upgrades it on refactor, while gpt-comp stays nearer the panel on both — vendor noise rather than a regime effect.
- **`superpower`** — feature 4/5/4, bugfix 4/5/2, refactor 4/7/3. gpt-comp tracks the panel on every task; opus-comp downgrades it on refactor, gpt-comp does not — another opus-specific shift the second lane does not corroborate.
- **`omc`** — feature 5/4/6, bugfix 7/6/8, refactor 7/4/7. Effectively *tied* between panel and gpt-comp on every task; opus-comp upgrades it on feature and refactor — another opus-specific shift the second lane does not corroborate.

**Interpretation — what the triangulation resolves.** The single-lane Opus-1M result raised three competing hypotheses for why panel and comparative ranks diverge. The two-lane triangulation at the symmetric N=75 panel lets us assign each task empirically:

1. **Per-artifact lenience drift in the panel** (judges scoring in isolation drift calibration cell-to-cell; comparative forces a single calibration moment). If this were dominant, both comp lanes would diverge from the panel *together* while agreeing with each other. **No task fits this cleanly at N=75.** Feature — the single-lane pilot's regime-drift example — does not survive: gpt-comp tracks the panel at ρ=0.833, so the divergence is not regime-wide. The clean regime-drift case the pilot reported was an artifact of the single (opus) lane.
2. **Style preference inversion under side-by-side input** (comparative weights surgical scope and idiom-fit above per-rubric absolute scoring). If dominant on a task, *both* comp lanes re-rank the same way and agree with each other more than with the panel. **Bugfix** fits this: opus-comp and gpt-comp agree at ρ=0.667, both demote `claudekit`/`ecc` and promote `compound`/`pure`, and neither tracks the panel. The bugfix sign-flip is a real cross-vendor regime property, not a judge property.
3. **Single-vendor intrinsic preference** (the opus-comp judge has context-dependent style preferences that the second vendor does not share). If dominant on a task, only one comp lane diverges from the panel while the other tracks it. **Feature and refactor both fit this** — gpt-comp tracks the panel (ρ=0.833 feature, 0.810 refactor) while opus-comp lags (0.571, 0.310). The opus-comp lane is the consistent outlier on the two non-bugfix tasks; the earlier "feature/refactor disagree with the panel" readings from the single-lane pilot are largely retired by the second vendor.

**What this changes for the headline ranking.** The MDE analysis (§5, also each per-task report's "Power analysis & detection threshold" section) already showed that most mid-pack rank differences in v2 fall below the n=5 detection threshold and should be read as ties. The triangulation sharpens this in two directions: **`feature` rank-1 and rank-8 are triply-anchored** (`ecc` and `gstack` are rank-1/8 under panel, opus-comp, and gpt-comp), so those positions are the strongest claims in the paper; **`bugfix` rank-1 is regime-specific in a model-independent way** — under per-artifact panel scoring `claudekit` wins, under head-to-head ranking both comparative vendors agree `compound` wins, and that disagreement is the clearest cross-vendor regime finding in the dataset. The cleanest read of the combined evidence: within each task, mid-pack ranks should be treated as an operational tie cluster, the rank-1 / rank-8 anchors are the strongest claims, and *which regime is the "right" one for bugfix is a methodological choice we surface rather than resolve*.

**Caveats.**

- **Two comparative judges, not five.** The triangulation resolves regime-vs-vendor more cleanly than the single-lane pilot did, but it cannot rule out that a *third* comparative model would land differently on bugfix. The strongest claim we can make is "the bugfix regime gap survives a vendor swap between opus-4-7 and gpt-5.4, while the feature/refactor gaps are opus-comp-specific," not "all comparative judges would agree." A third comp lane (`glm51` or `grok420`) would tighten this further; we did not run it in v2.

**Reproducibility.** Per-round outputs live under `results/<task>/_comparative-eval/t{1..5}/round{1..5}/`: `prompt.md` is the verbatim prompt sent (identical across lanes for a given cell), `.mapping-DO-NOT-OPEN.json` records the per-round seed + label assignment, `{opus1m,gpt54}-ranking.json` is each lane's parsed schema-validated output (with embedded `mapping_sha256` for tamper-detection), and `{opus1m,gpt54}-ranking.raw.json` is the full upstream envelope (Claude CLI for opus-1m, cliproxy `/v1/chat/completions` for gpt-5.4). Per-task per-lane aggregates: `_aggregate.{json,md}` (opus-1m, default) and `_aggregate.gpt54.{json,md}` are regenerated by `scripts/aggregate-comparative.py --lane {opus1m,gpt54}`. The cross-task triangulation in `results/_comparative-eval/_triangulation.{json,md}` is regenerated by `scripts/triangulate-comparative.py`. Each `final-report.md` renders the **Opus-1M lane** of this probe under §"Comparative-rank validity probe" as an in-report quick signal; the full two-lane (Opus-1M + GPT-5.4) triangulation with all three pairwise Spearman ρ per task lives in `results/_comparative-eval/_triangulation.{json,md}`.

## 3. Discussion

**Tool ≠ universal lift.** No single setup is top-2 on all three tasks. `ecc` is strongest on `feature` and second on `bugfix` but mid-pack on `refactor`. `claudekit` wins `bugfix` but is rank-6 on `feature`. `pure` (no addons) is rank-2 on `feature`, rank-3 on `bugfix`, and **rank-1 on `refactor`**. A reader looking for "the best Claude Code setup" should pick by task type, not headline rank.

**Pure-vs-cohort separation is mixed on bugfix; tight on refactor.** `pure` lands in the top-3 on `bugfix` and rank-1 on `refactor`. On `refactor`, no addon exceeds `pure` and the top-5 sit within 5.8 weighted pts — well inside the operational tie envelope of §4. On `bugfix`, the picture is split by point estimate: `claudekit` (178.93) and `ecc` (172.31) sit **9.4 and 2.8 weighted pts above** `pure` (169.53) respectively. **An earlier version of this paragraph claimed `claudekit − pure` rejected the strict null on bugfix because the gap exceeded the operational ~5-pt tie envelope; that claim does not survive the formal power analysis added 2026-05.** The per-task report computes MDE at the cohort's actual **n=5** trials per arm using the exact Student-t critical value (df=2(n-1)=8): **22.17 weighted pts** on bugfix (α=0.05 two-sided, power=0.80, σ_pool=11.14 pts; see `results/power-analysis.json` and each per-task report's *Power analysis & detection threshold* section), so the 9.4-pt gap is below detection threshold and the strict null "no addon outperforms the bare CLI" is *not* rejected at standard significance. The only separation that clears MDE anywhere in this cohort is `ecc` − `gstack` on `feature` (≈ 21.3 pts > the 19.33-pt feature MDE); no separation clears MDE on `bugfix` or `refactor` — `gstack`'s large refactor gap is *not* significant because that arm's own trial-4 (≈36/200 vs ~178 on its other four) inflates the refactor σ_pool to 22.13.

**Where tools separate: greenfield feature work.** `feature` is the lowest-scoring task overall (cohort mean ≈ 140). `ecc` (153.30) has the highest feature point estimate — **10.2 pts above rank-2 `pure`** — but, like the `claudekit − pure` bugfix gap retracted above, this is **below the formal feature MDE (19.33) and is not a statistical separation**; the only feature gap that clears MDE is `ecc` − `gstack` (≈21.3). Every adjacent gap is small (rank-2 → rank-3 = 1.8, rank-3 → rank-4 = 1.2, rank-4 → rank-5 = 0.7, rank-5 → rank-6 = 4.5, rank-6 → rank-7 = 0.4, rank-7 → rank-8 = 2.7 pts), so the rank-1 → rank-8 column (`ecc` through `gstack`) is one operational cluster by point estimate, not a statistical ranking: the heavy-orchestration setups `bmad`/`omc` landing mid-pack and `pure` landing rank-2 is a directional observation, not a statistical cluster. The session-audit ([`docs/analysis/feature-cohort.md`](https://github.com/infina-pfa/claude-tool-benchmark/blob/main/docs/analysis/feature-cohort.md)) finds no monotone relationship between subagent dispatch or tool-config read volume and feature score.

**Judge variance dominates.** On 19 of 24 (task, tool) cells `between_σ > within_σ`. The five exceptions are all where combined trial-to-trial + round-to-round spread runs ahead of judge base-rate spread: `claudekit` (11.42 within vs 9.35 between), `ecc` (13.54 vs 11.70), `pure` (12.05 vs 9.58) and `omc` (15.66 vs 13.74) on **bugfix**, plus `gstack` on **refactor** (58.43 vs 12.52 — its refactor diffs are bimodal across trials). Across the remaining 19 cells most uncertainty comes from judges disagreeing on absolute scale, not from tool output instability. `GPT-5.4` is consistently ≈ 19–27 pts below the per-task panel mean (19 on bugfix, 27 on feature, 27 on refactor). A single-judge benchmark on this corpus would under-report uncertainty by approximately the magnitude of the between-judge σ (9–21 pts depending on (task, tool) cell; feature spans 15–21, refactor 13–18, and bugfix runs lower at 9–16). The 5-judge weighted panel is the intended mitigation.

**R1 is a safety net, not a hot path.** 67 of 1800 judge files (~3.7%) had at least one mechanical-fact item rewritten by the R1 sweep (8 on `feature`, 18 on `bugfix`, 41 on `refactor`) — the 5-trial expansion surfaced more non-compliant `lines_removed`/test-count cells than the 3-trial pilot (which saw 8, with `bugfix` at zero), but the sweep still moves only single rubric items, so its effect on the headline weighted means is well under a point. R1 earns its place because the worst-case failure mode (a single non-compliant judge propagating LLM arithmetic drift on "did tsc pass" or "how many lines were removed" into the cohort mean) is exactly the kind of error the post-hoc lock makes impossible. Future iterations should expand R1 coverage to more deterministic items (e.g., "did the suite pass at all" is binary from `test-output.txt`) — broader coverage costs nothing when compliance is high and protects the corpus when a future judge regresses.

## 4. Limitations and threats to validity

- **Operator interaction is approve-only ("vibecode" mode).** Each trial is executed by accepting whatever plan, sub-agent dispatch, edit, or shell command the tool proposes — no mid-flight steering, no plan rejection, no "try a different approach" requests, no rejection of low-quality sub-steps. The per-tool slash command is fired once with the task prompt (see `scripts/manual-bench.sh`), then the operator only confirms permission prompts and lets the tool run to completion. This deliberately measures *autonomous one-shot capability under the pinned base model* (`claude-opus-4-7`). Setups whose realised quality depends on iterative human feedback (plan revision, rejecting a bad sub-task, mid-edit course correction, asking the agent to redo a section) will rank lower here than they would in an interactive pair-programming workflow. The rankings should be read as **"best when the operator just keeps approving"**, *not* as a measure of which tool is best in a human-in-the-loop coding session — a setup that finishes second here under approve-only execution may well be first under active steering, and vice-versa.
- **Single-repository, single-language.** All tasks are TypeScript in one internal NX monorepo. Generalisation to Python, Go, Rust, or polyglot codebases is untested.
- **Single executor base model.** All tool runs use `claude-opus-4-7`. A tool that specialises on a different model family might rank differently on sonnet, haiku, GPT, or Gemini bases.
- **Self-preference not identified.** Every executor uses the same Anthropic base, so an `opus_mean − non-Anthropic-mean` diagnostic cannot distinguish family-level favouritism from intrinsic judge-calibration drift, and is not reported here. As non-causal descriptive checks (explicitly *not* a self-preference estimate), the equal-weight comparator (`final-report.equal-weight.md`) and each report's *Per-judge z-normalized sensitivity* section show how rankings move when opus's 3× weight and per-judge base rates are removed; rank-1 is stable under both.
- **Cross-task synthesis intentionally not reported.** A single cross-task z̄ leaderboard is sensitive to weighting (equal-weight, judgment-count-weighted, and rank-sum disagree on middle-tier ordering with multi-rank swings) and bootstrap CIs on such a summary would be wide at this sample size (5 trials per cell). We report per-task tables only; readers wanting a cross-task summary should read the 3 `final-report.md` files together.
- **Sample size per cell — formal MDE.** 5 trials × 5 judges × 3 rounds = 75 judgments per `(task, tool)`, but the within-cell judgments are correlated (same judge across rounds, same trial across rounds), so trials are the real degree of freedom for output quality. Under a two-sample t-test (α=0.05 two-sided, power=0.80, σ_pool from trial-level weighted means) the per-task reports compute the Minimum Detectable Effect at the cohort's **n=5** trials per arm using the **exact Student-t critical value** for df=2(n-1)=8 (t≈2.306), not the normal z=1.96 — at n=5 the t correction enlarges every MDE by ~12%: **19.33 weighted pts on feature, 22.17 on bugfix, 44.02 on refactor** (σ_pool 9.72 / 11.14 / 22.13; see `results/power-analysis.json`). (The β term retains the normal z=0.84 as a deliberate conservative approximation — the exact noncentral-t power term needs scipy, which is not a project dependency — so the reported MDE is a conservative lower bound on the true t-based MDE.) The n=3→n=5 expansion did **not** scale MDE down as 1/√n: the n=3 σ_pool under-estimated true trial-to-trial variance, so σ_pool *rose* on every task (most sharply on refactor — `gstack`'s trial-4 refactor diff scored ≈36/200 against ~178 on its other four, a mechanically clean run that is a valid in-distribution trial under the pre-registered no-selective-rerun rule). Every per-task rank-1 lead falls below the MDE (feature 10.17, bugfix 6.62, refactor 2.15 pts), so the top-cluster orderings are *point-estimate first, statistically tied at this sample size*. **No rank-1 lead on any task clears MDE; under the exact-t threshold the only pairwise gap that clears its task MDE anywhere in the corpus is `ecc`−`gstack` on `feature` (≈21.3 > the 19.33 feature MDE).** An earlier z-based analysis additionally flagged `ecc`−`claudekit` (≈18.3) and `ecc`−`compound` (≈18.6) as clearing the feature MDE; both fall **below** MDE under the corrected exact-t critical and are no longer treated as separations. No family-wise correction is applied to the ≥21 pairwise gap comparisons — they are descriptive detection-threshold checks, not confirmatory hypothesis tests, and should not be read as a multiple-testing-controlled family. The rising-MDE result is itself the empirical demonstration of why the protocol bars post-hoc selective reruns.
- **Inter-rater agreement is low for absolute scores.** Krippendorff α (interval; judges as coders; blind labels as units; computed by `scripts/compute-krippendorff.py`) is **0.124 on feature, 0.284 on bugfix, 0.626 on refactor** (`results/krippendorff-alpha.json`). Under Krippendorff's conventional thresholds (≥0.800 firm, ≥0.667 tentative) none of the three reaches the tentative band — though `refactor` (0.626) sits just below it, far above the feature/bugfix values — so these values do not support firm absolute-score claims; α punishes per-judge lenience drift hard — `GPT-5.4` and `mimo25pro` are 30+ pts apart on most artifacts even when their tool *orderings* agree. **These α values are an upper bound:** α is computed on each (label, judge)'s *mean across rounds*, so round-to-round judge-sampler noise is averaged out before the reliability calculation — true per-round inter-judge α is *lower* than the values shown. The weighted-mean aggregation is less sensitive to any single judge's base rate but does not make raw scores robust to per-judge lenience drift — each report's *Per-judge z-normalized sensitivity* section is the actual mitigation for that; α is published as a separate honesty metric. Point estimates for α (n=40 units/task), σ_pool, and the per-judge z table are reported without confidence intervals — at this sample size their sampling error is non-trivial, so they should be read as descriptive rather than inferential; only the outlier-rate Wilson CI is reported (per-task report § Outlier audit).
- **Known judge-provenance defects.** Four of the 1800 judge files are named for the `gpt54pro` slot but their internal `judge` field records a different model: `bugfix/_blind-eval/Tango/gpt54pro-judge.json` (`openai-o3`), `bugfix/_blind-eval/Tango/round1/gpt54pro-judge.json` (`gpt-5`), `refactor/_blind-eval/Juliet/round1/gpt54pro-judge.json` (`openai-o3`), `refactor/_blind-eval/Xray/round2/gpt54pro-judge.json` (`gpt-5`). The aggregator dispatches by filename slot, so these 4 (0.22% of the corpus) are counted in the `gpt54pro` lane; they are **not** retroactively pulled (post-hoc removal of data after observing scores is itself a bias), but the aggregator now validates `.judge` against the slot and lists any mismatch in each per-task report's *Provenance Defects* section. This compounds the already-documented `gpt54pro` upstream model swap (t1–t3 = gpt-5.4-pro, t4+ = gpt-5.4; `versions.lock.json`). **Measured sensitivity** (rebuild excluding the 4 files, identical pipeline): **zero rank swaps on any task**; max |Δ_weighted-mean| = **0.46 pts on bugfix:`pure`** (rank-3, unchanged — the `ecc`−`pure` bugfix gap shifts from 2.78 to 3.23, both far below the 22.17-pt bugfix MDE); refactor moves are `claudekit` +0.22 and `compound` +0.11 (no rank change); feature is unaffected (no mismatched files in the feature corpus). An earlier version of this bullet estimated "sub-0.1 pt" from the 4/1800 corpus fraction; the measured per-cell shift is ~5× larger because 2 of 3 gpt54pro Tango (bugfix:`pure`) observations are affected, but the conclusion "immaterial to rankings" holds and the largest shift remains an order of magnitude below the bugfix MDE.
- **Outlier audit and rerun verdict.** Per the pre-registered rerun protocol (`CLAUDE.md` § Rerun), the cohort is audited for Tier-1 skill failures and Tier-2 round-level outliers by `scripts/compute-outlier-audit.py`. Result: 0 skill failures across the **63 t1–t3 cells** (7 non-baseline tools × 3 tasks × 3 trials) where a `session-audit.json` exists — t4–t5 session audits were not collected, so the skill-failure trigger is evaluated over t1–t3 only, not the full n=5 cohort; Tier-2 outlier rates of 4.17% / 3.67% / 1.33% on feature / bugfix / refactor (vs ~5% expected under 2σ chance) — point estimates at or below the chance baseline, though the per-task 95% CIs straddle it (the aggregate result is consistent with chance, not significantly below it), and the per-round 2σ trigger did fire on the individual flagged rounds. No reruns are triggered; selective re-rolling of flagged rounds would bias the cohort toward the mean by re-rolling extreme values while keeping in-distribution ones.
- **Judge sampling not pinned.** Temperature is set to 0 where the provider exposes it; Claude CLI and OpenAI Responses do not expose temperature/seed.
- **Equal-weight is a comparator, not a neutral estimator.** The 3 / 2 / 1 / 1 / 1 weighting is an operator choice declared in `versions.lock.json` and pre-registered as of 2026-05-12. The equal-weight companion (`final-report.equal-weight.md`) is published alongside as a sensitivity check; rank-1 is identical across both schemes on every task in this corpus, but middle ordering can swap by 1–2 positions.
- **R1 override is post-hoc.** It rewrites LLM scores using deterministic mechanical facts. The override is declared in the methodology and is fully auditable (`scores_pre_r1` preserved per file), but it does shift weighted means; without R1, ranks would still hold but absolute scores would drift on the affected items.
- **Not preregistered.** Tasks, rubric, judge panel, weight scheme, and R1 lock list were chosen iteratively by the operator. The weight scheme is written into `versions.lock.json` before aggregation, but the prior choice of tasks and rubric items is not preregistered.
- **Tool version snapshot, 2026-05.** Each tool was run at the version captured in `versions.lock.json` `tools.*`. Subsequent versions may change the ranking.
- **Cohort symmetry — soft.** All 40 labels per task land on the pinned base SHA, but the feature cohort span is 181.0h (bugfix 149.7h, refactor 146.6h), driven by the staged t1–t5 trial expansion plus the leak-fix re-judge pass. Provider model behaviour can drift across multi-day windows. The leak-fix rerun covered the 6 labels with detected fingerprints (claudekit×3, omc×1, gstack×1, superpower×1); the remaining 4 tools (`pure`, `bmad`, `compound`, `ecc`) had no labels in the leak set and were not re-judged. Coverage is symmetric across the *leak set*, not across all 40 feature labels — this is a known deviation from the strict cohort-rerun rule and is disclosed here rather than reframed as a full symmetric rerun.

## 5. Sensitivity

A short rank-stability table under the weighted-mean rule vs. equal-weight pooled mean (each task's rank-1 is bolded):

| Task | Rank-1 (weighted) | Rank-1 (equal-weight) | Identical top-3? |
|---|---|---|---|
| feature | **ecc** (153.30) | **ecc** (157.11) | **no** — weighted: ecc / pure / bmad; equal: ecc / bmad / pure |
| bugfix | **claudekit** (178.93) | **claudekit** (181.53) | yes — claudekit / ecc / pure |
| refactor | **pure** (180.19) | **pure** (182.63) | **no** — weighted: pure / claudekit / bmad; equal: pure / claudekit / superpower |

Rank-1 is stable under both aggregation rules on every task. Top-3 is identical under both rules on `bugfix`; on `feature` and `refactor` it reorders at rank-2/3. Mechanically, equal pooling moves each judge to weight 0.20 (vs the weighted scheme's opus = 0.375, `GPT-5.4` = 0.25, others = 0.125), so equal pooling **downweights opus and `GPT-5.4`** and **upweights `grok420` / `glm51` / `mimo25pro`**. On `feature`, `bmad` rises from weighted rank-3 to equal-weight rank-2: its opus mark (138.7) is well below its grok420 / mimo25pro marks (164.5 / 160.8), so de-emphasising opus lifts it past `pure` (opus 142.5). On `refactor` the rank-3 swap is margin-thin — weighted `bmad` 177.74 vs `superpower` 177.56; under equal weight `superpower` (pooled 180.51) edges ahead of `bmad` (180.08). Mid-pack rank-4 to rank-7 swap by at most 2 positions between rules; rank-8 is stable. The full equal-weight ranking lives in `results/{,bugfix/,refactor/}final-report.equal-weight.md`.

## 6. Reproducibility

The full pipeline is reproducible from [`infina-pfa/claude-tool-benchmark`](https://github.com/infina-pfa/claude-tool-benchmark). Set `BENCH_REPO` to a clone URL of your target repository (this paper's corpus uses a private TypeScript NX monorepo), then:

```bash
# 1. Fresh clone of the base repo for (task, trial):
TASK=refactor ./scripts/create-clones.sh 1 2 3

# 2. Execute the tool on the task (per trial):
TASK=refactor ./scripts/manual-bench.sh bmad 1

# 3. Generate blind-eval labels + mapping (path/content scrub + auto-metrics anonymisation):
TASK=refactor ./scripts/blind-eval-setup.sh

# 4. Judge every label × 5 judges:
TASK=refactor ./scripts/judge-all.sh            # no args = judge every label in the mapping

# 5. Per-task aggregation (R1 sweep + weighted-mean + equal-weight comparator):
TASK=refactor ./scripts/aggregate-results.sh

# 6. Cohort-symmetry audit:
python3 scripts/audit-cohort-symmetry.py
```

**Canonical aggregation rules** (enforced in `scripts/aggregate-results.sh`):

- **Round filter:** the label root plus dirs matching `^round[0-9]+$`, in union. Pilot/sample dirs (`roundcotsample*`, etc.) are excluded so the corpus size is deterministic.
- **Score per judge file:** `sum(scores.values())` (the stored `total` field is ignored).
- **Tool mean:** weighted mean of per-judge means with weights pre-registered in `versions.lock.json` `judges.*.weight` (mirrored as a hardcoded constant in `scripts/aggregate-results.sh`; synced manually). Missing judges drop out of both numerator and denominator.
- **R1 sweep:** `scripts/apply-r1-override.py` runs idempotently before every aggregation; pre-override scores are preserved per file under `scores_pre_r1`.
- **Equal-weight comparator** is emitted as `final-report.equal-weight.md` alongside the weighted report.

All raw judge JSONs are committed under `results/<task>/_blind-eval/<LABEL>/<judge>-judge.json`, alongside `judge-prompt.md` (the full prompt including rubric) and `implementation-diff.patch` (the artifact being judged). Label → `(tool, trial)` mapping is at `.mapping-DO-NOT-OPEN.json` in each `_blind-eval/`.

## 7. Conclusion

The strongest claim this data supports is: **on three mid-sized TypeScript tasks under a pinned `claude-opus-4-7` executor and a 5-judge × 3-round weighted panel, no Claude Code setup is statistically distinguishable from rank-2 on any task — every per-task rank-1 lead falls below the exact-t MDE, and the only pairwise gap that clears its task MDE anywhere in the corpus is `ecc`−`gstack` on `feature`.** By point estimate the ordering is task-dependent (`ecc` rank-1 on `feature`, `claudekit` on `bugfix`, `pure` on `refactor`) and the bare baseline is never meaningfully outperformed on `bugfix`/`refactor`, but these orderings are point-estimate only and must not be read as a ranking. No setup is top-2 on all three tasks. Rank-1 is stable across weighted and equal-weight aggregation rules on every task; top-3 is stable on `bugfix` but reorders on `feature` (and swaps at rank-3 on `refactor`) under equal weighting. Inter-judge calibration drift remains large — the `mimo25pro` − `GPT-5.4` gap is 32 pts on bugfix, ~38 on feature, ~39 on refactor, with `GPT-5.4` running ≈ 19–27 pts below the per-task panel mean — which the 5-judge weighted panel and the within / between σ decomposition (now estimated on 15 samples per (tool, judge) thanks to the 5-trial × 3-round layout) are designed to expose rather than hide. The full corpus (1800 judgments) is published for independent re-scoring and re-analysis.

## Appendix A — Per-task report files

| Path | Contents |
|---|---|
| [`results/final-report.md`](https://github.com/infina-pfa/claude-tool-benchmark/blob/main/results/final-report.md) | feature, weighted-mean ranking + caveats |
| [`results/final-report.equal-weight.md`](https://github.com/infina-pfa/claude-tool-benchmark/blob/main/results/final-report.equal-weight.md) | feature, equal-weight comparator |
| [`results/bugfix/final-report.md`](https://github.com/infina-pfa/claude-tool-benchmark/blob/main/results/bugfix/final-report.md) | bugfix, weighted-mean ranking + caveats |
| [`results/bugfix/final-report.equal-weight.md`](https://github.com/infina-pfa/claude-tool-benchmark/blob/main/results/bugfix/final-report.equal-weight.md) | bugfix, equal-weight comparator |
| [`results/refactor/final-report.md`](https://github.com/infina-pfa/claude-tool-benchmark/blob/main/results/refactor/final-report.md) | refactor, weighted-mean ranking + caveats |
| [`results/refactor/final-report.equal-weight.md`](https://github.com/infina-pfa/claude-tool-benchmark/blob/main/results/refactor/final-report.equal-weight.md) | refactor, equal-weight comparator |

## Appendix B — Versions

All version pins (claude-cli, base model, 8 tool setups, 5 judges, base SHAs per task, weight scheme) are captured in [`versions.lock.json`](https://github.com/infina-pfa/claude-tool-benchmark/blob/main/versions.lock.json). The weight scheme was pre-registered on 2026-05-12.

---
*Comments, corrections, and independent re-analyses welcome — file an Issue on the [repo](https://github.com/infina-pfa/claude-tool-benchmark/issues).*
