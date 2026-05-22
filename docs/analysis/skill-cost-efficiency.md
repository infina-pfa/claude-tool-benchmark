# Skill cost efficiency — output tokens per score point, per line

**Generated**: 2026-05-18 (Score column re-derived from the canonical n=5 weighted mean; cost columns unchanged)
**Score source**: `results/final-report.md` (canonical n=5 weighted-mean feature score)
**Cost source**: `scripts/audit-sessions.py` → `results/_audits/session-audit.json` (n=3 session-audit subset: t1–t3; the t4–t5 audit re-run is pending)
**Scope**: `feature` task. `+Lines` and `Skill out tok` are means over the n=3 session-audited trials (t1–t3) per tool; per-task drill-downs live in [`session-audit.md`](../../results/_audits/session-audit.md).

This page joins two audit fields:

- **`message.usage.output_tokens`** — tokens the model generated on the assistant turn (i.e. the *cost-bearing* tokens billed to output).
- **`attributionSkill`** — the skill/slash-command that owned that turn (captured from Claude Code's session JSONL).

Summed per skill, we get "output tokens spent inside skill X", which we then divide by the trial's weighted feature score and `+Lines` to get two efficiency ratios. The pure (no-addons) setup invokes no skills, so its row is empty by construction — it functions as the zero-skill-burn baseline.

## Caveats

- **Output tokens ≠ full billed cost.** Cache reads and cache creation dominate Claude Opus's $ figure (see `Cost` column in [`feature-cohort.md`](feature-cohort.md)); this page reports the verbosity-inside-skill axis only. For $/score see feature-cohort.md.
- **`attributionSkill` is best-effort.** Turns outside any skill (the main agent loop) are excluded from these totals. A skill that delegates to a sub-agent loses attribution on the sub-agent's turns — sub-agent output appears in cohort totals (see `session-audit.md` § Subagent dispatches) but not in the parent skill's column.
- **n=3 per tool.** A single outlier trial can swing a tool's per-skill mean by ±30 %. Pairs within ~20 % on these ratios should be read as ties.

## Cohort-wide: top skills by output tokens

Aggregated across all 8 tools × 3 tasks × 3 trials = 72 sessions. "Cells" = number of (tool, task) cells the skill appears in (max 3 since each addon is exclusive to one tool).

| Skill | Tool | Cells | Turns | Output tokens |
|---|---|---:|---:|---:|
| `bmad-quick-dev` | bmad | 3 | 1,380 | 693,733 |
| `superpowers:subagent-driven-development` | superpower | 1 | 2,668 | 669,379 |
| `oh-my-claudecode:team` | omc | 3 | 2,153 | 574,078 |
| `oh-my-claudecode:ralplan` | omc | 3 | 1,100 | 559,150 |
| `cook` | claudekit | 3 | 1,707 | 525,514 |
| `autoplan` | gstack | 2 | 456 | 349,544 |
| `compound-engineering:ce-work` | compound | 3 | 727 | 327,751 |
| `compound-engineering:ce-plan` | compound | 3 | 387 | 255,051 |
| `ck-plan` | claudekit | 3 | 540 | 200,432 |
| `ship` | gstack | 2 | 336 | 172,074 |
| `superpowers:writing-plans` | superpower | 1 | 47 | 162,288 |
| `superpowers:brainstorming` | superpower | 3 | 340 | 140,225 |
| `everything-claude-code:plan` | ecc | 3 | 427 | 137,366 |
| `compound-engineering:ce-code-review` | compound | 3 | 261 | 132,251 |
| `oh-my-claudecode:hud` | omc | 3 | 230 | 95,825 |

Each tool's primary skill dominates its skill-output total. `superpowers:subagent-driven-development` is concentrated in a *single* session-task cell (superpower on feature, 2,668 turns) — it generates more output in one feature trial than `bmad-quick-dev` does across all three tasks combined.

## Feature task: tokens per score point, tokens per line

Rows are ordered by the **canonical n=5 weighted-mean feature score** from [`results/final-report.md`](../../results/final-report.md) — so the `Score` column is provenanced and matches the headline benchmark ranking. `+Lines` and `Skill out tok` remain n=3 session-audit means (t1–t3; the t4–t5 audit re-run is pending), so the per-skill token ratios below are **n=3 cost estimates joined to the n=5 score** — read `Tok / pt` as an order-of-magnitude efficiency signal, not a precise n=5 figure. `Skill out tok` is the per-trial-summed output across **all** skills attributed to that tool's feature trials.

| Tool | Score | +Lines | Skill out tok | Tok / pt | Tok / line | Top skill (output) |
|---|---:|---:|---:|---:|---:|---|
| ecc | 153.30 | 1,924 | 48,956 | **319** | **25.4** | `everything-claude-code:plan` (48,956) |
| pure | 143.13 | 821 | 0 | 0 | 0 | (no skills invoked) |
| bmad | 141.33 | 521 | 242,106 | 1,713 | 464.7 | `bmad-quick-dev` (242,106) |
| superpower | 140.16 | 2,706 | 890,464 | **6,353** | 329.1 | `superpowers:subagent-driven-development` (669,379) |
| omc | 139.49 | 1,837 | 511,141 | 3,664 | 278.2 | `oh-my-claudecode:team` (290,393) |
| claudekit | 135.04 | 1,940 | 348,218 | 2,579 | 179.5 | `cook` (274,451) |
| compound | 134.67 | 960 | 322,815 | 2,397 | 336.3 | `compound-engineering:ce-work` (132,134) |
| gstack | 131.98 | 1,000 | 194,449 | 1,473 | 194.4 | `autoplan` (163,706) |

## Observations

**ecc is an order of magnitude more skill-efficient than any other setup.** 25 output tokens per line shipped vs. 180–465 for the rest, and 319 tokens per score point vs. ~1,500–6,400. `everything-claude-code:plan` runs once at the start (427 turns cohort-wide across 3 trials = ~142 turns/trial) and then yields to the main agent loop; ecc's skill ceremony front-loads into one planning pass rather than running a parallel skill context throughout execution. This shows up as the smallest `Skill out tok` column despite the largest `+Lines`.

**superpower's 6,353 tok/pt is the cohort outlier.** `superpowers:subagent-driven-development` runs 2,668 turns in a single feature trial and emits 669k output tokens, but the score does not follow: superpower (140.16) lands **below** `pure` (143.13) on feature. The skill is doing work, but that work is not converting into judged score on feature. Compare to compound (`compound-engineering:ce-work` at 132k tokens for a similar mid-pack score, 134.67).

**`pure` at 0 skill-burn is a usable null.** Pure's 143.13 score is **rank-2 on the canonical feature ranking** with zero attributed skill output. Every tool above 0 in this column is choosing to spend output tokens on skill-internal text (plans, subagent prompts, hooks, status lines) on top of the same base model. The skill-cost-efficient setups are the ones where that spend either (a) stays small (ecc) or (b) translates into measurable lift over the pure baseline. On feature, only ecc clears both bars; superpower and omc spend the most output and score below pure.

## Related

- [`feature-cohort.md`](feature-cohort.md) — full feature-task table with billed `$` cost (cache-aware) and per-trial run-time stats.
- [`../../results/_audits/session-audit.md`](../../results/_audits/session-audit.md) — cohort behavioural fingerprints, top-5 skills per tool, full per-(tool, task) metrics.
- [`../../scripts/audit-sessions.py`](../../scripts/audit-sessions.py) — miner; the `skill_token_cost` field is at TrialMetrics.skill_token_cost.