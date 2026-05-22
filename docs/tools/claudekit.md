# claudekit

## Overview

Claudekit is a skill pack and hook toolkit for Claude Code. The benchmark pins the Infina fork (a private Infina fork of claudekit @ `cf636d9`), forked from `carlrannaberg/claudekit` (MIT). It ships as a `.claude/` directory — custom slash commands, subagent skills, and a set of Claude Code hooks (`file-guard`, `typecheck-changed`, `eslint`, `codebase-map`, `create-checkpoint`, `validate-todo-completion`, `no-any`) that enforce guardrails at `PreToolUse`, `PostToolUse`, and `Stop` boundaries.

The benchmark exercises claudekit through the plan-then-cook chain recommended by claudekit's own docs (https://docs.claudekit.cc/docs/engineer): `/ck:plan` scopes the work, then `/ck:cook --auto` executes it without stopping at interactive review gates. Cook is claudekit's feature-implementation orchestrator, documented by the author as "your implementation conductor" — it classifies intent, chooses a workflow (fast, parallel, research-backed, or plan-execution), and chains planner, coder, tester, and reviewer skills across review gates. The `--auto` flag removes the human-in-the-loop approval gates and runs all phases continuously. In practice the session-log audit shows `/ck:plan` fires as a slash command and the operator then types `/ck:cook --auto` at the interactive prompt to enter the implementation phase — the chained form in a single prompt body is treated as prose and is not dispatched autonomously.

## Setup

`scripts/setup-tool-config.sh` clones the claudekit source repo into `/tmp/internal-claudekit`, replaces the clone's `.claude/` directory with claudekit's, copies claudekit's `CLAUDE.md` over the project's, and appends a short project-context block (stack, NX layout, testing command) while preserving the original as `CLAUDE.md.original`. A `plans/` directory is created for the `ck:plan` skill. Hook node paths are rewritten from bare `node` to the resolved `$(which node)` because the bench runs under `env -i` and NVM's PATH is stripped. `settings.json` is minimal — only `skipDangerousModePermissionPrompt: true`. No MCP servers, no external agents.

## Benchmark prompt

```
/ck:plan $SHARED_TASK
```

Plan-only entry. Fork skills are installed at `CLAUDE_CONFIG_DIR` (user-level) so the slash command dispatches directly — `/ck:plan` expands in the CLI's command handler rather than relying on prose trigger phrases. (Prior "prose form" — *"Use /ck:plan to scope…"* — produced zero `Skill` tool calls in an Apr-23 canary, which motivated the leading-slash form.)

Once the plan file(s) land, the operator manually types `/ck:cook --auto` at the interactive prompt to start the implementation phase. An earlier rerun design included that second command in the prompt body, but session-log audits showed the chained instruction was treated as prose and never re-fired as a slash command — so the harness was simplified to fire only `/ck:plan` explicitly and leave the plan→cook transition to the operator.

## What the transcripts show (session audit)

Numbers below are mean across 3 trials per task (session-audit run-time subsystem is n=3; the score table above is the full n=5 cohort), from [`scripts/audit-sessions.py`](../../scripts/audit-sessions.py). Per-trial JSON: `results/claudekit/t<N>/session-audit.json` (feature), `results/{bugfix,refactor}/claudekit/t<N>/session-audit.json`. Cohort summary: [`results/_audits/session-audit.md`](../../results/_audits/session-audit.md).

| Task     | wall min | main turns | sidechain turns | sub-agent disp. | files read (config / target) | files edited | cache hit |
|----------|---------:|-----------:|----------------:|----------------:|------------------------------:|-------------:|----------:|
| feature  | 97.2 | 116.0 | **334.3** | 2.3 | 67.3 (0 / 67.3) | 47.3 | 0.98 |
| bugfix   | 21.2 |  92.7 |  38.7     | 0.7 | 20.7 (0 / 20.7) |  2.3 | 0.97 |
| refactor | 38.2 | 147.7 |  19.7     | 0.3 | 25.3 (0 / 25.3) | 24.7 | 0.98 |

- **Two skills drive the runs:** `cook` (1,707 turns across all trials) and `ck-plan` (540) — `ck-plan` fires once per trial to scope, then `cook` runs the implementation thread. `attributionSkill` confirms the plan→cook hand-off the docs claim.
- **Slash commands typed:** `/ck-plan` (9), `/cook` (9), `/copy` (2). The plan→cook split is operator-typed in every trial.
- **Sub-agent types when dispatched:** `fullstack-developer` (4), `Explore` (4), `tester` (1), `code-reviewer` (1) — across the 9 trials. The feature task carries most of the dispatch budget; bugfix/refactor stay near-zero.
- **Feature is the sidechain-heavy task** (334 sidechain turns mean vs 39/20 for bugfix/refactor) — `cook` does fan out reviewer/tester subagents when the scope is large enough to amortise the dispatch cost.
- **Tool-config reads are zero on every task** — the `.claudekit/` scaffolding is loaded once into the model's prompt and not re-read during the run, contrasting with `omc` (~17 config reads per feature trial).

## Benchmark performance

| Task     | Weighted mean /200 | within_σ | between_σ | Rank |
|----------|-------------------:|---------:|----------:|------|
| feature  | 135.04             | 12.75    | 16.83     | 6 / 8 |
| bugfix   | **178.93**         | 11.42    | 9.35      | **1 / 8** |
| refactor | 178.04             | 5.29     | 17.01     | 2 / 8 |

Bugfix is claudekit's rank-1 task. It separates from rank-2 (`ecc` 172.31) by ≈ 7 weighted points and from rank-3 (`pure` 169.53) by ≈ 9 (feature's ecc→bmad spread of ≈ 12 is the corpus's largest rank-1-to-rank-3 gap). `within_σ` of 11.42 on bugfix combined with `between_σ` 9.35 makes this one of five cells in the corpus where `within_σ > between_σ` (alongside `ecc`, `pure` and `omc` on bugfix, and `gstack` on refactor).

Claudekit's ESLint counts are consistently non-zero across all three tasks despite its own `eslint` hook being configured — suggesting hook output is advisory in `--auto` mode and not a hard completion gate for the cook workflow.

## Notable observations

The `/ck:cook --auto` entry point is claudekit's most opinionated surface: it collapses a multi-skill pipeline (`ck-plan` → `ck-cook` → embedded reviewers) into a single prompt and bypasses human approval. On bugfix — a scope-bounded defect with a named filter and a QA report — the plan-first chain produces the cohort's best score. On feature (rank-6), the same structure does not separate from the cohort: the task surface is large enough that planning lift is diluted across many files. On refactor the plan-then-cook chain holds up well, landing rank-2 just behind `pure`.
