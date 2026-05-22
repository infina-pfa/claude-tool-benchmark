# pure

The no-addon baseline. Vanilla Claude Code with plan mode forced on and nothing else.

## Upstream

- **Product:** Anthropic Claude Code.
- **CLI version pinned:** `2.1.133` (via `$BENCH_CLAUDE_BIN`, see [`versions.lock.json`](../../versions.lock.json)).
- **Model:** `claude-opus-4-7`.
- **Docs:** https://docs.anthropic.com/en/docs/claude-code/overview.

There is no third-party repository. "pure" is the CLI out of the box.

## Performance

| Task     | Weighted mean /200 | within_σ | between_σ | Rank |
|----------|-------------------:|---------:|----------:|------|
| feature  | 143.13             | 7.51     | 15.72     | 2 / 8 |
| bugfix   | 169.53             | 12.05    | 9.58      | 3 / 8 |
| refactor | **180.19**         | 4.44     | 13.73     | **1 / 8** |

Pure is the only setup top-3 on every task and **rank-1 on refactor**. On `refactor` no addon exceeds pure and the top-5 sit within ≈ 6 weighted pts — the null "tools add no value over the bare CLI" is not rejected on this task. On `bugfix`, pure is rank-3 but `claudekit` (+9.40 pts) and `ecc` (+2.78 pts) both sit above; the `claudekit`–`pure` gap (+9.40) is **below** the bugfix MDE (22.17), so the strict null is **not** rejected on bugfix (the earlier ~5-pt-tie-envelope claim is retracted — see PAPER §4). See [README §TL;DR](../../README.md#tldr--rank-1-by-task-weighted-mean--200) and [PAPER §3 Discussion](../../PAPER.md#3-discussion).

## Mechanism

There is no mechanism beyond Claude Code itself. Everything is the stock tool set — TodoWrite, the general-purpose Agent sub-agent, Bash, Read, Grep, Glob, Edit, Write. No plugins, no skills, no hooks, no MCP servers, no custom slash commands.

## How this benchmark invoked it

`config/pure-t<N>/` is deliberately empty of customisation. `setup-tool-config.sh` (case `pure)`) is a no-op:

> "Pure Claude Code — no external tools to install. Config dir stays empty (no plugins, no MCP, no skills, no hooks)."

`config/pure-t<N>/settings.json` contains one key: `"skipDangerousModePermissionPrompt": true`.

The per-tool prompt is the shared task text verbatim: `PROMPT="$SHARED_TASK"`. No slash command, no setup preamble. The CLI is launched with `claude --model claude-opus-4-7 --dangerously-skip-permissions`.

## What the transcripts show (session audit)

Numbers below are mean across 3 trials per task (session-audit run-time subsystem is n=3; the score table above is the full n=5 cohort), from [`scripts/audit-sessions.py`](../../scripts/audit-sessions.py). Per-trial JSON: `results/pure/t<N>/session-audit.json` (feature), `results/{bugfix,refactor}/pure/t<N>/session-audit.json`. Cohort summary: [`results/_audits/session-audit.md`](../../results/_audits/session-audit.md).

| Task     | wall min | main turns | sidechain turns | sub-agent disp. | files read (config / target) | files edited | cache hit |
|----------|---------:|-----------:|----------------:|----------------:|------------------------------:|-------------:|----------:|
| feature  | 34.4 | 138.3 | 131.3 | 1.0 | 45.7 (0 / 45.7) | 30.3 | 0.98 |
| bugfix   | 12.6 |  83.0 |  25.7 | 0.3 | 18.0 (0 / 17.7) |  1.3 | 0.97 |
| refactor | 28.2 | 143.0 |  58.3 | 1.3 | 42.0 (0 / 42.0) | 20.0 | 0.97 |

- **Zero `attributionSkill` rows** across all 9 trials — confirms the "no skills, no plugins" mechanism: every assistant turn is base-model, not skill-attributed.
- **Zero tool-config reads** on every trial — no scaffolding to read.
- **Sub-agent dispatch is sparse and read-only.** Types observed across all trials: `Explore` (7), `general-purpose` (1) — used for investigation, never for delegating implementation. Matches the pure-CLI behavior the docs describe.
- **Slash commands typed:** `/resume` (1) — only when one trial needed a session resume, not part of the standard flow.
- **Cache hit ratio is the cohort's highest** (~0.98) — short, focused sessions reuse context efficiently.
- **Wall-clock is among the lowest** at 28–34 min for feature/refactor and ~13 min for bugfix; the no-addon path doesn't pay any orchestration tax.

## Why the baseline performs so well

Two observations from the transcripts:

1. **The investigate-then-write discipline is built into the base model.** Setups that wrap Claude Code typically add a plan document, a scope boundary, a "do not edit before planning" guardrail. When the base model is already producing that discipline implicitly, the marginal value of an addon shrinks. This is especially visible on `refactor`, where the task surface is small enough that orchestration overhead overwhelms whatever lift extra scaffolding could provide — `pure` is rank-1, all the orchestrators sit behind it.

2. **Opus 4.7 is sufficient on its own for benchmark-sized tasks.** The tool mix stays simple. Subagent dispatches are scoped and read-only. The shape of a strong `pure` run is short-but-structured.

## Strengths and failure modes

**Strengths.** Top-3 across all three tasks; rank-1 on refactor; lowest ceremony cost per trial; no setup-introduced regressions. `within_σ` on refactor (4.44) is the lowest in the cohort — pure's output is the most consistently stable run-to-run on this task (`superpower` at 5.09 and `claudekit` at 5.29 sit just above).

**Failure modes.** No enforced verification step beyond what the model decides to run. No automatic scope broadening — if a task needs exploration beyond one investigation pass, pure won't initiate a second. No memory across runs; every session is cold.

The takeaway is editorial rather than surprising: a well-planned vanilla session is competitive with — and on refactor, ahead of — anything the other setups in this cohort add on top.

## References

- `config/pure-t<N>/settings.json`
- `scripts/setup-tool-config.sh` (case `pure)`)
- `scripts/manual-bench.sh` (prompt passthrough, no slash command)
- `results/pure/t<N>/`, `results/bugfix/pure/t<N>/`, `results/refactor/pure/t<N>/`
- Per-task reports: [`results/final-report.md`](../../results/final-report.md), [`results/bugfix/final-report.md`](../../results/bugfix/final-report.md), [`results/refactor/final-report.md`](../../results/refactor/final-report.md)
- Claude Code documentation: https://docs.anthropic.com/en/docs/claude-code/overview
