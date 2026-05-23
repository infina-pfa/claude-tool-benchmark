# AI Coding Tool Benchmark

A multi-task, 5-judge evaluation of **8 Claude Code setups** (plugins, skill packs, hook kits, and a no-addon baseline) on 3 real-world software-engineering tasks from the a private TypeScript NX monorepo monorepo. All runs on `claude-opus-4-7`.

- **[PAPER.md](https://github.com/infina-pfa/claude-tool-benchmark/blob/main/PAPER.md)** — research-paper-style report (method, results, caveats, reproducibility)
- **[results/final-report.md](https://github.com/infina-pfa/claude-tool-benchmark/blob/main/results/final-report.md)** — feature task, weighted-mean ranking + caveats
- **[results/bugfix/final-report.md](https://github.com/infina-pfa/claude-tool-benchmark/blob/main/results/bugfix/final-report.md)** — bugfix task
- **[results/refactor/final-report.md](https://github.com/infina-pfa/claude-tool-benchmark/blob/main/results/refactor/final-report.md)** — refactor task
- **[docs/README.md](https://github.com/infina-pfa/claude-tool-benchmark/blob/main/docs/README.md)** — docs folder index (guides, tool profiles, analysis)
- **[docs/guides/verification.md](https://github.com/infina-pfa/claude-tool-benchmark/blob/main/docs/guides/verification.md)** — how to independently verify any claim
- **[PAPER.md §6](https://github.com/infina-pfa/claude-tool-benchmark/blob/main/PAPER.md#6-reproducibility)** — end-to-end run/judge/aggregate pipeline

---

## TL;DR — Rank-1 by task (weighted mean / 200)

| Task | Rank 1 | Rank 2 | Rank 3 | Cohort spread |
|---|---|---|---|---|
| feature  | **ecc** (153.30) | pure (143.13) | bmad (141.33) | top-to-bottom span 21.3 |
| bugfix   | **claudekit** (178.93) | ecc (172.31) | pure (169.53) | top-to-bottom span 19.0 |
| refactor | **pure** (180.19) | claudekit (178.04) | bmad (177.74) | gstack collapses to 144.92 (−25 vs rank-7) |

**No rank-1 lead is statistically significant.** The rank table above is **point-estimate only**: under the exact Student-t detection threshold every per-task rank-1 gap falls below MDE, and the *only* pairwise gap that clears its task MDE anywhere in the 1800-judgment corpus is `ecc`−`gstack` on `feature`. `ecc` is rank-1 on `feature`, `claudekit` on `bugfix`, `pure` (no addons) on `refactor` **by point estimate only — none is distinguishable from rank-2 at standard significance**; no setup is top-2 on all three tasks. The per-task reports compute MDE at the cohort's actual **n=5** trials per arm using the **exact Student-t critical value** for df=2(n-1)=8 (t≈2.306, not the normal z=1.96 — at n=5 this enlarges every MDE ~12%): **19.33 pts (feature) · 22.17 (bugfix) · 44.02 (refactor)** (α=0.05 two-sided, power=0.80; σ_pool 9.72 / 11.14 / 22.13; β-term keeps the normal z=0.84 as a conservative approximation; see `results/power-analysis.json`). Expanding from n=3 → n=5 did **not** scale MDE down as 1/√n: σ_pool rose on every task (more trials exposed larger true trial-to-trial variance), most sharply on refactor — driven by one high-variance arm, `gstack`, whose trial-4 refactor diff judges scored ≈36/200 against ~178 on its other four (a mechanically clean run, so a valid in-distribution trial under the pre-registered no-selective-rerun rule). The rank-1 leads (feature 10.17, bugfix 6.62, refactor 2.15 pts) all fall well below MDE: the top-cluster orderings are *point-estimate first, statistically tied.* No rank-1 lead on any task clears MDE; under the exact-t threshold the **only** separation that clears MDE anywhere in the corpus is `ecc` − `gstack` on `feature` (21.3 > the 19.33 feature MDE). An earlier z-based analysis additionally flagged `ecc` − `claudekit` (18.3) and `ecc` − `compound` (18.6) as clearing the feature MDE; both fall **below** MDE under the corrected exact-t critical and are no longer treated as separations. No separation clears MDE on `bugfix` or `refactor`. An earlier version of this paragraph claimed `claudekit − pure` rejected the strict null on bugfix based on a heuristic ~5-pt tie envelope; the formal power analysis retracts that claim (9.4 ≪ 22.17). `pure` is top-3 on every task and rank-1 on refactor — the strongest counter-claim to the "you need addons" prior, *within the tie band.* Rank-1 is stable across weighted-mean (opus×3, gpt54pro×2, others×1) and equal-weight aggregation on every task; top-3 is identical under both rules on bugfix, and reorders within the top cluster on feature (weighted ecc / pure / bmad vs equal-weight ecc / bmad / pure) and refactor (weighted rank-3 bmad vs equal-weight rank-3 superpower). Inter-rater agreement is low for absolute scores (Krippendorff α: feature 0.124, bugfix 0.284, refactor 0.626 — punished by lenience drift; refactor (0.626) sits just below the tentative band, feature/bugfix far below; **these α are an upper bound — computed on round-averaged scores, so true per-round agreement is lower**); the weighted mean and the per-judge z-normalized sensitivity column are the intended mitigations. `between_σ > within_σ` on 19 of 24 (tool, task) cells — the dominant uncertainty is judge disagreement, not tool instability. Outlier audit: 0 skill-failure triggers (evaluated over the t1–t3 cells where session audits exist), per-task round-outlier rates 4.17% / 3.67% / 1.33% (feature / bugfix / refactor; 55 of 1800 pooled ≈ 3.1%) vs ~5% 2σ-chance baseline — point estimates at/below chance but 95% CIs straddle it → **no reruns triggered**. **Corpus:** 1800 judgments (3 tasks × 8 tools × 5 trials × 5 judges × 3 rounds). **Preregistration scope:** only the judge weights and the rerun protocol are pre-registered; the tasks, the 20-item rubric, the judge panel, and the R1 mechanical-fact lock list were operator-iterative (see PAPER §4 "Not preregistered"). Treat the rankings as descriptive — the strongest claim this design supports is the *negative result* (no rank-1 lead clears MDE on any task) and the *calibration-study* finding (α=0.124 on feature means LLM judges fundamentally disagree on absolute scores), not a confirmatory leaderboard. See [PAPER.md §2](https://github.com/infina-pfa/claude-tool-benchmark/blob/main/PAPER.md#2-results) for per-task tables, [§4](https://github.com/infina-pfa/claude-tool-benchmark/blob/main/PAPER.md#4-limitations-and-threats-to-validity) for threats to validity, and [`docs/IMPROVEMENT-PLAN-NEXT-COHORT.md`](docs/IMPROVEMENT-PLAN-NEXT-COHORT.md) for the runbook to raise statistical power.

---

## Reproduce

```bash
# One (task, tool, trial) run:
TASK=refactor ./scripts/create-clones.sh 1
TASK=refactor ./scripts/manual-bench.sh bmad 1

# Blind labels + mapping (path/content scrub + auto-metrics anonymisation):
TASK=refactor ./scripts/blind-eval-setup.sh

# Judge every label × 5 judges:
TASK=refactor ./scripts/judge-all.sh            # no args = judge every label in the mapping

# Aggregate per-task (R1 sweep → weighted-mean → equal-weight comparator):
TASK=refactor ./scripts/aggregate-results.sh

# Cohort-symmetry audit:
python3 scripts/audit-cohort-symmetry.py
```

See **[PAPER.md §6](https://github.com/infina-pfa/claude-tool-benchmark/blob/main/PAPER.md#6-reproducibility)** for the full pipeline and judge-prompt locations. All script sources live under [`scripts/`](https://github.com/infina-pfa/claude-tool-benchmark/tree/main/scripts).

---

## Layout

```
scripts/                 — pipeline (create-clones, manual-bench, judge-*, aggregate)
docs/                    — task briefs, pipeline notes, tool profiles, analyses
config/                  — per-tool config templates
results/
  final-report.md        — feature, weighted-mean + caveats
  final-report.equal-weight.md — feature, equal-weight comparator
  _blind-eval/           — feature judged artifacts (5-judge panel × 3 rounds per artifact)

  bugfix/, refactor/     — task-scoped results (per-task final-report.md inside)
  <tool>/t<N>/           — per-trial execution artifacts
versions.lock.json       — base model, 5-judge panel + weights, 8 tool versions, base SHAs
CLAUDE.md                — internal operator notes
```

Browse the tree on GitHub: [infina-pfa/claude-tool-benchmark](https://github.com/infina-pfa/claude-tool-benchmark).

---

## Caveats

> **Framing — approve-only "vibecode" execution.** Trials are run by an operator who accepts whatever each tool proposes — no mid-flight steering, no plan rejection, no "try a different approach". The per-tool slash command is fired once and the operator only clicks through permission prompts. This deliberately measures *autonomous one-shot capability under a pinned base model*. Setups whose realised quality depends on iterative human feedback (plan revision, rejecting a sub-task, mid-edit course correction) will rank lower here than they would in interactive pair-programming use. Read these rankings as **"best when the operator just keeps approving"**, not as a measure of effectiveness with human-in-the-loop steering — a tool that ranks second here under vibecode may well rank first under active human direction.

1. **Single codebase, single language** (a private TypeScript NX monorepo). Don't assume these rankings generalize to Python/Go/Rust.
2. **Single executor base model** (`claude-opus-4-7`). A setup that specializes on sonnet/haiku/GPT/Gemini may rank differently.
3. **Self-preference is not identified.** Every executor uses an Anthropic base, so we cannot disentangle Anthropic-family judge favouritism from intrinsic judge-calibration drift; this benchmark deliberately does not report a self-preference diagnostic. As non-causal descriptive checks (not self-preference estimates), the equal-weight comparator and each report's per-judge z-normalized sensitivity section show rank-1 is stable when opus's 3× weight and per-judge base rates are removed.
4. **LLM judges diverge by 32–42 pts (full panel spread, per task).** `gpt54pro` is consistently the harshest scorer (19–27 pts below the per-task panel mean), `mimo25pro` the most lenient. The 5-judge weighted panel (opus×3, gpt54pro×2, grok420/glm51/mimo25pro×1, pre-registered in `versions.lock.json`) is the intended mitigation; an equal-weight comparator is emitted alongside every report for sensitivity. Rank-1 is stable under both rules on every task in this corpus; top-3 is identical on bugfix, and reorders within the top cluster on feature and refactor (see TL;DR above and PAPER §5). **Judge-model note:** the `gpt54pro` slot is heterogeneous across the cohort — t1–t3 answered as `gpt-5.4-pro` (OpenAI `/v1/responses`), t4+ as `gpt-5.4` (local cliproxy); the slot key is frozen for aggregation continuity. Full provenance in `versions.lock.json` `judges.gpt54pro.routing_history` and PAPER §1.6 / §2.5.
5. **`between_σ > within_σ` on 19 of 24 (tool, task) cells.** The five exceptions are `claudekit` (within 11.42 vs between 9.35), `ecc` (13.54 vs 11.70), `pure` (12.05 vs 9.58) and `omc` (15.66 vs 13.74) on bugfix, plus `gstack` on refactor (within 58.43 vs between 12.52 — one trial scored far below gstack's other four). On the remaining 19 cells most variance is judge disagreement, not tool instability. Close rank pairs (within ~5 weighted pts) should be read as ties.
6. **R1 mechanical-fact override is post-hoc.** Deterministic rubric items (tsc/eslint counts, core-test failures, lines removed in scope-discipline) are rewritten from `auto-metrics.json` after judging. Pre-override scores are preserved per-file under `scores_pre_r1`; the sweep is idempotent and runs before every aggregation.
7. **Cross-task synthesis not reported as a canonical claim.** A single cross-task z̄ summary is sensitive to weighting (multi-rank swings in middle tiers across plausible weightings) and noisy even at 5 trials per cell; read the 3 per-task `final-report.md` files together rather than collapsing to a single leaderboard. The landing page renders an equal-weight z̄ visualization at the top of the page as a visual aid; it is explicitly labeled as such and is not the canonical ranking.
8. **Judge sampling not pinned.** Temperature is fixed to 0 where the provider exposes it (OpenRouter, OpenCode Go); Claude CLI and OpenAI `/v1/responses` do not expose temperature/seed.
9. **Not preregistered.** Tasks, rubric, judge panel, weight scheme, and R1 lock list were chosen iteratively. The weight scheme is committed to `versions.lock.json` before aggregation; earlier choices of tasks and rubric items are not preregistered. The leak-fix re-judge pass was symmetric over the 6 detected-leak labels, not all 40 feature labels — a disclosed deviation from the strict cohort-rerun rule (see PAPER §4).
10. **Tool-version snapshot, 2026-05.** Versions captured in [`versions.lock.json`](https://github.com/infina-pfa/claude-tool-benchmark/blob/main/versions.lock.json); re-run for current-version claims.

See **[PAPER.md §4](https://github.com/infina-pfa/claude-tool-benchmark/blob/main/PAPER.md#4-limitations-and-threats-to-validity)** for the full threats-to-validity list.

---

## License

Released under the MIT License — see [`LICENSE`](LICENSE). Copyright © 2026 Infina. Refer to each upstream tool for its own license. Source repository: [infina-pfa/claude-tool-benchmark](https://github.com/infina-pfa/claude-tool-benchmark).

## Citation

If you reference this benchmark, please cite:

```bibtex
@misc{infina2026claudetoolbenchmark,
  title        = {AI Coding Tool Benchmark: Blind, Multi-Judge Evaluation of Claude Code Setups},
  author       = {Quang Tran (Infina)},
  year         = {2026},
  howpublished = {\url{https://claude-tool-benchmark.pages.dev/}},
  note         = {Tool-version snapshot 2026-05; base model \texttt{claude-opus-4-7}}
}
```
