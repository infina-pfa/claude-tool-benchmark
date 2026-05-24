# Quickstart — Run one trial end-to-end in ~10 minutes

This guide gets you from `git clone` to a scored trial in the shortest path. For the full methodology and reference, see [PAPER §1](../preview/paper.html#1-methodology) (methodology) and [§6](../preview/paper.html#6-reproducibility) (reproducibility).

---

## Prerequisites

- **macOS or Linux.** Windows via WSL untested.
- **git**, **bash** (4.0+), **python3** (3.10+ with `numpy` if you want to re-compute stats).
- **OpenCode CLI** — only if you want to run the non-Claude judges (`grok420`, `glm51`, `mimo25pro`). `opencode --version` must succeed.
- **Anthropic API key** for Claude Code (`opus` judge + the executor base model).
- **OpenAI API key** for the `gpt54pro` judge (calls `/v1/responses` directly).
- **Disk:** ~2 GB for the benchmark's base repo clones and judge artifacts.

The benchmark runs against a real TypeScript NX monorepo that must be cloneable locally. Set `BENCH_REPO` to the clone URL of that monorepo (your fork or the original) — `scripts/env.sh` reads it and derives `BASE_REPO` as the local prepared-clone path (`runs/base-feature`, `runs/base-bugfix`, `runs/base-refactor` depending on `TASK`). `create-clones.sh` provisions those base clones on first use; after that it copies them into per-trial working copies.

---

## 1. Clone and orient (~1 min)

```bash
git clone git@github.com:infina-pfa/claude-tool-benchmark.git
cd claude-tool-benchmark
export BENCH_REPO="git@github.com:your-org/your-target-repo.git"   # or your fork
grep -E 'TOOLS|BASE_REPO|BENCH_REPO|TASK' scripts/env.sh              # tool list, base repo paths, task env
```

The benchmark evaluates 8 tools × 3 tasks:
- **Tasks:** `feature` `bugfix` `refactor`
- **Tools:** `pure`, `claudekit`, `gstack`, `bmad`, `omc`, `compound`, `ecc`, `superpower`

---

## 2. Pick one (task, tool, trial) (~1 min)

The smallest meaningful unit is one `(task, tool, trial)`. Pick something cheap first:

```bash
export TASK=refactor          # smallest PRD, shortest trials
TOOL=bmad                     # top-of-cluster tool — easy signal
TRIAL=1
```

---

## 3. Clone the base repo into a trial working copy (~2 min)

```bash
TASK=$TASK ./scripts/create-clones.sh $TRIAL
```

First run: clones `$BENCH_REPO` to the task's base path at the pinned SHA (declared in `versions.lock.json` `base_repos.<task>.sha`). Subsequent runs: fast-copies that base (APFS clonefile on macOS, `cp -r` elsewhere) into `runs/<task>/<tool>-t<trial>/` — one isolated working copy per (tool, trial). These directories are `.gitignored` so your tool's commits don't pollute the benchmark repo.

---

## 4. Prepare the per-tool config (~30 sec)

```bash
TASK=$TASK ./scripts/setup-tool-config.sh $TOOL $TRIAL
```

This provisions `config/<tool>-t<trial>/` — an isolated Claude Code home directory. It installs the tool (plugin, git clone, marketplace, depending on the tool — see `scripts/setup-tool-config.sh` for the per-tool recipe), seeds `settings.json`, and writes `.claude.json`.

Isolation matters: the benchmark does not want to inherit your personal Claude settings, plugins, or MCP servers. See the per-tool `config/<tool>-t<trial>/` for what was actually loaded.

---

## 5. Run the tool (~5-15 min depending on tool)

```bash
TASK=$TASK ./scripts/manual-bench.sh $TOOL $TRIAL
```

Follow the on-screen instructions: paste the prompt, let the tool run to its natural stop, then `/exit`. The script prints the SHA-capture + collect-metrics one-liner — **run it before anything else** so the SHAs and `auto-metrics.json` are captured cleanly.

You now have one trial worth of artifacts at `results/<task>/<tool>/t<trial>/`:
- `commits.txt` (line 1: BASE SHA, line 2: IMPL SHA)
- `session-logs/*.jsonl` (the full Claude Code transcript)
- `auto-metrics.json`, `diff-stats.txt`, `tsc-output.txt`, `eslint-output.txt`, `test-output.txt`
- `sessions/*.meta.json` (trial metadata, base commit, tool version)

---

## 6. Judge it (~2-5 min per judge)

For a minimum-viable-judgement, run one judge on your trial:

```bash
TASK=$TASK ./scripts/blind-eval-setup.sh
TASK=$TASK ROUND=1 ./scripts/judge-opus.sh Alpha    # replace Alpha with the blind label printed above
```

`blind-eval-setup.sh` generates a blind label (Alpha/Bravo/Charlie/...) per (tool, trial) and builds `judge-prompt.md` with: the PRD, reference implementation, the diff patch, the 20-item rubric, and the output JSON schema. Nothing in the prompt names the tool. `.mapping-DO-NOT-OPEN.json` keeps the label→tool mapping.

For the **full 5-judge protocol** (as used in the published report), run all five:

```bash
TASK=$TASK ROUND=1 ./scripts/judge-opus.sh      <label>
TASK=$TASK ROUND=1 ./scripts/judge-grok420.sh   <label>
TASK=$TASK ROUND=1 ./scripts/judge-glm51.sh     <label>
TASK=$TASK ROUND=1 ./scripts/judge-gpt54pro.sh  <label>
TASK=$TASK ROUND=1 ./scripts/judge-mimo25pro.sh <label>
```

Or use the panel wrapper:

```bash
TASK=$TASK ./scripts/judge-all.sh <label>       # 5-judge panel, single round
```

5 trials × 5 judges × 3 rounds = 75 judgments per `(tool, task)` cell. Each judgment uses fresh sampling (temperature 0 where provider exposes it). The canonical round's judge files live flat under each label dir; the two added stability rounds live under `round1/` and `round2/` subdirs (see `PAPER.md §1.6` and the aggregator's `^round[0-9]+$` filter).

