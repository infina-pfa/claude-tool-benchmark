# superpower

Superpowers is a skill-pack plugin for Claude Code by Jesse Vincent (`obra`). It ships a library of named skills — `brainstorming`, `writing-plans`, `test-driven-development`, `systematic-debugging`, `verification-before-completion`, and roughly two dozen more — that the base model is expected to invoke via the `Skill` tool when appropriate.

**Source.** [`obra/superpowers`](https://github.com/obra/superpowers); skills live in [`obra/superpowers-skills`](https://github.com/obra/superpowers-skills) (MIT), marketplace manifest in [`obra/superpowers-marketplace`](https://github.com/obra/superpowers-marketplace). The benchmark installs at pinned `5.1.0` (marketplace SHA `f2cbfbef`). Setup writes two lines to `settings.json` (`enabledPlugins` + marketplace entry). No wrapper command, no hook, no MCP server — a pure skill registry.

**Benchmark invocation.** The harness fires a single skill trigger — `/superpowers:brainstorming` — on **every task** (feature, bugfix, refactor), per the 2026-04-25 harness decision that superseded an earlier bugfix-specific `systematic-debugging` + `verification-before-completion` suffix (`scripts/manual-bench.sh`, case `superpower)`, L144–154). Downstream skill chaining (writing-plans, test-driven-development, systematic-debugging, verification-before-completion, etc.) is left entirely to the base model. No task is pinned to a downstream skill; activation past the brainstorming entry is model-driven on all three tasks, bugfix included.

## What the plugin actually installs

A named skill registry plus short `SKILL.md` files loaded into context. Relevant skills for this benchmark: `superpowers:brainstorming`, `writing-plans`, `executing-plans`, `test-driven-development`, `systematic-debugging`, `verification-before-completion`, `dispatching-parallel-agents`, and `using-superpowers` (the meta-skill that tells the model to consult the registry before responding). The harness auto-triggers only `brainstorming`; everything downstream is the skill descriptions plus whatever the base model has learned about when to invoke them. Bugfix is **not** an exception — it uses the same `/superpowers:brainstorming` entry as feature and refactor, with model-driven downstream activation.

## What the benchmark measured

| Task     | Weighted mean /200 | within_σ | between_σ | Rank |
|----------|-------------------:|---------:|----------:|------|
| feature  | 140.16             | 10.06    | 15.14     | 4 / 8 |
| bugfix   | 166.41             | 7.48     | 13.28     | 4 / 8 |
| refactor | 177.56             | 5.09     | 15.39     | 4 / 8 |

Superpower lands rank-4 on all three tasks — feature, bugfix, and refactor. On refactor it sits ≈ 2.63 weighted pts behind rank-1 `pure` (180.19); on feature it is ≈ 13.14 pts behind rank-1 `ecc` (153.30). On bugfix it is rank-4 under the same `/superpowers:brainstorming` entry used on the other tasks (no skills are pinned). Refactor `within_σ` of 5.09 is among the lowest in the cohort on that task, just above `pure` (4.44).

The harness prompt is the **same on every task** — a single brainstorming entry:

```
/superpowers:brainstorming

<SHARED_TASK>
```

> **Correction (2026-05-18).** Earlier versions of this profile claimed the bugfix harness pinned `/superpowers:systematic-debugging` at session start and `/superpowers:verification-before-completion` as a completion gate, and that this "isolates skill quality from the base model's trigger-phrase sensitivity." That is false. `scripts/manual-bench.sh` fires only `/superpowers:brainstorming` on bugfix — confirmed as the sole typed slash command in all five bugfix trials — and `verification-before-completion` never attribution-fires in any bugfix trial. Bugfix activation is **not** controlled; it is as model-driven as feature and refactor. The session-audit analysis below has been re-derived from that reality.

## What the transcripts show (session audit)

Numbers below are mean across 3 trials per task (session-audit run-time subsystem is n=3; the score table above is the full n=5 cohort), from [`scripts/audit-sessions.py`](../../scripts/audit-sessions.py). Per-trial JSON: `results/superpower/t<N>/session-audit.json` (feature), `results/{bugfix,refactor}/superpower/t<N>/session-audit.json`. Cohort summary: [`results/_audits/session-audit.md`](../../results/_audits/session-audit.md).

| Task     | wall min | main turns | sidechain turns | sub-agent disp. | files read (config / target) | files edited | cache hit |
|----------|---------:|-----------:|----------------:|----------------:|------------------------------:|-------------:|----------:|
| feature  | 229.6 | 183.3 | **778.7** | **18.3** | 104.3 (1.7 / 101.7) | 65.7 | 0.95 |
| bugfix   |  13.6 | 118.3 |     0.0   |     0.0  |  15.3 (0 / 15.3)    |  4.7 | 0.97 |
| refactor | 218.5 | 133.0 |    42.3   |     0.7  |  29.3 (0 / 29.3)    | 17.7 | 0.95 |

- **Sub-agent fan-out is the cohort's largest on feature** (18.3 dispatches mean) but **collapses on bugfix (0)** and **refactor (0.7)**. The `subagent-driven-development` skill activates aggressively on feature work and not at all on bugfix or refactor — explaining why feature wall-clock is 17× bugfix's despite both being base-model Opus 4.7.
- **Bugfix downstream activation diverges sharply run-to-run (n=5).** All bugfix trials enter via `/superpowers:brainstorming`; what activates next is model-driven and inconsistent: t1 → `test-driven-development` (78 turns), t2/t3 → `systematic-debugging` (109 / 116), t4/t5 → `brainstorming` only (no downstream debugging skill). `verification-before-completion` **never attribution-fires** on any bugfix trial. This is exactly the trigger-phrase sensitivity the harness does *not* control for — there is no bugfix pin.
- **Skills observed (corpus union):** `superpowers:subagent-driven-development` (2,668 turns), `brainstorming` (340), `systematic-debugging` (225), `test-driven-development` (78), `writing-plans` (47). The 225 systematic-debugging turns are the bugfix t2+t3 trials only, not a pinned-and-always-on skill (corrected 2026-05-18).
- **Sub-agent types dispatched:** `general-purpose` (55), `Explore` (2) — heavily skewed to one type, vs. omc's role-split dispatches.
- **No slash command in the `<command-name>` channel.** The `/superpowers:brainstorming` entry is delivered in the prompt body on every task (not the `<command-name>` channel) and registers as a `Skill` invocation; downstream skills are model-driven. The transcripts confirm the registry-only mechanism the docs claim.
- **Bugfix has 0 sidechain turns and 0 sub-agent dispatches on every trial (n=5).** Whatever downstream skill activates (TDD / systematic-debugging / none) runs entirely in the main thread; the bugfix corpus never fans out reviewers (≈ 93–124 main turns/trial, ≈ 3.6 files edited, ≈ 13 wall min).

## Failure modes

1. **Activation dependence on entry-point wording.** The one-shot harness passes a terse prompt led only by `/superpowers:brainstorming`; the model can read it as a direct execution request and skip deeper skills. This applies to **all three tasks including bugfix** — the harness names only the `brainstorming` entry, never a downstream skill, so which skill (if any) activates next is model-driven and varies trial-to-trial (n=5 bugfix: TDD / systematic-debugging / none). Earlier text claiming bugfix "controls for this" was incorrect (corrected 2026-05-18).

2. **Skill output lands mid-pack on bugfix, not top-3.** When a debugging skill does activate (bugfix t2/t3 → `systematic-debugging`) it keeps the diff scoped — but it is not reliably activated (t1 → TDD, t4/t5 → brainstorming only) and `verification-before-completion` never fires. Judges score bugfix ≈ 13 weighted pts below rank-1 `claudekit`. The gap is a mix of skill-content headroom and inconsistent activation, not a single clean pipeline.

## Honest positioning

Superpowers is a well-constructed skill library. On feature-class work and on refactor it costs nothing and consistently lands in the top half — rank-4 on both feature and refactor in this n=5 corpus, behind ecc and pure respectively on those tasks. The base-model dependency on trigger-phrase pattern-matching for activation is a real operating-condition caveat for anyone deploying this in a one-shot harness: if the entry prompt does not name the skills, the registry may stay dormant.
