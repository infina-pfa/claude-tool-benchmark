# Improvement plan — next cohort

This document tracks the four compute-heavy improvements that cannot be implemented
in a single editing session. Each item has a budget estimate, a trigger condition,
and the concrete commands needed to execute. Operators should pick one and run
to completion before starting the next — partial cohorts violate the cohort-symmetry
rule (`scripts/audit-cohort-symmetry.py`).

The four analysis-side improvements (Krippendorff α, MDE / power analysis,
per-judge z-normalized sensitivity, per-trial skill-fired column) are already
in `scripts/aggregate-results.sh` and re-emitted on every report regeneration.

> **Cohort baseline (current).** The v2 cohort now runs **N=5 trials per cell** — 8 tools × 3 tasks × 5 trials = **120 tool runs**, **1800 judgments**, **75 per (tool,task) cell** (5 trials × 5 judges × 3 rounds). Item #1 below (the N=3→5 trial expansion **and** the n=5 MDE recompute) is **complete**. Wherever items #7/#8 say "same as the original cohort", read the current 120-trial / 1800-judgment baseline.

---

## #1 — Trial count N=3 → N=5 per cell  ·  **STATUS: COMPLETE (trials shipped + n=5 MDE recomputed)**

**Shipped**: the two additional trials per cell were run and judged; the cohort is N=5 (1800 judgments, 75 per (tool,task)). `results/power-analysis.json` and every per-task report now compute MDE at the actual n=5, and PAPER / README / landing / announcements have been resynced to it.

**Outcome (note — counterintuitive)**: the n=3 σ_pool *under-estimated* true trial-to-trial variance, so expanding to n=5 did **not** cut MDE the way 1/√n predicts. MDE now uses the exact Student-t critical value t(0.975, df=2(n-1)=8) ≈ 2.306 rather than the normal z=1.96 (at n=5 this enlarges MDE ~12%); the β/power term retains the normal z=0.84 as a deliberate conservative approximation. σ_pool rose on every task (feature 7.87→9.72, bugfix 9.99→11.14, refactor 6.07→22.13), so MDE did **not** scale down as 1/√n — it held roughly flat on feature, eased modestly on bugfix, and blew up on refactor. The refactor blow-up is driven by `gstack`'s trial-4 refactor diff scoring ≈36/200 against ~178 on its other four — a mechanically clean run (tsc 0, 77/77 tests, real 504/73 diff, slash commands fired), so a **valid in-distribution trial** under the pre-registered no-selective-rerun rule. Net effect: every rank-1 lead is below MDE (feature 10.17, bugfix 6.62, refactor 2.15) and the **only** separation clearing MDE anywhere in the corpus is `ecc` − `gstack` on feature (≈21.3 > 19.33). The "statistically tied" headline got *stronger*, and the rising MDE is itself the empirical proof of why the protocol bars post-hoc selective reruns.

**Budget**: the 48 additional trials + judging (~$60, ~24h supervised ops) and the analysis-side recompute are all **spent**. No open cost.

**Trigger condition**: closed. Future cohorts wanting *significant* top-cluster differences need a different lever (lower trial variance or more trials than 5), not this item.

**Runbook (executed)**:
```bash
# Trials + judging: DONE (cohort is N=5).
# n=5 MDE recompute: DONE — compute-power-analysis.py now derives n from the
# per-arm trial count (no flag), aggregate-results.sh re-emits the n=5 figure.
python3 scripts/compute-power-analysis.py
TASK=feature ./scripts/aggregate-results.sh
TASK=bugfix  ./scripts/aggregate-results.sh
TASK=refactor ./scripts/aggregate-results.sh
node tooling/render-md-previews.mjs
```

**Pre-registration**: the N=3 → N=5 move was an additive expansion (no trials dropped), so there was no re-aggregation hazard; the cohort change is recorded in `versions.lock.json`.

---

## #4 — Replace refactor task with a harder one (or drop it from cross-task)

**Why (re-evaluate at n=5 — original premise inverted)**: at the n=3 single-round snapshot refactor looked informationally null (K-α = −0.085, judges disagreeing more than chance). **The n=5 corpus inverts this**: refactor K-α is now **0.626** — the *highest* of the three tasks (judges agree most on refactor). But the n=5 power analysis cuts the other way too: refactor σ_pool is **22.13** (one arm, `gstack` trial-4 ≈36/200, dominates it) and the n=5 refactor MDE is **44.02 pts**, so *no* refactor separation is statistically significant — not even gstack's 35.3-pt gap to rank-1. So refactor both (a) has the most judge agreement and (b) statistically discriminates *nothing* at n=5. The original "informationally null / replace it" rationale is superseded by a more precise reading; treat #4 as **re-evaluate against the n=5 evidence, trigger no longer clearly met** rather than a recommended action.

**Two paths**:

### Path A — Drop refactor from cross-task synthesis (free, immediate)

Edit `docs/index.html` cross-task section to compute z̄ over only `feature` + `bugfix`. Per-task refactor results stay published; just remove from the leaderboard. **Budget**: 30 minutes. **Risk**: cross-task narrative shrinks; rank ordering changes (recompute z̄ over 2 tasks).

### Path B — Replace refactor with a harder task (full new cohort)

Pick a refactor that actually discriminates. Candidate criteria (Tested against a pilot pure-baseline trial):
- Inter-module API change spanning 3+ packages
- ≥ 200 LOC of co-evolving change with a non-trivial type-graph rewrite
- Has a known correct/incorrect outcome (e.g., a ground-truth diff exists)
- Pure baseline scores ≤ 70/200 in one pilot trial (otherwise too easy)

