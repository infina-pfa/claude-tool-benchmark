# AI Coding Tool Benchmark — Methodology Pass (2026-05-16)

> **Correction (2026-05-18):** the MDE figures below were computed with a normal z critical value; the corrected exact Student-t MDEs are feature 19.33 / bugfix 22.17 / refactor 44.02.

External-comms drafts for the methodology pass that added Krippendorff α,
formal MDE / power analysis, per-judge z-normalized sensitivity, per-trial
skill-firing counts, and the outlier-audit / no-rerun verdict to every
per-task report.

The pass also **retracts** the earlier "claudekit beats pure on bugfix →
strict null rejected" claim. The 9.4-pt gap is below the formal n=5
bugfix MDE of 22.17 pts, so it is not significant at standard
thresholds. Top-cluster orderings are *point-estimate first, statistically
tied at this sample size.* (The cohort has since expanded to n=5 trials
per cell and the report-side MDE recompute is **done**: the per-task
reports now print the true n=5 MDE — 19.33 / 22.17 / 44.02 pts on
feature / bugfix / refactor, using the exact Student-t critical value
t(0.975, df=2(n-1)=8) ≈ 2.306 rather than the normal z=1.96 (at n=5
this enlarges MDE ~12%; the β/power term keeps the normal z=0.84 as a
deliberate conservative approximation). The expansion did *not* cut MDE
as 1/√n; σ_pool rose on every task — see `docs/IMPROVEMENT-PLAN-NEXT-COHORT.md`
item #1, now closed.)

---

## Tweet / Mastodon / Bluesky (under 280 chars)

> Methodology pass on the AI Coding Tool Benchmark (8 Claude Code setups
> · 3 tasks · 5 judges · 1800 judgments). Added formal MDE / power
> analysis → every rank-1 lead in the cohort is below detection threshold.
> Top cluster is statistically tied. Honest > definitive.
>
> https://claude-tool-benchmark.pages.dev/

**Alt — shorter, "what changed":**

> Update on the benchmark: added Krippendorff α + formal MDE per task,
> recomputed at the full n=5. Result: no rank-1 lead in the v2 cohort is
> significant at α=0.05. Retracted the "claudekit beats pure on bugfix"
> strict-null claim — the gap is below detection threshold. Adding 2
> honest trials per cell *raised* the MDE, not lowered it.
>
> https://claude-tool-benchmark.pages.dev/

---

## LinkedIn / blog / forum post (~150 words)

**The honest update I owe readers of our AI Coding Tool Benchmark**

We benchmarked 8 Claude Code setups across 3 tasks (5-judge weighted
panel, 5 trials per cell, 1800 judgments). The original write-up
flagged 5 rank-1 leaders by task. After re-running the numbers with
a formal power analysis at the cohort's actual n=5, those leads are
**all below the Minimum Detectable Effect** — the per-task reports
now print the true n=5 MDE: 19.33 pts on feature, 22.17 pts on
bugfix, 44.02 pts on refactor (σ_pool 9.72 / 11.14 / 22.13), computed
with the exact Student-t critical value t(0.975, df=8) ≈ 2.306, not
the normal z=1.96. The n=3→n=5 expansion did *not* cut MDE the way
1/√n would predict: σ_pool rose on every task (feature 7.87→9.72,
bugfix 9.99→11.14, refactor 6.07→22.13; the n=3 estimate had
under-stated trial-to-trial variance), so MDE did not scale down as
1/√n. Largest observed rank-1 lead is 10.17 pts
(feature) — below every threshold.

The corollary: the earlier claim that *"claudekit beats pure on bugfix
by 9.4 pts → tools-add-no-value null rejected"* is retracted. The gap
is real by point estimate; it is below detection threshold by formal
test. The top cluster on every task is statistically tied at this
sample size.

What does survive the formal test: exactly one separation in the
entire 1800-judgment corpus clears MDE — **ecc−gstack on feature
(≈21.3 > 19.33)**. Nothing clears MDE on bugfix (claudekit−gstack
18.96 < 22.17) or refactor (pure−gstack 35.27 < 44.02; gstack's own
trial-4 refactor diff — a mechanically clean, valid in-distribution
run that judges scored ≈36/200 vs ~178 on its other four trials —
inflates refactor σ_pool and kills its significance). Under the
pre-registered no-selective-rerun rule that trial is *not*
rerun-eligible, and the rising MDE is the headline finding.

Every report now publishes Krippendorff α (panel agreement adjusted
for chance), MDE per task, a per-judge z-normalized sensitivity check,
and an outlier audit (~3.1% round-outlier rate across the corpus,
below the 5% chance baseline — no reruns triggered, no harness bugs
found). The n=5 MDE recompute is done; the surprising result — adding
two honest trials *raised* the bar — is itself the demonstration of
why the pre-registration forbids post-hoc selective reruns
(`docs/IMPROVEMENT-PLAN-NEXT-COHORT.md` item #1, closed).

Reports: <https://claude-tool-benchmark.pages.dev/>
Methodology updates: any of the `Power analysis`, `Inter-rater agreement`,
or `Outlier audit` sections in the per-task reports.

---

## Hacker News submission (title + first comment)

**Title (≤ 80 chars):**
> Show HN: Methodology pass on AI tool benchmark — every rank-1 lead is statistically tied

**First comment (the honest version):**

> Author here. Quick changelog for anyone who read the earlier writeup:
>
> Added formal MDE / power analysis to every per-task report and
> recomputed at the cohort's actual n=5. The reports now print the
> true n=5 MDE: 19.33 / 22.17 / 44.02 weighted pts on
> feature / bugfix / refactor, using the exact Student-t critical
> value t(0.975, df=8) ≈ 2.306, not the normal z=1.96. Surprise:
> going n=3→n=5 did *not* cut MDE ~23% as 1/√n predicts — σ_pool
> rose on every task (feature 7.87→9.72, bugfix 9.99→11.14, refactor
> 6.07→22.13; the n=3 σ_pool had under-estimated true trial-to-trial
> variance), so MDE did not scale down as 1/√n. Every rank-1 lead in
> the cohort (≤ 10.17 pts) is still below threshold. The strict-null
> "tools add no value over baseline" claim from the bugfix section is
> retracted — claudekit's 9.4-pt lead over pure is well below the
> 22.17-pt n=5 bugfix MDE.
>
> What survives the formal test: exactly one separation in the whole
> corpus clears MDE — ecc−gstack on feature (≈21.3 > 19.33). Nothing
> clears MDE on bugfix or refactor; gstack's refactor gap to rank-1
> (35.27) does *not* clear the 44.02-pt refactor MDE, because gstack's
> own clean-but-low trial-4 refactor run (judged ≈36/200 vs ~178 on
> its other four; tsc 0, 77/77 tests, real diff, slash commands fired
> — a valid in-distribution trial, not rerun-eligible under the
> pre-registered rule) inflates that task's σ_pool. Everything inside
> the top cluster is tied at this sample size.
>
> Also added: Krippendorff α (interval, judges-as-coders) per task —
> 0.124 / 0.284 / 0.626 (these α are an upper bound — computed on
> round-averaged scores, so true per-round agreement is lower). α is
> low on feature/bugfix because judges
> differ sharply in base-rate lenience (gpt-5.4-pro is reliably 19–27
> pts below the panel; mimo-2.5-pro reliably above); refactor sits just
> below the tentative band. The weighted-mean aggregation
> is the intended mitigation and the per-judge z-normalized sensitivity
> column is now published for ordering robustness.
>
> Outlier audit at the round level: ~3.1% of round-judgments exceed
> the 2σ flag (vs ~5% expected under chance) — no reruns triggered,
> no skill failures across 7 non-baseline tools × 3 tasks × 5 trials.
>
> The n=5 MDE recompute is done; the headline is that adding two
> honest trials per cell *raised* the bar — the empirical case for why
> the pre-registration forbids post-hoc selective reruns. Everything
> reproducible from `scripts/aggregate-results.sh` +
> `scripts/compute-{krippendorff,power-analysis,outlier-audit}.py`.

---

## /r/LocalLLaMA or /r/MachineLearning post

**Title:**
> [P] Methodology pass on the open AI Coding Tool Benchmark — adding power analysis retracts most "rank-1" claims

**Body:**

We've been running an open, blind-judged benchmark of 8 Claude Code
setups (plugins, skill packs, hook kits, no-addon baseline) across
3 software-engineering tasks. 1800 judgments by a 5-vendor judge panel.
Full corpus published.

This week we added formal power analysis and inter-rater agreement
to every per-task report. Two notable findings:

1. **MDE recomputed at the cohort's actual n=5 is 19.33 / 22.17 / 44.02
   weighted points on feature / bugfix / refactor** (σ_pool 9.72 /
   11.14 / 22.13, pooled across 8 tools using trial-level weighted
   means), using the exact Student-t critical value t(0.975, df=8) ≈
   2.306, not the normal z=1.96. The surprise: raising n from 3→5 did
   *not* cut MDE ~23% as
   1/√n predicts — σ_pool rose on every task (feature 7.87→9.72,
   bugfix 9.99→11.14, refactor 6.07→22.13) because the n=3 estimate
   had under-stated trial-to-trial variance, so MDE did not scale down
   as 1/√n. Every rank-1 lead in the cohort is below
   MDE. The reported orderings are valid as point estimates, but
   they're statistically tied at this sample size.

2. **Krippendorff α is 0.124 / 0.284 / 0.626 on feature/bugfix/refactor**
   (interval level, judges as coders; these α are an upper bound —
   computed on round-averaged scores, so true per-round agreement is
   lower). On feature/bugfix the judges agree
   weakly on absolute scores; refactor sits just below the tentative band. Caveat:
   α is suppressed by per-judge
   lenience drift — gpt-5.4-pro is reliably 19–27 pts below the panel,
   mimo-2.5-pro reliably above. Tool *orderings* are more stable
   than absolute scores. We publish both the weighted mean (canonical)
   and a per-judge z-normalized sensitivity column for ordering
   robustness.

The post-pass narrative: exactly one separation in the entire
1800-judgment corpus clears the detection threshold — ecc−gstack on
feature (≈21.3 > 19.33). Nothing clears MDE on bugfix
(claudekit−gstack 18.96 < 22.17) or refactor (pure−gstack 35.27 <
44.02). gstack's refactor gap looks large by point estimate but does
*not* clear MDE: its own trial-4 refactor diff — mechanically clean
(tsc 0, 77/77 tests pass, real 504/73-line diff, slash commands
fired) but judged ≈36/200 vs ~178 on its other four trials — is a
valid in-distribution run that inflates refactor σ_pool. Under the
pre-registered no-selective-rerun rule it is not rerun-eligible.
Everything else inside the top cluster is tied.

The n=5 MDE recompute is *done*, and the surprising result is the
finding: adding two honest trials per cell raised the bar instead of
lowering it — the empirical demonstration of why the pre-registration
forbids post-hoc selective reruns. No open action remains on this
(`docs/IMPROVEMENT-PLAN-NEXT-COHORT.md` item #1, closed).

Curious what the community thinks the right framing is when a blind
multi-judge eval has high point-estimate spread but low statistical
power — keep publishing rank-1s as canonical (with the MDE caveat
inline)? Drop them entirely until N is raised? We chose the former
because the canonical-rank framing is widely cited, but happy to hear
other framings.

Reports: https://claude-tool-benchmark.pages.dev/
Repo: https://github.com/infina-pfa/claude-tool-benchmark

---

## Email to a colleague / mailing list (~100 words)

Quick heads up if you're using the benchmark numbers in any internal
deck or talk:

We added formal MDE / power analysis this week and recomputed at the
full n=5. The earlier claim that "claudekit beats pure on bugfix →
tools-add-no-value null is rejected" is retracted — the 9.4-pt gap is
below the 22.17-pt n=5 bugfix MDE. All rank-1 leads in the cohort are
below detection threshold. The honest framing is "rank-1 by point
estimate, statistically tied at this sample size."

The surprise: n=3→n=5 did *not* cut MDE ~23% (σ_pool rose on every
task: feature 7.87→9.72, bugfix 9.99→11.14, refactor 6.07→22.13).
True n=5 MDE is 19.33 / 22.17 / 44.02 on feature / bugfix /
refactor (exact Student-t t(0.975, df=8) ≈ 2.306, not z=1.96). Only
one separation in the whole corpus clears MDE:
ecc−gstack on feature (21.3 > 19.33). Nothing clears it on bugfix or
refactor — gstack's big-looking refactor gap (35.27) sits under the
44.02 MDE because its own valid trial-4 variance inflated σ_pool.

The n=5 recompute is done — no open action; that the bar *rose* is
the finding (`docs/IMPROVEMENT-PLAN-NEXT-COHORT.md` item #1, closed).

Reports as before: https://claude-tool-benchmark.pages.dev/

---

## What stays the same / what changes (one-pager for the README PR if needed)

| Claim | v2 original | v2 + methodology pass |
|---|---|---|
| `ecc` rank-1 on feature | Yes (153.30) | Yes (153.30) — **point estimate; tied to top cluster** |
| `claudekit` rank-1 on bugfix | Yes (178.93) | Yes (178.93) — **point estimate; tied to top cluster** |
| `pure` rank-1 on refactor | Yes (180.19) | Yes (180.19) — **point estimate; tied to top cluster** |
| "Strict null rejected on bugfix by claudekit > pure" | Claimed | **Retracted** (9.4 pts ≪ 22.17-pt n=5 MDE) |
| `gstack` significantly below cohort on refactor | Implicit | **Not significant** (pure−gstack 35.27 < 44.02-pt n=5 MDE; gstack's valid trial-4 variance inflates σ_pool) |
| `gstack` separation on feature | Implicit | **The only separation in the corpus that clears MDE** (ecc−gstack 21.3 > 19.33); not separated from the pack |
| `gstack` / cohort on bugfix | Implicit | **Not significant** (claudekit−gstack 18.96 < 22.17-pt n=5 MDE) |
| `omc` on refactor | Implicit | **Not significant** (~2-pt gap to cohort) |
| n=3→n=5 MDE recompute | n=3 figure printed | **Done**: true n=5 MDE 19.33 / 22.17 / 44.02 — σ_pool *rose* on every task, MDE did not scale down as 1/√n (item #1 closed) |
| Inter-rater agreement | Not published | Krippendorff α: 0.124 / 0.284 / 0.626 (upper bound — round-averaged; true per-round lower) |
| Round-outlier audit | Not published | ~3.1% rate (below 5% chance); no reruns triggered |
| Skill-firing audit | Aggregated only | Per-trial counts published |
| Per-judge z-normalized check | Not published | Published; rank-1 invariant |
