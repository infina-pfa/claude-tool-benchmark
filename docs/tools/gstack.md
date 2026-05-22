# gstack

**Upstream:** [github.com/garrytan/gstack](https://github.com/garrytan/gstack) — MIT, by Garry Tan (YC). Pinned at SHA `443bde05`, `VERSION` 1.28.0.0. Runtime stack: Claude Code + Bun v1.0+ (plus Node on Windows). Marketed as "Garry's Stack — Claude Code skills + fast headless browser. One repo, one install, entire AI engineering workflow."

## What it is

gstack is a skill pack — 37 directories under `config/gstack-t1/skills/` — that frames Claude Code as a simulated product team: CEO (`/plan-ceo-review`), eng manager (`/plan-eng-review`), designer (`/plan-design-review`, `/design-review`), reviewer (`/review`), QA (`/qa`, `/qa-only`), security officer (`/cso`), release engineer (`/ship`, `/land-and-deploy`, `/canary`), plus debugging (`/investigate`), planning (`/autoplan`, `/office-hours`), retros, scope locks (`/freeze`, `/guard`), and a headless-browser binary. The installer (`./setup --no-prefix`) drops each skill into `$CLAUDE_CONFIG_DIR/skills/`, where Claude Code reads them as top-level slash commands.

Every skill begins with a long `# Preamble (run first)` Bash block that probes `~/.gstack/` for telemetry, proactive-suggest, routing, and vendoring markers, optionally appends a "Skill routing" block to the project CLAUDE.md, and (when proactive is on) auto-invokes peer skills from conversational triggers — `"why is this broken"` routes to `/investigate`, `"ship it"` to `/ship`, `"architecture review"` to `/plan-eng-review`, and so on. Each skill's `description:` frontmatter explicitly names its trigger phrases; that prose is what Claude Code matches against the user turn.

## Benchmark configuration

- Config dir: `config/gstack-t1/`. `settings.json` contains only `{"skipDangerousModePermissionPrompt": true}`; no MCP, no hooks, no allow-list. All behaviour comes from the skill tree. Install shim in `scripts/setup-tool-config.sh` (gstack case, ~L176) clones upstream into `$TOOL_CONFIG/skills/gstack` and runs `HOME=$TOOL_CONFIG ./setup --no-prefix` so `~/.gstack/` writes stay inside the trial.
- Launch prompt (`scripts/manual-bench.sh`, ~L208): feature and refactor fire bare `/autoplan` (no task argument — the skill auto-discovers the PRD from the repo) with the suffix *"When implementation is complete and committed, run /ship to review the diff and finalize."*; bugfix prepends `/investigate $SHARED_TASK` with the suffix *"When the fix is committed, run /ship to review the diff and finalize."* Every task now fires an explicit entry skill per the 2026-04-22 "explicit skill activation" harness change — previously feature and refactor ran with raw `$SHARED_TASK` and relied on prose triggers; that form produced zero or near-zero `Skill` tool calls on some runs, so the rerun pins `/autoplan` (feature/refactor) and `/investigate` (bugfix) as the primary entry points. The 2026-04-23 follow-up dropped `$SHARED_TASK` from the `/autoplan` line after confirming the skill locates the PRD on its own — passing the task text inline was redundant and risked steering the skill away from its own discovery path.

## How the entry points behave

`/investigate` is a four-phase debugger enforcing what the skill calls the **Iron Law: no fixes without root cause**. Phase 1 is root-cause investigation with a regression-diff check; Phase 2 is pattern analysis with an optional sanitized web search; Phase 3 is explicit hypothesis confirmation via temporary logs/assertions before any edit; Phase 4 is the minimal fix; Phase 5 writes a regression test and a capture-learnings entry to `~/.gstack/projects/<slug>/learnings.jsonl`. `PreToolUse` hooks on `Edit`/`Write` call `freeze/bin/check-freeze.sh` to enforce a scope lock.

`/ship` is where gstack's "eng-review gate" lives — the reason gstack is excluded from plan mode. It runs: Step 0 platform detection → Step 1 pre-flight + Review Readiness Dashboard (tallies prior `/plan-ceo-review`, `/codex review`, `/plan-eng-review`, `/plan-design-review`, `/plan-devex-review` runs from `~/.gstack/` logs; verdict is `NO REVIEWS YET` until they've run) → Step 2 merge base branch → Step 2.5 test-framework bootstrap → Step 3 tests, with a Test Failure Ownership Triage that classifies failures as in-branch vs pre-existing and, on collaborative repos, can open and assign a GitHub issue via `gh`. Only after review+tests+eval-suites clear does it bump VERSION, update CHANGELOG, commit, push, and open the PR.