**Budget**: identical to #1 minus the bugfix/feature components → 24 tool trials + 360 judgments. ~2 weeks calendar time including PRD design + pilot.

**Recommendation**: Path A first (publish honest narrative this quarter). Path B for the next major cohort.

---

## #7 — Second executor base model (Sonnet 4.6)

**Why**: caveat 02 names this. All current trials use `claude-opus-4-7`. Whether the rankings carry to a weaker base model is the strongest open question. If addon-vs-pure gaps shrink on Sonnet, that's the meaningful finding ("addons help most where the base model is strongest"); if they grow, that's also meaningful ("addons compensate for a weaker base").

**Minimal version**: 1 trial × 8 tools × 1 task (bugfix — fastest and most discriminating). 8 trials, ~2 hours operator time, 40 new judgments.

**Full version**: 3 trials × 8 tools × 3 tasks = 72 new tool runs. Same budget as the original cohort. ~2 weeks calendar time.

**Budget (full)**:
- Operator-attended trials: ~24 hours of supervised runs.
- Token cost: ~50M input + ~5M output (Sonnet is faster but our tools may issue more turns).
- Judging cost: 72 × 5 × 3 = 1080 new judgments ≈ ~$90.

**Runbook**:
```bash
# 1. Pin the second base model
echo '{"executor_base_model": "claude-sonnet-4-6"}' > config/executor-sonnet.json

# 2. Override CLAUDE_MODEL in env.sh for the new cohort
export CLAUDE_MODEL=claude-sonnet-4-6

# 3. Re-run the original 72-trial cohort with the new model
# (use a separate results/ subtree to keep them comparable)
mkdir -p results-sonnet
TASK=bugfix ./scripts/create-clones.sh 1 2 3 --base-model sonnet --out results-sonnet
TASK=bugfix ./scripts/manual-bench.sh ecc 1
# … repeat per cell

# 4. Aggregate into a separate report
TASK=bugfix RESULTS_DIR=results-sonnet ./scripts/aggregate-results.sh

# 5. Diff the rankings
python3 scripts/cross-cohort-diff.py results/final-report.md results-sonnet/final-report.md
```

**Trigger condition**: required for any claim of the form "tools X, Y, Z generalize" or "tool X is most reliable". Currently the benchmark is honest that it does not test this.

---

## #8 — Second codebase / language

**Why**: caveat 01 names this. Current cohort is one TypeScript NX monorepo. Generalization to Python / Go / Rust is unverified.

**Minimal version**: pick one Python repo (e.g., a clean FastAPI service of ~5kLOC) and one task type (bugfix again — fastest). 8 trials + 40 judgments + new PRD design. ~3 days operator time.

**Full version**: same task taxonomy (feature / bugfix / refactor) on 1 new codebase. Same budget as the original cohort, plus ~1 week of PRD design and pilot judging. ~3 weeks calendar time.

**Budget (full)**:
- PRD design: 40 hours (one operator-week)
- Pilot judging: 8 trials × 5 judges = 40 judgments to confirm rubric items map sensibly to the new repo
- Full cohort: 72 trials + 1080 judgments → same as original
- Token cost: ~80M input total

**Runbook**:
```bash
# 1. Pick + clone the second codebase
git clone https://github.com/<org>/<python-repo> ../bench-python-repo

# 2. Author 3 PRDs (feature/bugfix/refactor) over the new codebase
# Use the existing PRDs as templates — same rubric items must map cleanly
mkdir -p results-python/{feature,bugfix,refactor}/_blind-eval
$EDITOR results-python/feature/_blind-eval/prd.md
# … see PAPER §1 for PRD design checklist

# 3. Pilot one trial per task with pure to verify rubric coverage
TASK=feature BENCH_REPO=../bench-python-repo RESULTS_DIR=results-python ./scripts/manual-bench.sh pure 1

# 4. Inspect judge JSONs — every rubric item should have a non-zero score
# If 5+ items collapse to 0/N for the pilot, rewrite the rubric mapping

# 5. Run the full cohort once the rubric is stable
TASK=feature BENCH_REPO=../bench-python-repo RESULTS_DIR=results-python ./scripts/create-clones.sh 1 2 3
# … repeat per (task, tool, trial)
```

**Trigger condition**: required for any cross-language generalization claim. Optional otherwise (current scope is honestly described as "TypeScript only" in caveat 01).

---

## Decision matrix

| Item | Cost | Calendar | Statistical impact | Narrative impact |
|---|---|---|---|---|
| #1 N=3→5 | $60 + 24h ops | 1 week | **COMPLETE** | Done — MDE *rose* (σ underestimated at n=3); headline unchanged (still tied) |
| #4 Path A (drop refactor) | $0 | 30 min | Medium (cleaner cross-task) | High (more honest narrative) |
| #4 Path B (replace refactor) | $90 + 1wk PRD | 3 weeks | High | Medium |
| #7 Sonnet base (full) | $90 + 24h ops | 2 weeks | **High** (resolves caveat 02) | High (new finding either way) |
| #8 Python codebase (full) | $200 + 1wk PRD | 3 weeks | High (resolves caveat 01) | High (generalization claim) |

**Suggested order**:
1. #4 Path A — free, immediate honesty win.
2. #1 — biggest statistical-power gain per dollar.
3. #7 minimal version (1 task × 1 trial) — cheapest exploration of caveat 02.
4. #7 full or #8 minimal — pick based on which caveat (model vs language) is most cited by readers.
