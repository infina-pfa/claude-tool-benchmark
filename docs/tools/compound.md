# compound

## Overview

`compound` is the Claude Code plugin [`EveryInc/compound-engineering-plugin`](https://github.com/EveryInc/compound-engineering-plugin), maintained by Every Inc. (the media and software company behind the Cora email product). The plugin was developed in public alongside Kieran Klaassen's "compound engineering" writing, and it packages that methodology as a large bundle of slash commands, skills, and specialist agents. The benchmark installs it via the Claude Code plugin marketplace and pins release **3.7.0** (tag SHA `0bb53dfa`, MIT license). The user-facing primitives cluster into four phases: `/ce:plan`, `/ce:work`, `/ce:review`, and `/ce:compound`, plus a handful of research, design, and git utilities.

The methodology behind the name is the thesis that each engineering task should leave the system *easier* to work on next time, by codifying plans, reviews, and learnings back into the repository. In practice that shows up as markdown artifacts in `docs/plans/`, reviewer persona subagents, and a `/ce:compound` step that writes learnings to a wiki-style store.

## Entry point: `/lfg`

The benchmark drives the plugin through its beta autonomous entry point, `/compound-engineering:lfg` ("let's f***ing go"). The skill file is explicit about ordering: it is a fixed six-step pipeline with stop-gates between phases.

1. Optionally delegate to a `ralph-loop` skill if present (not installed in the benchmark).
2. `/ce:plan $ARGUMENTS` — gated on producing a plan file under `docs/plans/`.
3. `/ce:work` — gated on observing code changes beyond the plan.
4. `/ce:review mode:autofix plan:<plan-path>` — passes the plan path so review can check requirement coverage.
5. `/compound-engineering:todo-resolve`.
6. `/compound-engineering:test-browser`, then emit `<promise>DONE</promise>`.

So `lfg` is a plan-execute-review loop with a knowledge-compaction tail, not a freeform agent. Phases are sequenced with "GATE: STOP" language rather than parallel fan-out.

## What the transcripts show (session audit)

Numbers below are mean across 3 trials per task (session-audit run-time subsystem is n=3; the score table above is the full n=5 cohort), from [`scripts/audit-sessions.py`](../../scripts/audit-sessions.py). Per-trial JSON: `results/compound/t<N>/session-audit.json` (feature), `results/{bugfix,refactor}/compound/t<N>/session-audit.json`. Cohort summary: [`results/_audits/session-audit.md`](../../results/_audits/session-audit.md).

| Task     | wall min | main turns | sidechain turns | sub-agent disp. | files read (config / target) | files edited | cache hit |
|----------|---------:|-----------:|----------------:|----------------:|------------------------------:|-------------:|----------:|
| feature  | 22.0 | 165.0 | 53.3 | **1.7** | 25.0 (0 / 25.0) | 11.7 | 0.98 |
| bugfix   |  7.2 |  83.0 |  0.0 | **0.0** | 14.0 (0 / 14.0) |  1.0 | 0.97 |
| refactor | 15.0 | 165.3 |  0.0 | **0.0** | 22.3 (0 / 22.0) | 27.0 | 0.98 |

- **Reviewer fan-out fires in 1 of 9 trials.** The `lfg` pipeline (plan → work → review → todo-resolve) phases through compound's own skills as sequential `attributionSkill` changes within the main thread — `ce-work` (727), `ce-plan` (387), `ce-code-review` (261), `ce-commit-push-pr` (7), `lfg` (18). But the *reviewer-persona sub-agents* (`ce-correctness-reviewer`, `ce-adversarial-reviewer`, `ce-api-contract-reviewer`, `ce-testing-reviewer`, `ce-maintainability-reviewer`) only dispatched once each across the entire corpus — concentrated in **compound/t2 feature** (5 dispatches). All other 8 trials show 0 sub-agent dispatches.
- **Bugfix and refactor stay single-thread.** 0 sidechain turns and 0 `Agent` calls on every trial of both tasks. The pipeline's review phase still fires (`ce-code-review` shows up in attribution) but does it as a role-played turn inside the main thread, not as a sub-agent dispatch.
- **Slash commands typed:** `/compound-engineering:lfg` (9), `/login` (1).
- **Refactor is the most edit-heavy task** (27.0 edits) but completes fast (15 min) — the lfg pipeline collapses to plan-then-edit without review fan-out, looking similar in shape to `pure`.

## Benchmark outcome

| Task     | Weighted mean /200 | within_σ | between_σ | Rank |
|----------|-------------------:|---------:|----------:|------|
| feature  | 134.67             | 13.26    | 15.99     | 7 / 8 |
| bugfix   | 166.25             | 9.57     | 11.27     | 5 / 8 |
| refactor | 174.42             | 6.04     | 16.40     | 5 / 8 |

Compound is **rank-7 on feature** — ≈ 18.6 weighted pts behind `ecc` (153.30) and ≈ 8.5 pts below `pure` (143.13). On the smaller tasks the reviewer-persona pipeline lands mid-pack: rank-5 on both bugfix and refactor.

## Reading of the result

`compound` is not a lightweight prompt — it ships a full plan-then-work-then-review pipeline with reviewer personas, gates, and a learning-capture step. In the benchmark's single-shot `/lfg` invocation the pipeline does run, but its orchestration overhead is not repaid on any of the three single-shot tasks: it lands rank-7 on feature and mid-pack (rank-5) on bugfix and refactor. The reviewer fan-out and plan artifacts do not separate from the cohort when each task is a one-attempt run with no memory carryover.

The plugin is more interesting as a methodology carrier — plans in `docs/plans/`, learnings in a wiki — than as a single-shot speed runner, and the benchmark, which rewards diff quality on one attempt with no memory carryover, is a harsh venue for that design.