## What the transcripts show (session audit)

Numbers below are mean across 3 trials per task (session-audit run-time subsystem is n=3; the score table above is the full n=5 cohort), from [`scripts/audit-sessions.py`](../../scripts/audit-sessions.py). Per-trial JSON: `results/gstack/t<N>/session-audit.json` (feature), `results/{bugfix,refactor}/gstack/t<N>/session-audit.json`. Cohort summary: [`results/_audits/session-audit.md`](../../results/_audits/session-audit.md).

| Task     | wall min | main turns | sidechain turns | sub-agent disp. | files read (config / target) | files edited | cache hit |
|----------|---------:|-----------:|----------------:|----------------:|------------------------------:|-------------:|----------:|
| feature  | 41.0 | 155.7 | 31.0 | 2.7 | 21.0 (0 / 21.0) | 13.3 | 0.97 |
| bugfix   |  5.9 |  72.0 |  0.0 | 0.0 | 12.7 (0 / 12.7) |  1.3 | 0.97 |
| refactor | 46.3 | **258.7** | 42.7 | 2.7 | 40.3 (0 / 40.3) | 32.7 | 0.98 |

- **Three skills drive the runs:** `autoplan` (456 turns), `ship` (336), `investigate` (216). The plan→ship pair fires every feature/refactor trial; `investigate` fires only on bugfix as intended.
- **Slash commands typed:** `/autoplan` (7), `/ship` (7), `/investigate` (3) — `/autoplan`+`/ship` fire on every feature/refactor trial (6 trials, with one double-fire on each), `/investigate` fires on every bugfix trial.
- **Sub-agent types dispatched:** `general-purpose` (14), `Explore` (2). Notably ≈ 0 dispatch on bugfix — `/investigate`'s "no fixes without root cause" phases run as sequential turns in the main thread.
- **Refactor main-turn count is the cohort's highest (258.7)** — gstack's preamble + skill-routing chatter adds noticeable per-skill turn overhead, especially when `/autoplan` and `/ship` both fire.

## Results

| Task     | Weighted mean /200 | within_σ | between_σ | Rank |
|----------|-------------------:|---------:|----------:|------|
| feature  | 131.98             | 18.35    | 19.41     | 8 / 8 |
| bugfix   | 159.97             | 9.13     | 16.12     | 8 / 8 |
| refactor | 144.92             | 58.43    | 12.52     | 8 / 8 |

gstack is the cohort's weakest performer overall — rank-8 on all three tasks. On `feature` it sits ≈ 7.5 weighted pts below rank-5 `omc` (139.49) — the **only setup cleanly below the main cluster** on any task. `within_σ` of 18.35 on feature is the highest in the cohort, indicating noticeable run-to-run instability in addition to between-judge spread. The refactor `within_σ` of **58.43** is a severe outlier — an order of magnitude above the 4–13 range every other tool sits in on refactor — signalling extreme run-to-run variance on that task, which drags gstack's refactor weighted mean (144.92) far below the rest of the cohort and into rank-8.

## Where it fits

gstack trades blank-prompt flexibility for a fixed organisational metaphor. The ceiling is high when the task lines up with a role gstack already has, and lower when the bottleneck is exploratory reasoning the preamble didn't anticipate. The eng-review gate enforces process cleanliness but does not catch all code-quality issues that judges weight heavily; on this corpus that translates to rank-8 on every task.
