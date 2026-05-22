# omc (oh-my-claudecode)

**Disclosure.** `omc` is maintained by the benchmark author (`Yeachan-Heo/oh-my-claudecode`). The ranking below should be read in that light — the tool was evaluated on a benchmark its own author designed, and it still lands near the bottom. That is the expected direction for an honest self-report, but it does not cancel the conflict of interest. Every rubric item, task brief, and judge prompt was chosen by the same author; an external replication is the only thing that would remove the concern.

## Identity

- **Repo:** `github.com/Yeachan-Heo/oh-my-claudecode`
- **Plugin version at run:** 4.13.6 (`8b24a29d`)
- **License:** MIT, Copyright 2025 Yeachan Heo
- **Install mechanism:** Claude Code plugin marketplace
- **Invocation in this benchmark:** two-message flow — `/oh-my-claudecode:omc-setup`, then `/oh-my-claudecode:ralplan <task>`; after ralplan lands the consensus plan the operator manually types `/oh-my-claudecode:team` to execute it via team workers

## Mechanism

omc is an orchestration layer. It ships a large surface area — agents, hooks, skills, a status line, a `.omc/` state directory, and an experimental agent-teams flag — and routes work through specialized subagents. The stated model is delegate-first: `ralplan` produces a consensus plan via planner + architect + critic agents, then `team` auto-decomposes that in-context plan and spawns worker agents to execute it. Parent transcripts are large; the tool spends tokens coordinating.

## What the transcripts show (session audit)

Numbers below are mean across 3 trials per task (session-audit run-time subsystem is n=3; the score table above is the full n=5 cohort), from [`scripts/audit-sessions.py`](../../scripts/audit-sessions.py). Per-trial JSON: `results/omc/t<N>/session-audit.json` (feature), `results/{bugfix,refactor}/omc/t<N>/session-audit.json`. Cohort summary: [`results/_audits/session-audit.md`](../../results/_audits/session-audit.md).

| Task     | wall min | main turns | sidechain turns | sub-agent disp. | files read (config / target) | files edited | cache hit |
|----------|---------:|-----------:|----------------:|----------------:|------------------------------:|-------------:|----------:|
| feature  | 223.5 | 170.7 | **1556.0** | **10.7** | **227.0** (17.3 / 209.7) | 126.3 | 0.93 |
| bugfix   |  37.6 | 109.0 |  122.0     |  3.7     |  35.3 (0.3 / 35.0)       |   7.7 | 0.92 |
| refactor | 185.0 | 186.7 |  481.3     | 12.3     |  76.0 (4.7 / 71.3)       |  34.0 | 0.93 |

- **Highest sidechain volume in the cohort.** Feature averages 1,556 sidechain turns vs the cohort median of ~50 — the `team` skill spawns workers that each carry their own long thread.
- **Skills observed:** `oh-my-claudecode:team` (2,153 turns), `oh-my-claudecode:ralplan` (1,100), `oh-my-claudecode:hud` (230), `oh-my-claudecode:omc-setup` (111), `oh-my-claudecode:cancel` (6). The two-message harness (`omc-setup` → `ralplan` → operator-typed `team`) is visible end-to-end.
- **Sub-agent types dispatched:** `oh-my-claudecode:executor` (24), `oh-my-claudecode:critic` (18), `oh-my-claudecode:architect` (17), `oh-my-claudecode:planner` (16), `Explore` (4) — the planner/architect/critic split the ralplan docs describe materialises in `attributionSkill` + `subagent_type` rows.
- **Only setup with material tool-config read overhead.** Mean 17.3 tool-config reads per feature trial (vs 0 for almost all other tools). `.omc/`, `.claude/skills/`, and the project's CLAUDE.md are re-read during execution — the "setup tax" of an orchestrator that maintains its own scaffolding.
- **Cache hit ratio is the cohort's lowest** (~0.93 vs others' 0.96–0.98) — the sidechain fan-out forces more cache creation per worker.
- **Slash commands typed:** `/oh-my-claudecode:team` (10), `/oh-my-claudecode:omc-setup` (9), `/clear` (9), `/oh-my-claudecode:ralplan` (9), `/login` (3), `/oh-my-claudecode:cancel` (1).

## Results

| Task     | Weighted mean /200 | within_σ | between_σ | Rank |
|----------|-------------------:|---------:|----------:|------|
| feature  | 139.49             | 10.88    | 17.29     | 5 / 8 |
| bugfix   | 164.80             | 15.66    | 13.74     | 7 / 8 |
| refactor | 170.11             | 7.43     | 17.52     | 7 / 8 |

omc lands in the bottom half on every task — rank 5 on feature, 7 on bugfix, 7 on refactor. On feature omc edges ahead of `claudekit` (139.49 vs 135.04) for rank-5. The bugfix `within_σ` of 15.66 is still the highest in the cohort on that task — the autopilot loop produces unusually variable bugfix output run-to-run.

## What the mechanism did here

**The ceremony entry point costs a full message.** `/oh-my-claudecode:omc-setup` is a setup step — it bootstraps CLAUDE.md injection, hooks, and the `.omc/` state directory — and no other tool in the cohort requires it. The bench runner has a dedicated `OMC_TWO_MSG=1` branch precisely to accommodate this. In a single-session evaluation the setup message contributes no code; it is pure prelude. That alone does not explain the cohort-bottom finish, but it sets the tone for the rest of the trace.

**Orchestration did not substitute for scope discipline.** The premise of a ralplan→team pipeline with planner / architect / critic agents and team workers is that it catches scope-and-quality mistakes the bare baseline would miss. On these three tasks it did not — `pure`, the unadorned baseline, is top-3 on every task and rank-1 on refactor, while omc lands rank-5 on feature and rank-7 on both bugfix and refactor.

## Honest read

omc is a plausible design. The problem is not noise per se: refactor `within_σ` is 7.43 — above the 4–6 range the rest of the orchestrators sit in, but well below gstack's 58.43 refactor outlier. The bigger story is that the orchestration surface, on these three tasks, did not produce code that judges preferred over a plain Claude session. The bench author's own tool underperforms a zero-ceremony baseline; this disclosure is retained at the top of the file for the reader.

## Reproducing

```bash
TASK=feature ./scripts/create-clones.sh 1
TASK=feature ./scripts/manual-bench.sh omc 1
# MSG1: paste /oh-my-claudecode:omc-setup, wait for setup to complete.
# MSG2: paste /oh-my-claudecode:ralplan "<task>", wait for the consensus plan.
# MSG3 (operator-typed): type /oh-my-claudecode:team to spawn workers.
# Exit when the tool has committed.
```

Artifacts live under `results/{omc,bugfix/omc,refactor/omc}/t<N>/`. Session logs and subagent transcripts are retained verbatim; the `.omc/` state directory is gitignored by the benchmark safety rules and does not leave the clone.
