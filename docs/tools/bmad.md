# bmad — BMad-Method

> A structured Agile-style workflow harness that runs a Plan → Code → Review loop through a single `/bmad-quick-dev` slash command.

## Upstream

- **Repo:** https://github.com/bmad-code-org/BMAD-METHOD
- **Version used:** `6.6.0` (`e6cdc93b`), pinned via `npx bmad-method@6.6.0 install` in `scripts/setup-tool-config.sh`.
- **Author / maintainer:** `bmad-code-org` (GitHub organisation).
- **License:** MIT.
- **Primary doc:** https://github.com/bmad-code-org/BMAD-METHOD (README). Installer also writes `_bmad/` and `.claude/skills/bmad-*` into the repo with its own docs.

## Performance in this benchmark

| Task     | Weighted mean /200 | within_σ | between_σ | Rank |
|----------|-------------------:|---------:|----------:|------|
| feature  | 141.33             | 7.02     | 20.81     | 3 / 8 |
| bugfix   | 165.72             | 12.75    | 12.94     | 6 / 8 |
| refactor | 177.74             | 5.48     | 15.28     | 3 / 8 |

Refactor is bmad's rank-3 task (within 2.45 weighted pts of rank-1 `pure` at 180.19 — inside the between-judge σ envelope). Bugfix is rank-6 by ≈ 13 pts behind rank-1 `claudekit` (178.93). Feature is rank-3; `between_σ` of 20.81 on feature is the highest in the cohort, signalling judges disagreed widely on bmad's feature output.


## Mechanism — what actually runs

- **Install surface** (from `scripts/setup-tool-config.sh` case `bmad)`): `npx bmad-method@6.6.0 install --directory . --modules bmm --tools claude-code --yes` is run inside the cloned repo. This writes `_bmad/` (config + agent prompts, gitignored by the bench safety rules), `.claude/skills/bmad-*` (skill files exposed to Claude Code), and `_bmad-output/` (tracked, used for phase artifacts). No plugin is added to the CLI's plugin registry. The tool's `settings.json` is just `{ "skipDangerousModePermissionPrompt": true }`; all bmad behaviour comes from the in-repo skill files, not from CLI-level config.
- **Entry point** (from `scripts/manual-bench.sh` case `bmad)`): the harness prepends an intro that tells bmad which path to take, then sends `PROMPT="/bmad-quick-dev $BMAD_INTRO\n\n$SHARED_TASK"`. The intro always says "Pick the Plan-Code-Review path" and adds task-shape hints ("non-trivial feature", "scoped bugfix — reproduce first", "scoped refactor — no behavior change"). Observable behaviour: the command parses the intro, then proceeds through plan → code → review phases inline.
- **Skills / sub-agents / hooks activated:** bmad dispatches `Agent` tool calls to sub-agents during execution. Roles observed in sub-agent prompts: an `Explore` investigator, a blind adversarial code reviewer, an edge-case hunter, and an acceptance auditor. No external hooks, no MCP servers — only the installed skill files and Claude Code's built-in `Task`/`Agent` tool.
- **Core mental model:** BMad stages a cut-down Agile cycle — scope → plan → implement → multi-angle review — into a single slash command, with a fact-forcing preamble and explicit phase checkpoints before file edits.

## How this benchmark invoked it

Exact PROMPT (from `manual-bench.sh`, with per-task intro):

```
/bmad-quick-dev Pick the Plan-Code-Review path — this is a <non-trivial feature | scoped bugfix | scoped refactor> in an existing <brownfield> codebase. <task-shape hint>

<SHARED_TASK>
```

Base model: `claude-opus-4-7` (same for all eight tools).

## What the transcripts show (session audit)

Numbers below are mean across 3 trials per task (session-audit run-time subsystem is n=3; the score table above is the full n=5 cohort), from [`scripts/audit-sessions.py`](../../scripts/audit-sessions.py). Per-trial JSON: `results/bmad/t<N>/session-audit.json` (feature), `results/{bugfix,refactor}/bmad/t<N>/session-audit.json`. Cohort summary: [`results/_audits/session-audit.md`](../../results/_audits/session-audit.md).

