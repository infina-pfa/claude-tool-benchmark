# docs/tools/ — Tool profiles

One profile per setup under test. Read the individual files for mechanism detail; this index is for comparison at a glance.

---

## Setups & upstream

| Tool | Upstream | License | Version at run | Profile |
|---|---|---|---|---|
| [`bmad`](bmad.md) | `bmad-code-org/BMAD-METHOD` | MIT | npx `bmad-method@6.6.0` (`e6cdc93b`) | [bmad.md](bmad.md) |
| [`claudekit`](claudekit.md) | a private Infina fork of claudekit (fork of `carlrannaberg/claudekit`) | MIT | master `cf636d9` | [claudekit.md](claudekit.md) |
| [`compound`](compound.md) | `EveryInc/compound-engineering-plugin` | MIT | plugin 3.7.0 (`0bb53dfa`) | [compound.md](compound.md) |
| [`ecc`](ecc.md) | `affaan-m/everything-claude-code` | MIT | plugin 1.10.0 (`846ffb75`) | [ecc.md](ecc.md) |
| [`gstack`](gstack.md) | `garrytan/gstack` | MIT | 1.28.0.0 (`443bde05`) | [gstack.md](gstack.md) |
| [`omc`](omc.md) | `Yeachan-Heo/oh-my-claudecode` | MIT | plugin 4.13.6 (`8b24a29d`) | [omc.md](omc.md) |
| [`pure`](pure.md) | Anthropic Claude Code (stock) | proprietary (CLI) | CLI 2.1.133 | [pure.md](pure.md) |
| [`superpower`](superpower.md) | `obra/superpowers` (via `obra/superpowers-marketplace`) | MIT | 5.1.0 (`f2cbfbef`) | [superpower.md](superpower.md) |

All tools run on the same base executor model: **`claude-opus-4-7`**, base-model effort `medium`, context window 200k. The only thing that varies between rows is the setup (plugin, skill pack, hook kit, or bare-CLI configuration) wrapping Claude Code. Versions are pinned in [`versions.lock.json`](../../versions.lock.json) `tools.*`.

---

## Per-task weighted-mean ranking

Pulled from `results/<task>/final-report.md` (weighted mean of per-judge means under the pre-registered 3 / 2 / 1 / 1 / 1 panel; equal-weight comparator alongside).

| Tool | feature /200 | bugfix /200 | refactor /200 |
|---|---|---|---|
| ecc | **153.30 (rank 1)** | 172.31 (rank 2) | 173.61 (rank 6) |
| superpower | 140.16 (rank 4) | 166.41 (rank 4) | 177.56 (rank 4) |
| pure | 143.13 (rank 2) | 169.53 (rank 3) | **180.19 (rank 1)** |
| compound | 134.67 (rank 7) | 166.25 (rank 5) | 174.42 (rank 5) |
| bmad | 141.33 (rank 3) | 165.72 (rank 6) | 177.74 (rank 3) |
| omc | 139.49 (rank 5) | 164.80 (rank 7) | 170.11 (rank 7) |
| claudekit | 135.04 (rank 6) | **178.93 (rank 1)** | 178.04 (rank 2) |
| gstack | 131.98 (rank 8) | 159.97 (rank 8) | 144.92 (rank 8) |

**Cohort weighted-mean** per task: feature 139.89 · bugfix 167.99 · refactor 172.07. **No setup is top-2 on all three tasks.** A single cross-task summary is sensitive to weighting; each cell is now 5 trials per cell, 75 judgments per cell (5 trials × 5 judges × 3 rounds) — read the three per-task `final-report.md` files together rather than collapsing to one leaderboard (README caveat 7).

---

## Mechanism taxonomy

Grouping the 8 setups by the primary enhancement mechanism:

| Mechanism | Tools | Works by |
|---|---|---|
| **No-addon baseline** | `pure` | Vanilla Claude Code, no addons |
| **Skill registry (model-selected)** | `superpower` | Named skill files the base model chooses to invoke via `Skill` tool |
| **Skill pack + hook gates** | `claudekit`, `gstack` | Slash commands, skills, hooks enforcing gates (typecheck/eslint, freeze/scope-lock, eng-review) |
| **Multi-agent orchestrator (sequential)** | `compound`, `ecc` | Fixed phase pipelines (plan → work → review) with stop-gates between phases |
| **Multi-agent orchestrator (role-based)** | `bmad` | Agent personas (PM, architect, dev, QA) with hand-off between them |
| **Meta-orchestrator (delegation-heavy)** | `omc` | Top-level planner that dispatches to specialized subagents/skills |

"Orchestrator" here means the setup adds its own agent/subagent layer on top of Claude Code, not just prompt + tool choices. The orchestrator row is *not* itself a ranking of orchestration quality — `compound` ranks 7 on feature but 5 on bugfix and refactor; `bmad` ranks 3 on refactor but 6 on bugfix. Architecture is under-determinative of outcome in this corpus.

---

## Invocation & planning profile

