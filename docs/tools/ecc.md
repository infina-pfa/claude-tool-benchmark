# ecc — everything-claude-code

> A plugin pack from an Anthropic hackathon winner: a large catalog of commands, agents, skills, and hooks, invoked here through a single command — `/everything-claude-code:plan`, fired on every task.

## Upstream

- Repository: `affaan-m/everything-claude-code` (https://github.com/affaan-m/everything-claude-code)
- Author: Affaan Mustafa
- License: MIT
- Plugin version pinned at install: `1.10.0` (commit `846ffb75`)
- Claude Code plugin identifier: `everything-claude-code@everything-claude-code`

## Performance

| Task     | Weighted mean /200 | within_σ | between_σ | Rank |
|----------|-------------------:|---------:|----------:|------|
| feature  | **153.30**         | 8.96     | 15.29     | **1 / 8** |
| bugfix   | 172.31             | 13.54    | 11.70     | 2 / 8 |
| refactor | 173.61             | 8.71     | 16.12     | 6 / 8 |

ecc is **rank-1 on feature** (by ≈ 10 weighted pts over `pure` at 143.13 and `bmad` at 141.33) and rank-2 on bugfix. `within_σ` on feature (8.96) is mid-pack among orchestrators — the `/plan` planner pass produces moderately stable run-to-run quality. The mid-pack rank on refactor (6) is consistent with the rest of the orchestrator class on a task where the bare baseline takes rank-1.

## Mechanism

ECC ships a sprawling plugin surface — its own documentation claims 38 agents, 156 skills, and 72 legacy command shims at v1.10.0, with additional components for cost, security, and operator workflows. The config directory confirms an MIT plugin registered through the Anthropic marketplace and a single `enabledPlugins` entry (`everything-claude-code@everything-claude-code`); no skills were manually re-keyed into `~/.claude/`.

For the benchmark, a single entry point out of the full catalog was reached:

- `/everything-claude-code:plan` — the only command the harness fires (on all three tasks). Invokes the planner subagent, which restates requirements, writes a step-by-step implementation plan, and waits for explicit confirmation before editing code.
- `/everything-claude-code:build-fix` exists in the catalog (a build/bug fixer that investigates, edits, then runs language-appropriate build + test commands) but **was never invoked by this benchmark** — it appears in zero ecc session logs across all 40 trials.
- Everything else in the catalog (TDD, review, harness audit, memory, instincts, multi-plan, etc.) was available but never triggered by the harness.

## How this benchmark invoked it

`scripts/manual-bench.sh` (case `ecc)`, L176–178) fires the **same command on every task** — there is no per-task split:

- `feature` → `/everything-claude-code:plan <shared task prompt>`
- `refactor` → `/everything-claude-code:plan <shared task prompt>`
- `bugfix` → `/everything-claude-code:plan <shared task prompt>`

> **Correction (2026-05-18).** Earlier versions of this profile described a load-bearing `/plan`-vs-`/build-fix` split (bugfix routed to `/build-fix`). That split was never implemented: `scripts/manual-bench.sh` has a single `ecc)` case with no task branch, and `/everything-claude-code:build-fix` is absent from every ecc transcript (feature/bugfix/refactor × t1–t5). The bugfix-performance explanation built on that premise was unfounded and has been re-derived below from the actual plan-only session data.

## What the transcripts show (session audit)

Numbers below are mean across 3 trials per task (session-audit run-time subsystem is n=3; the score table above is the full n=5 cohort), from [`scripts/audit-sessions.py`](../../scripts/audit-sessions.py). Per-trial JSON: `results/ecc/t<N>/session-audit.json` (feature), `results/{bugfix,refactor}/ecc/t<N>/session-audit.json`. Cohort summary: [`results/_audits/session-audit.md`](../../results/_audits/session-audit.md).

| Task     | wall min | main turns | sidechain turns | sub-agent disp. | files read (config / target) | files edited | cache hit |
|----------|---------:|-----------:|----------------:|----------------:|------------------------------:|-------------:|----------:|
| feature  | 634.1¹ | 215.7 | 259.0 | 1.7 | 59.0 (0 / 59.0) | 56.3 | 0.98 |
| bugfix   |  22.5  |  46.0 |  58.3 | 1.0 | 22.7 (0 / 22.7) |  1.3 | 0.95 |
| refactor |  26.3  | 144.0 |  41.0 | 1.0 | 36.7 (0 / 36.7) | 25.0 | 0.98 |

¹ ecc's feature wall-clock is suspect — all 3 trials land near 634 min regardless of turn count (t1: 633.1 / 258 turns; t2: 635.2 / 353 turns; t3: 634.2 / 813 turns). This is likely the session-lifetime of the harness (kept open past task completion), not in-flight agent time.

- **One driving skill on every task:** `everything-claude-code:plan` is the only attributed skill across all 40 ecc trials (feature/bugfix/refactor × t1–t5). There is no `build-fix` skill or slash command in any transcript.
- **Slash commands typed:** `/everything-claude-code:plan` only, across the whole corpus. (Earlier text claiming `/build-fix` "shows up in the harness prompt" was incorrect — corrected 2026-05-18.)
- **Sub-agent types dispatched:** `general-purpose` (6), `everything-claude-code:planner` (6), `Explore` (3), `Plan` (1) — **16 dispatches across 15 (tool,task,trial) cells**. Bugfix averages ≈ 0.6 dispatches/trial at n=5.
- **The planner subagent fires inconsistently on bugfix.** At n=5: t1–t3 dispatched the `everything-claude-code:planner` subagent (sub-agent ≥ 1, non-zero sidechain: 79/70/26 turns); t4–t5 ran `/plan` entirely in the main thread (0 sub-agents, 0 sidechain). The `/plan` flow itself degrades to an inline single-thread plan on some trials — there is no guaranteed planner round trip.
- **Bugfix sessions are short and tightly scoped** (n=5 means: ≈ 56 main turns, ≈ 1.4 files edited, ≈ 19 wall min — among the lowest edit footprints in the cohort on bugfix). The `/plan` entry restates requirements and scope-gates to 1–2 files before editing.

## Why it ranked where it did

ecc's bugfix rank-2 comes from the `/plan` entry's upfront requirement restatement and scope-gating, which yields tight, small-footprint edits (≈ 1.4 files/trial) and a reproduction-test that other tools in this benchmark did not consistently produce — **not** from any `/build-fix` fast path, which does not exist in this harness. The `everything-claude-code:planner` subagent contributes on t1–t3 but is absent on t4–t5, so the lift is the in-context plan-and-confirm discipline, not reliable sub-agent fan-out.

On feature the same `/plan` upfront pass is load-bearing — ecc takes rank-1 by ≈ 10 weighted pts over the next setup. On refactor the same `/plan` entry point does not separate from the orchestrator pack; the bare baseline takes rank-1 across the cohort.

## Strengths and failure modes

Strengths observed: the `/plan` planner pass produces reviewable plans with explicit confirm gates and tight edit scope; fact-forcing gate catches blast-radius before each edit; willingness to separate pre-existing failures from regressions. (No task-to-command mapping exists — one command, `/plan`, serves all three tasks.)

Failure modes observed: 14 eslint errors on the feature diff, 6 on the refactor — the workflow does not round-trip lint before committing. Large catalog is mostly dormant (TDD, quality-gate, code-review commands never fire unless the harness picks them). On tasks without a clear "this is a bug" framing (refactor), the tool reduces to vanilla Claude with an extra planning prelude.

Unverified items: 140K-star / 21K-fork counts on the upstream README — README claim only, not checked against GitHub.

## References

- Upstream repo and README: `https://github.com/affaan-m/everything-claude-code`
- Install case: `scripts/setup-tool-config.sh` (case `ecc)`)
- Prompt switch: `scripts/manual-bench.sh` (case `ecc)`)
- Config surface: `config/ecc-t<N>/settings.json`, `config/ecc-t<N>/plugins/installed_plugins.json`
- Transcripts: `results/{ecc,bugfix/ecc,refactor/ecc}/t<N>/session-logs/`
- Per-task reports: [`results/final-report.md`](../../results/final-report.md), [`results/bugfix/final-report.md`](../../results/bugfix/final-report.md), [`results/refactor/final-report.md`](../../results/refactor/final-report.md)