| Task     | wall min | main turns | sidechain turns | sub-agent disp. | files read (config / target) | files edited | cache hit |
|----------|---------:|-----------:|----------------:|----------------:|------------------------------:|-------------:|----------:|
| feature  | 21.4 | 156.3 | 49.3  | **1.0**  | 47.0 (6.0 / 40.7)  | 10.0 | 0.96 |
| bugfix   |  9.5 |  83.3 |  0.0  | **0.0**  | 15.3 (2.7 / 12.7)  |  3.0 | 0.96 |
| refactor | 82.1 | 168.0 | 70.0  | **1.3**  | 45.3 (4.7 / 40.7)  | 29.0 | 0.96 |

- **Single skill drives every trial.** `attributionSkill` is `bmad-quick-dev` on every assistant turn across all 9 trials (1,380 turns total). No second bmad skill activates; the "phases" are sequential turns inside one skill, not skill hand-offs.
- **Slash commands typed:** `/bmad-quick-dev` only (12 across the corpus).
- **Sub-agent types when dispatched:** `Explore` (6), `general-purpose` (1) — all on feature/refactor, none on bugfix.
- **Bugfix dispatches no sub-agents.** All 3 bugfix trials use the same `Bash`+`Read`+`Edit`+`Write` mix in the main thread; no `Agent` tool calls. The previously claimed "multi-reviewer gate fires on bugfix" (Explore + adversarial + edge-case + acceptance reviewers as sub-agent dispatches) is **not supported by the transcripts** — if reviewer personas appear, they appear as sequential role-play turns inside `bmad-quick-dev`, not as `Agent` dispatches.

## Why it ranked where it did

- **Refactor (rank 3)** is bmad's strongest task — the Plan-Code-Review loop fits a scope-bounded structural change with a named refactor target. `pure` and `claudekit` land ahead, by ≈ 2.45 and 0.30 weighted pts respectively (both inside the noise envelope; refactor top-3 spans 2.45 pts). Wall-clock is 82 min — longest of any bmad cell — driven by the 168-turn main thread and the fact-forcing preamble before each of 29 edits.
- **Bugfix (rank 6)** does **not** benefit from a multi-reviewer sub-agent gate (the audit shows 0 dispatches). Whatever lift bmad has on this task comes from the in-skill checkpoints and fact-forcing preamble, not from reviewer fan-out. `claudekit` and `ecc` separate from the cohort by ≈ 7–13 pts on a task with a tightly named target file.
- **Feature (rank 3)** is a strong spot on score but the `between_σ` of 20.81 is the cohort's highest on this task, meaning judges disagreed widely on the bmad feature artifact — some saw it as thorough, others as overlong. This is a "judge disagreement", not a "tool instability" failure mode (`within_σ` is a low 7.02).

## Strengths & failure modes

**Strengths (transcript-grounded):**
- Fact-forcing preamble before edits and explicit "checkpoint" markers keep the agent from drifting on long sessions; appears as repeated assistant text turns rather than as sub-agent dispatches.
- Matches task shape via the intro: the harness-provided hint flips the workflow between feature / bugfix / refactor without changing the slash command.
- Lean tool-config overhead (~5 config reads per task) — the in-repo `_bmad/` scaffolding is referenced lightly during the run.

**Failure modes (transcript-grounded):**
- Lint is not gated; the workflow does not round-trip `eslint` before declaring done.
- Pre-maturity elicitation is skipped when the agent judges context "sufficient", so the plan step can collapse into a monologue — the failure mode behind the high feature `between_σ`.
- The "multi-reviewer" structure documented upstream does not materialise as actual reviewer sub-agents in this corpus, especially on bugfix; the workflow is effectively single-thread role-play inside `bmad-quick-dev`.

## References

- Install surface: `scripts/setup-tool-config.sh` (case `bmad)`)
- Prompt construction: `scripts/manual-bench.sh` (case `bmad)`)
- Config snapshot: `config/bmad-t<N>/settings.json`, `config/bmad-t<N>/plugins/`
- Transcripts: `results/{bmad,bugfix/bmad,refactor/bmad}/t<N>/session-logs/`
- Per-task reports: [`results/final-report.md`](../../results/final-report.md), [`results/bugfix/final-report.md`](../../results/bugfix/final-report.md), [`results/refactor/final-report.md`](../../results/refactor/final-report.md)
- Upstream repo: https://github.com/bmad-code-org/BMAD-METHOD