| Tool | Entry command | Planning layer | Setup turn? |
|---|---|---|---|
| pure | (no prefix) | Claude native plan-mode | no |
| superpower | (no prefix for feature/refactor); `/superpowers:systematic-debugging` for bugfix | skill registry (model chooses) | no |
| bmad | `/bmad-quick-dev` | BMad-Method phases | no |
| claudekit | `/ck:plan` → `/ck:cook --auto` | `ck-plan` skill | no |
| ecc | `/everything-claude-code:plan` (feat/refactor), `/everything-claude-code:build-fix` (bugfix) | own `plan` skill | no |
| gstack | `/autoplan` (feat/refactor), `/investigate` (bugfix); `/ship` finalizer | `/autoplan`, `/ship` gate | no |
| compound | `/compound-engineering:lfg` | `/ce:plan` phase (step 2 of 6) | no |
| omc | `/oh-my-claudecode:ralplan` → operator-typed `/oh-my-claudecode:team` (after setup turn) | ralplan consensus planner (planner + architect + critic) feeding `/team` workers | **yes** (`/oh-my-claudecode:omc-setup`) |

---

## Per-task winners

| Task | Rank 1 | Rank 2 | Rank 3 |
|---|---|---|---|
| feature (Mode-2 CD Batch)              | ecc       | pure       | bmad |
| bugfix (near-maturity)       | claudekit | ecc        | pure |
| refactor (aggregate-ownership)| pure     | claudekit  | bmad |

**`pure`** (no addons) is the only setup top-3 on every task and rank-1 on `refactor`. The null hypothesis "tools add no value over the bare CLI" is not rejected on `refactor` (top-5 within ≈ 5.8 weighted pts); on `bugfix`, `claudekit` (+9.40 pts over pure) is **below** the bugfix MDE (22.17), so the strict null is **not** rejected there (the earlier ~5-pt-tie-envelope claim is retracted — see PAPER §3 / §4).

---

## Session audit (transcript-mined behavior)

Each per-tool profile now includes a session-audit table with the headline behavioral metrics — wall-clock, main/sidechain turns, sub-agent dispatches, file reads (split into tool-config vs target-repo), files edited, and cache hit ratio — computed across 3 trials per task from the raw JSONL transcripts (session-audit run-time subsystem is n=3; the per-task score tables are the full n=5 cohort).

Source: [`scripts/audit-sessions.py`](../../scripts/audit-sessions.py) walks `results/<tool>/t<N>/session-logs/*.jsonl` (feature) and `results/{bugfix,refactor}/<tool>/t<N>/session-logs/*.jsonl` for the other tasks, plus the `subagents/*.jsonl` files underneath. Per-trial JSON: `results/<...>/t<N>/session-audit.json`. Cohort summary: [`results/_audits/session-audit.md`](../../results/_audits/session-audit.md).

Headline cross-tool findings from the audit:

- **Sub-agent dispatch is not what most docs claimed.** `bmad` dispatches 0 sub-agents on bugfix across all 3 trials; `compound` dispatches reviewer-personas in only 1 of 9 trials (compound/t2 feature). The "multi-reviewer gate" architecture documented upstream materialises as sequential `attributionSkill` changes inside a single thread, not as actual `Agent` tool calls.
- **`superpower`'s skill activation is task-dependent.** Sub-agent fan-out is 18.3 dispatches/trial on feature but ~0.5 on bugfix/refactor — the `subagent-driven-development` skill triggers on feature work only.
- **`omc` is the only setup with material tool-config read overhead** (~17 reads per feature trial vs ~0 for every other tool) — the "setup tax" of a self-maintaining orchestrator.
- **`pure` is the only setup with zero `attributionSkill` rows** — every assistant turn is base-model, confirming the no-addon mechanism.
- **Cache hit ratios** are 0.97–0.98 for most tools; `omc` is lowest at 0.93 (worker fan-out forces more cache creation).

## Observed failure modes

Cross-cutting patterns from reading the transcripts:

- **Over-orchestration on small tasks** — `compound`, `omc`. Multi-agent setups paying a high fixed setup cost on a 30-minute task suffer when the task doesn't use their multi-phase capacity.
- **`--auto` gate-suppression** — `claudekit`. `/ck:cook --auto` removes the human-review gates that the setup relies on; the scripted workflow runs end-to-end but the "stop on test failure" behavior doesn't kick in.
- **Skill activation depends on entry-point wording** — `superpower`. A registry-style skill library whose triggers are generic vocabulary ("bug", "error", "root cause") is not guaranteed to activate on a terse prompt that does not pattern-match. The bugfix harness names the slash-commands explicitly to isolate skill content from trigger-phrase sensitivity.
- **Eng-review gate ≠ code-quality gate** — `gstack`. `/ship` enforces process cleanliness but doesn't catch all code-quality issues; rank-8 on `feature` and `bugfix`.

---

## How to read these profiles

Each profile follows roughly:
1. **Upstream & identity** — repo, version, license, maintainer.
2. **Performance** — per-task weighted mean, within_σ, between_σ, rank.
3. **Mechanism** — what actually runs: skills, hooks, sub-agents, MCP, permission layer.
4. **How this benchmark invoked it** — exact prompt, plan-mode flag, setup turn.
5. **What the transcripts show** — per-task: tool-call mix, sub-agent use, commit shape.
6. **Why it ranked where it did** — grounded in transcript evidence.
7. **Strengths & failure modes** — per-task observations.
8. **References** — links back to upstream and to the benchmark artifacts.

The intent is: a reader should be able to close the profile with an accurate mental model of how the tool operates *in practice on this corpus*, not a re-phrasing of the upstream README.
