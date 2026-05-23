# Verification Guide — Reproducing the Benchmark Claims

Guide for a reader who wants to independently verify any claim made in [PAPER](../preview/paper.html), [README](../preview/readme.html), or the per-task `results/<task>/final-report.md` files. Everything needed is checked into `results/` — no private state, no network access.

---

## 0. Setup

```bash
git clone <this-repo>
cd ai-tool-benchmark
python3 -m pip install --user --break-system-packages numpy
```

Only `numpy` is needed for re-aggregation. The aggregation scripts use only stdlib + numpy, no framework.

---

## 1. "Where does a tool's score come from?"

**Claim example:** "`ecc` is rank-1 on feature with a weighted mean of 153.30/200."

**Chain of evidence:**

1. **Raw judge files** — for the canonical (first) round: `results/_blind-eval/<label>/{opus,grok420,glm51,gpt54pro,mimo25pro}-judge.json`, where `<label>` is whichever NATO letter maps to `ecc t<trial>` in `results/_blind-eval/.mapping-DO-NOT-OPEN.json`. The two added stability rounds live under `results/_blind-eval/<label>/round1/` and `results/_blind-eval/<label>/round2/` with the same five judge files in each. The aggregator unions the label root + every `^round[0-9]+$` subdir, so all three rounds are counted automatically; pilot/sample dirs (`roundcotsample*`, etc.) are excluded.
2. **Canonical score per file** — `sum(scores.values())` (authoritative; do not use the stored `total` field, which has historically drifted off-by-one).
3. **Canonical round filter** — `aggregate-results.sh` unions the label root (the canonical first round) with every `^round[0-9]+$` subdir (in this cohort: `round1/` and `round2/`). Pilot/sample dirs (`roundcotsample*`, etc.) are excluded so the corpus size is deterministic.
4. **R1 mechanical-fact override** — `scripts/apply-r1-override.py` rewrites deterministic rubric items from `auto-metrics.json` before aggregation. Pre-override scores are preserved per-file under `scores_pre_r1`.
5. **Aggregation** — `scripts/aggregate-results.sh` computes per-judge means, then the **weighted mean of per-judge means** with weights from `versions.lock.json` `judges.*.weight` (opus×3, gpt54pro×2, grok420 / glm51 / mimo25pro ×1). Equal-weight comparator is emitted alongside as `final-report.equal-weight.md`.
6. **Output** — `results/<task>/final-report.md`.

**To verify:**
```bash
# Snapshot the current committed report, then regenerate and compare.
cp results/final-report.md /tmp/final-report.feature.before.md
TASK=feature ./scripts/aggregate-results.sh
diff /tmp/final-report.feature.before.md results/final-report.md
```

The R1 sweep is idempotent, so the diff should be empty (modulo the regenerated timestamp). If not, either your dependency versions differ or the committed artifacts have drifted from their generating source.

---

## 2. "Why is `pure` rank-1 on refactor?"

**Claim example:** "On the aggregate-ownership refactor, `pure` (no addons) takes rank-1 at 180.19/200 over `claudekit` (178.04) and `bmad` (177.74). Top-5 span is 5.8 weighted pts."

**Walk the chain:**

1. `results/refactor/_blind-eval/.mapping-DO-NOT-OPEN.json` — find which labels map to `pure t1/t2/t3`.
2. `results/refactor/_blind-eval/<label>/implementation-diff.patch` — inspect the actual code diff the judges saw.
3. `results/refactor/_blind-eval/<label>/<judge>-judge.json` — read `notes` field and per-item rubric scores; compare to the next-ranked tool's labels.
4. `results/refactor/pure/t1/session-logs/<uuid>.jsonl` — the full session transcript.
5. `results/refactor/pure/t1/auto-metrics.json` — tsc / eslint / test counts, line changes.