---

## 7. Aggregate & get the score (~30 sec)

```bash
TASK=$TASK ./scripts/aggregate-results.sh
```

Writes `results/<task>/final-report.md` (weighted-mean ranking + caveats + σ decomposition) and `results/<task>/final-report.equal-weight.md` (equal-weight comparator). The script runs an idempotent R1 mechanical-fact sweep before aggregating, so any single-judge retry that bypassed the wrapper is auto-corrected.

For the cohort-symmetry audit:

```bash
python3 scripts/audit-cohort-symmetry.py
```

Exits non-zero on missing trials, base-commit divergence within a trial, or any other hard violation; soft-warns on >24h cohort spans.

---

## 8. Check your numbers against the published benchmark

The canonical rankings are published at [claude-tool-benchmark.pages.dev](https://claude-tool-benchmark.pages.dev/) — open the per-task report (feature / bugfix / refactor) and compare your `results/<task>/final-report.md` rank-order and weighted means against the table there.

If your numbers diverge, check: base-repo SHA, tool version, judge model versions, round count.

---

## Minimum viable re-run

If all you want is one score on one task with one judge (skip multi-judge averaging):

```bash
TASK=refactor ./scripts/create-clones.sh 1
TASK=refactor ./scripts/setup-tool-config.sh pure 1
TASK=refactor ./scripts/manual-bench.sh pure 1
# paste + run + exit + printed one-liner
TASK=refactor ./scripts/blind-eval-setup.sh
TASK=refactor ROUND=1 ./scripts/judge-opus.sh Alpha
TASK=refactor ./scripts/aggregate-results.sh
```

---

## What this quickstart deliberately skips

- **Multi-trial per tool.** Production numbers use 5 trials per (tool, task).
- **Cohort symmetry.** Production re-runs all 8 tools whenever one is re-run.
- **Full 5-judge panel.** Production uses opus / grok420 / glm51 / gpt54pro / mimo25pro with pre-registered 3 / 2 / 1 / 1 / 1 weights (see `versions.lock.json`).

See the [verification guide](verification.md) for how to reproduce a specific published claim.

See [extending.md](extending.md) if you want to add a new tool or judge.
