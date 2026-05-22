# refactor — Equal-Weight Aggregation (companion to final-report.md)

Generated: 2026-05-19T04:05:40Z

## Inputs and source artifacts

Same inputs as the canonical [`final-report.md`](final-report.md) — only the aggregation rule changes here.

- **Trial input (task PRD).** `_blind-eval/prd.md` (omitted from public release).
- **Per-tool prompt prefix.** [`scripts/manual-bench.sh`](../../scripts/manual-bench.sh).
- **Judge input (verbatim request payload).** `_blind-eval/Alpha/round1/` (omitted from public release) (`<judge>-judge.json.request.json`).
- **Judge prompt template.** ``scripts/generate-judge-prompt-combined-v2.sh`` (omitted from public release).
- **Methodology and threats to validity.** [`PAPER.md`](../../PAPER.md) · [`README.md`](../../README.md) · [landing page](https://claude-tool-benchmark.pages.dev/).

## Methodology
- Same cohort, judges, rubric, and 3-round layout as `final-report.md`.
- **Equal weighting** — every judge contributes weight 1 (vs the published weighted mean's opus×3, `GPT-5.4`×2, others×1).
- Use this to verify rank-stability under operator-neutral weighting.

## Ranking (Equal-Weight Mean)

1. **pure** — 182.63/200
2. **claudekit** — 180.76/200
3. **superpower** — 180.51/200
4. **bmad** — 180.08/200
5. **compound** — 177.03/200
6. **ecc** — 176.57/200
7. **omc** — 173.83/200
8. **gstack** — 147.92/200

## Detail

Same cohort and judgments as `final-report.md`; only the aggregation rule differs. Column glossary:

- **Tool** — the setup under test (8 rows). Sort order: Equal-Weight Mean, rank-1 first.
- **Equal-Weight Mean** *(bold; canonical rank column for this comparator)* — straight arithmetic mean over all 75 judgments, every judge counted 1×. Compare against the Weighted Mean in `final-report.md` to verify rank-stability under operator-neutral weighting.
- **Pooled σ** — standard deviation across all 75 judgments (raw spread).
- **within_σ** — within-judge spread: per-judge σ across the 15 samples per tool (5 trials × 3 rounds), then averaged across judges. High = unstable trial-to-trial.
- **between_σ** — between-judge spread: σ across the 5 per-judge means. High = judges systematically disagree about this tool.
- **N** — total judgments aggregated. Should equal 75 when complete (5 trials × 5 judges × 3 rounds).

| Tool | Equal-Weight Mean | Pooled σ | within_σ | between_σ | N |
|---|---|---|---|---|---|
| pure | **182.63** | 13.10 | 4.44 | 13.73 | 75 |
| claudekit | **180.76** | 16.25 | 5.29 | 17.01 | 75 |
| superpower | **180.51** | 14.74 | 5.09 | 15.39 | 75 |
| bmad | **180.08** | 14.86 | 5.48 | 15.28 | 75 |
| compound | **177.03** | 15.96 | 6.04 | 16.40 | 75 |
| ecc | **176.57** | 16.91 | 8.71 | 16.12 | 75 |
| omc | **173.83** | 17.50 | 7.43 | 17.52 | 75 |
| gstack | **147.92** | 58.70 | 58.43 | 12.52 | 75 |

## Cross-rule comparison

Compare `Equal-Weight Mean` here against `Weighted Mean` in `final-report.md`. Rank-1 is identical under both rules on every task in this corpus; mid-pack ranks 4–7 may swap by at most 2 positions.

