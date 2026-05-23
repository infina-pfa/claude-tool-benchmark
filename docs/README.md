# docs/ — Benchmark Documentation

Everything a reader needs to understand, reproduce, extend, or critique the benchmark.

This folder is organized by *reader intent*. The top-level [`README.md`](../README.md) and [`PAPER.md`](../PAPER.md) are the author-facing entry points; this folder is the reader-facing reference set.

---

## Map

### guides/ — "How do I …?"

| File | Answers |
|---|---|
| [`guides/quickstart.md`](guides/quickstart.md) | How do I clone this repo and run one task end-to-end in ~10 minutes? |
| [`guides/verification.md`](guides/verification.md) | How do I independently verify a specific claim (e.g. "why is `pure` rank-1 on refactor")? |
| [`guides/extending.md`](guides/extending.md) | How do I add a new tool or a new judge to the panel? |

### tools/ — "What is each setup, actually?"

Per-tool profile: version, upstream repo, mechanism (skills/hooks/prompts), what each trial loaded, observed strengths and failure modes.

| File | Tool | Mechanism |
|---|---|---|
| [`tools/README.md`](tools/README.md) | — | Comparison matrix across all 8 tools (mechanism taxonomy, per-task winners, failure modes) |
| [`tools/bmad.md`](tools/bmad.md) | `bmad` | Role-based multi-agent (`/bmad-quick-dev`) |
| [`tools/claudekit.md`](tools/claudekit.md) | `claudekit` | Skill pack + hook gates (`/ck:cook --auto`) |
| [`tools/compound.md`](tools/compound.md) | `compound` | Multi-agent pipeline (`/lfg`) |
| [`tools/ecc.md`](tools/ecc.md) | `ecc` | Plugin pack (`/everything-claude-code:plan`, `/build-fix`) |
| [`tools/gstack.md`](tools/gstack.md) | `gstack` | Product-team simulator (`/autoplan`, `/investigate`, `/ship`) |
| [`tools/omc.md`](tools/omc.md) | `omc` | Meta-orchestrator (`/oh-my-claudecode:autopilot`) |
| [`tools/pure.md`](tools/pure.md) | `pure` | Vanilla Claude Code, no addons |
| [`tools/superpower.md`](tools/superpower.md) | `superpower` | Skill registry (`/superpowers:*`) |

### analysis/ — "What did we learn?"

Rank-order alone is low-signal once the top-cluster intervals overlap. This folder holds the *why*.

| File | Covers |
|---|---|
| [`analysis/feature-cohort.md`](analysis/feature-cohort.md) | Feature-cohort cross-tool analysis: where the top cluster separates, where it ties, and what the session transcripts show about the planning/orchestration patterns that drove it. |
| [`analysis/skill-cost-efficiency.md`](analysis/skill-cost-efficiency.md) | Per-skill `output_tokens / score` and `output_tokens / line` on the feature cohort, derived from `attributionSkill` × `message.usage` in the session JSONLs. ecc clears both efficiency bars; superpower is the 6,353 tok/pt outlier; pure is the zero-skill-burn null. |

### Pre-publish runbook

| File | Covers |
|---|---|
| [`RERUN-PRE-PUBLISH.md`](RERUN-PRE-PUBLISH.md) | Operator runbook for the harness patches applied before the published cohort: R1 sweep behaviour, blind-eval scrubs, σ decomposition, and the verification commands to confirm no fingerprint leaks. |

### preview/ — rendered markdown for the site

HTML renders of every docs markdown file so readers can view them in-browser without leaving the landing page. Rebuilt via `node tooling/render-md-previews.mjs` whenever the source markdown changes.

### Landing page (served from this folder)

`index.html`, `styles.css`, `favicon.svg`, `_headers` are served by Cloudflare Pages from the `docs/` root. The canonical public URL is [`https://claude-tool-benchmark.pages.dev/`](https://claude-tool-benchmark.pages.dev/).

---

## Reader routes

- **"I just want the numbers."** → [`../results/final-report.md`](preview/final-report-feature.html) (feature, tabular) plus [`../results/bugfix/final-report.md`](preview/final-report-bugfix.html) and [`../results/refactor/final-report.md`](preview/final-report-refactor.html), or [`../PAPER.md`](preview/paper.html) (narrative).
- **"I want to verify a specific claim."** → [`guides/verification.md`](guides/verification.md).
- **"I want to re-run one trial."** → [`guides/quickstart.md`](guides/quickstart.md), or [`../PAPER.md`](../PAPER.md) §6 for the full command sequence.
- **"I want to understand what each tool actually does."** → [`tools/README.md`](tools/README.md) (comparison), then the per-tool profile that catches your eye.
- **"I want the *learnings*, not the ranks."** → [`analysis/feature-cohort.md`](analysis/feature-cohort.md).
- **"I want to add my own tool or judge."** → [`guides/extending.md`](guides/extending.md).

---

## Upstream references

The two foundational docs live at the repo root, not here, because they're the public interface of the project:

- [`../README.md`](../README.md) — TL;DR + TOC + caveats headline.
- [`../PAPER.md`](../PAPER.md) — research-paper-style full report.