**Cross-reference:** [PAPER §2.1 refactor](../preview/paper.html#21-per-task-rankings) and [§3 Discussion](../preview/paper.html#3-discussion) narrate this result.

---

## 3. "No hidden sampling of trials / no cherry-picking reruns"

**Claim example:** The cohort-symmetry rule (enforced by `scripts/audit-cohort-symmetry.py`) requires that if trial `t<N>` is rerun for one tool, it's rerun for all 8 before the trial is used in comparison.

**Verify:**

```bash
python3 scripts/audit-cohort-symmetry.py
```

Reads `results/<task>/<tool>/t<N>/sessions/*.meta.json` across all 8 tools, groups by trial index, and reports:
- Missing trials per tool (hard violation → non-zero exit)
- Base-commit divergence within a trial (hard violation → non-zero exit)
- >24h cohort timestamp span (soft warning — flagged in each task's `final-report.md` "Caveats" block)
- Any archived reruns under `results/<task>/<tool>/archive-t<N>-<date>/`

---

## 4. "The judge didn't see the tool identity"

**Verify:**

1. Open any `results/<task>/_blind-eval/<label>/judge-prompt.md`. Confirm nothing in the prompt names the tool.
2. Open `implementation-diff.patch` in the same dir. Confirm the diff uses paths from the actual repo (no tool-specific markers like `.omc/`, `_bmad/`, `.claudekit/`, `.superpowers/`, etc.).
3. Open `auto-metrics.json` in the same dir. Confirm `plugin_versions` and `collected_at` have been stripped (anonymisation).
4. Open `.mapping-DO-NOT-OPEN.json` only after you've formed your own expectation.

The judge receives: PRD + reference codebase markdown + the diff patch + the 20-item rubric + JSON schema. Nothing else.

---

## 5. "The judges use the canonical model settings"

**Claim example:** "Temperature is fixed to 0 where the provider exposes it (OpenRouter, OpenCode Go); Claude CLI and OpenAI `/v1/responses` do not expose temperature/seed."

**Verify:**

```bash
claude --help | grep -iE 'temp|seed|sampl'        # Claude CLI — no results
opencode run --help | grep -iE 'temp|seed|sampl'  # OpenCode CLI — exposes temperature
```

Comment headers in `scripts/judge-{opus,grok420,glm51,gpt54pro,mimo25pro}.sh` document this per-judge. Round-to-round variance shows up as `within_σ` in each `final-report.md`; the 5-judge weighted panel is the intended mitigation, not a fix.

---

## 6. "The ranking doesn't flip under different weighting"

**Canonical ranking** is the **weighted mean** (`final-report.md`, panel weights opus×3 / gpt54pro×2 / others×1, pre-registered in `versions.lock.json`). The equal-weight pass (`final-report.equal-weight.md`) is a sensitivity check, not a second canonical ranking.

**Claim example:** "Rank-1 is stable under both weighted-mean (3/2/1/1/1) and equal-weight aggregation on every task; top-3 is identical on bugfix only — feature top-3 reorders under equal weighting (ecc / pure / bmad → ecc / bmad / pure) and refactor swaps at rank-3 (bmad → superpower)."

**Verify:**

For each task, compare `final-report.md` (canonical, weighted) against `final-report.equal-weight.md` (equal-weight sensitivity). They are written by the same `aggregate-results.sh` pass.

```bash
for task in feature bugfix refactor; do
  case $task in feature) dir=results;; *) dir=results/$task;; esac
  echo "=== $task ==="
  grep -E '^[0-9]+\. \*\*' $dir/final-report.md | head -3
  echo "--- equal-weight ---"
  grep -E '^[0-9]+\. \*\*' $dir/final-report.equal-weight.md | head -3
done
```

Expected: rank-1 identical across both columns on every task; top-3 identical on bugfix only; feature top-3 reorders (weighted: ecc / pure / bmad; equal-weight: ecc / bmad / pure) and refactor swaps at rank-3 (weighted bmad; equal-weight superpower — see PAPER §5).

---

## 7. R1 mechanical-fact override

**Claim example:** "Deterministic rubric items (tsc / eslint / core-test failures / lines removed) are rewritten from `auto-metrics.json` after judging. Pre-override scores are preserved per-file."

**Verify:**

```bash
# Count: every judged file (across all 3 rounds) should carry a scores_pre_r1 snapshot.
python3 -c "
import json, pathlib
files = [f for f in pathlib.Path('results').rglob('*-judge.json')
         if '_blind-eval' in f.parts and '_archive' not in f.parts
         and 'request' not in f.name and 'raw' not in f.name]
total = len(files); with_snap = sum(1 for f in files if 'scores_pre_r1' in json.loads(f.read_text()))
print(f'{with_snap}/{total} files carry scores_pre_r1')
"
```

Expected: `1800/1800 files carry scores_pre_r1` (3 tasks × 8 tools × 5 trials × 5 judges × 3 rounds). The locked items per task are documented in [PAPER §1.5](../preview/paper.html#15-r1-mechanical-fact-override).

---

## 8. Reproducing the pipeline end-to-end

If you want to re-run the benchmark (not just re-aggregate):

See **[`quickstart.md`](quickstart.md)** for the full clone → execute → judge → aggregate flow and **[PAPER §6](../preview/paper.html#6-reproducibility)** for the canonical pipeline reference.

**Minimum re-run for one (task, tool, trial):**

```bash
TASK=refactor ./scripts/create-clones.sh 1
TASK=refactor ./scripts/setup-tool-config.sh bmad 1
TASK=refactor ./scripts/manual-bench.sh bmad 1
# → paste prompt, run tool, exit
# → run the printed one-liner (SHA capture + collect-metrics)

TASK=refactor ./scripts/blind-eval-setup.sh
TASK=refactor ./scripts/judge-all.sh <label>   # 5-judge panel, single round

TASK=refactor ./scripts/aggregate-results.sh
python3 scripts/audit-cohort-symmetry.py
```

---

## 9. What this benchmark does **not** let you verify

Being explicit about what's outside the scope of the artifact:

- **Judge self-preference at the family level** — all 8 executors use a Claude base model, so Anthropic-family favoritism is not identified by this design. A true audit would need a non-Anthropic-base executor as control.
- **Generalization to other languages / codebases** — single TypeScript NX monorepo (a private TypeScript NX monorepo).
- **Tool-version drift** — results are a 2026-05 snapshot pinned in `versions.lock.json`.
- **Cross-task synthesis** — intentionally not reported as a single leaderboard; read the three per-task `final-report.md` files together. See [README caveat 7](../preview/readme.html#caveats).

Each limitation is disclosed in [PAPER §4](../preview/paper.html#4-limitations-and-threats-to-validity) and [README Caveats](../preview/readme.html#caveats).

---

## Quick Reference

| Question | File to open |
|---|---|
| What was the exact prompt sent to this tool? | `results/<task>/<tool>/t<N>/phase1-prompt.txt` |
| What did the tool actually do? | `results/<task>/<tool>/t<N>/session-logs/<uuid>.jsonl` |
| What did the judge see? | `results/<task>/_blind-eval/<label>/judge-prompt.md` + `implementation-diff.patch` |
| What did each judge score? | `results/<task>/_blind-eval/<label>/<judge>-judge.json` |
| What was the pre-R1 score? | `scores_pre_r1` field inside the same judge file |
| How is the aggregate computed? | `scripts/aggregate-results.sh` |
| Which label is which tool? | `results/<task>/_blind-eval/.mapping-DO-NOT-OPEN.json` (after judging is done) |
| What are the integrity guarantees? | This file + `scripts/audit-cohort-symmetry.py` (rerun protocol) + `scripts/aggregate-results.sh` (aggregation rules) |
