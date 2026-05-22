# Methodology-flow visual diagram — design + implementation spec

**Status:** shipped (2026-05-17 redesign: split into two pipelines + per-mode micro-graphics)
**Owner:** ops
**Last updated:** 2026-05-17

## 1. Problem

The `#how-it-works` section on the landing page (`docs/index.html`) explained the
benchmark methodology with a single dense pipeline that ran trial-generation and
judging through the same row, with the comparative-rank sidecar tacked on below.
Two issues:

1. **The two judging modes looked identical** in the original SVG and the first
   HTML rebuild (same card style for absolute scoring and head-to-head ranking).
   The *point* of the methodology section is to make their difference legible at
   a glance — uniform cards under-sell that distinction.
2. **Trial generation and judging are conceptually independent stages** (one
   produces artifacts, the other evaluates them) but were collapsed into a
   single flow, obscuring that the same artifacts feed two parallel judging
   pipelines.

The redesign splits the section into two `.meth-pipeline` blocks, each with
its own purpose-built visualisation:

- **① Trial generation** — 5-stage linear pipeline (setup → install → execute
  → collect → archive). Same card style and marching arrows as before.
- **② Judging** — two parallel modes rendered side-by-side as bespoke
  micro-graphics that visually encode the distinction between absolute scoring
  and relative ranking, joined at the bottom by a convergent-validity badge.

## 2. Library decision — Motion One

Researched 2025-2026 JS animation landscape via `perplexity_ask`:

| Library | Bundle (gz) | Notes |
|---|---|---|
| **Motion One** | **~5-7 KB** | Framer-team, WAAPI under the hood, CDN-friendly. **Chosen.** |
| anime.js v4 | ~12 KB | Mature, good SVG path support, no scroll-trigger primitive |
| GSAP + ScrollTrigger | ~35-40 KB | Most capable but overkill for our needs |
| CSS Scroll-Driven Animations | 0 KB | Native, but browser support gaps and ergonomics still rough |
| Framer Motion | ~50 KB | React-only — disqualified (static site) |

**Why Motion One:** smallest credible footprint, uses standard Web Animations API
(no proprietary lock-in), drop-in ESM import from `cdn.jsdelivr.net`, no build
step. We don't need GSAP's pinning / multi-stage scroll choreography.

**Version pin:** `motion@10.18.0/+esm` (frozen — `latest` was rejected because a
silent CDN-side breaking change would zero out the methodology section without
any local diff to investigate).

**Tradeoff accepted:** Motion One has no built-in `ScrollTrigger` analog — we
pair its `inView()` helper with `IntersectionObserver` (which it wraps anyway).
That is ~10 lines of glue we'd otherwise pay GSAP 30 KB to skip.

## 3. Files touched

| Path | Change | Status |
|---|---|---|
| `docs/index.html` | Replaced `#how-it-works` section: two `.meth-pipeline` blocks (trial 5 stages + judge split with Mode A panel-diagram + Mode B compare-diagram + convergent-validity join). | ✓ shipped |
| `docs/index.html` end-of-body | Added Motion One `<script type="module">` (pinned `motion@10.18.0/+esm`). Orchestrates trial-pipeline reveal, Mode A sequential build, Mode B shuffle/reorder cycle. JS-fail safe: elements only hidden after the CDN import resolves. | ✓ shipped |
| `docs/index.html` (4 spots) | Renamed user-facing `GPT-5.4-pro` → `GPT-5.4`. Technical IDs (`gpt54pro` in filenames / judge keys) left unchanged. | ✓ shipped |
| `docs/styles.css` | Appended ~310 lines: `.meth-pipeline`, `.judge-split`, `.judge-mode`, `.judge-mode-panel/compare`, `.judge-tag`, `.panel-diagram` (5-column grid + artifact row-span), `.panel-judge`, `.panel-chip`, `.panel-mean`, `.compare-diagram` (3-column grid), `.compare-input` (2×4 tile grid), `.compare-judge` (badge + pulse), `.compare-output` (ranked `<ol>`), `.judge-join`, mobile breakpoint at 880px, `prefers-reduced-motion` overrides. Existing `.flow-*` classes reused for the trial pipeline. | ✓ shipped |
| `docs/charts/methodology-flow.svg` | Deleted (superseded by split diagram + per-mode micro-graphics). | ✓ shipped |

## 4. Animation specification

### 4.1 Trial pipeline reveal (scroll-triggered)

- **Trigger:** `inView('[data-meth-pipeline="trial"]', …, { amount: 0.15 })`
- **Cards** (`.flow-card`):
  - `opacity: 0 → 1`, `transform: translateY(16px) → translateY(0)`
  - `duration: 0.45s`, `delay: stagger(0.07)`, `easing: [0.2, 0, 0.2, 1]`
- **Arrows** (`.flow-arrow`):
  - `opacity: 0 → 1`, `duration: 0.35s`, `delay: stagger(0.07, { start: 0.05 })`
- **Marching-ants stroke** (CSS-only, always on): `stroke-dasharray: 4 4`,
  `stroke-dashoffset: 0 → -16` over 1.4s linear infinite.

### 4.2 Panel micro-graphic — Mode A (scroll-triggered, one-shot)

Sequential build that mirrors the logical flow of judgment:

1. **Artifact** card fades in (0.35s).
2. **Connectors** dash-lines fade in, stagger 0.09s, starting at +0.10s.
3. **Judge** rows fade-and-slide-right (`translateX(-8 → 0)`), stagger 0.10s, starting at +0.20s.
4. **Right-arrows** fade in, stagger 0.10s, starting at +0.35s.
5. **Score chips** fade-slide-scale (`translateX(-10) scale(0.92) → 0/1`), stagger 0.10s, starting at +0.50s.
6. **Weighted-mean row** fades up at +1.30s with a `translateY(8 → 0)` slide.

Once revealed, static. No looping.

### 4.3 Compare micro-graphic — Mode B (continuous loop)

Conveys that the same 8 inputs get re-ordered into a fresh rank every round:

- **Initial reveal:** input tiles fade-up (stagger 0.05s); output ranks fade-up (stagger 0.05s, start 0.40s).
- **Cycle (every 7 s):**
  1. `shuffleTiles()` — assign each input tile a small random `translate(±7px, ±5px)`. CSS `transition: transform 700ms` carries it. 360 ms later the transform is cleared (tiles spring back to grid position).
  2. `reorderRanks()` — fade output rank-tiles to opacity 0.20 (stagger 0.035s), shuffle their text labels, fade back to 1 (stagger 0.04s).
- **Judge node** has a CSS-only border-glow pulse (3.6 s ease-in-out infinite).

Cycle is teardown-aware: `inView` returns a cleanup that `clearInterval`s when
the section leaves view (battery courtesy).

### 4.4 Marching-ants arrows

Reused on the trial pipeline arrows AND the two compare-judge-col input/output
arrows: `stroke-dasharray: 4 4; animation: flow-march 1.4s linear infinite`.

## 5. Accessibility

- **`prefers-reduced-motion: reduce`:** suppresses the marching-ants stroke,
  the compare-judge pulse, the input-tile transitions, and all Motion One
  reveal/cycle animations. Section renders in its final visual state
  immediately. (Implementation: JS short-circuits with `reduce = matchMedia(...)`
  before scheduling any animations; CSS overrides handle the always-on bits.)
- **JS-fail safe:** Both diagrams render at full opacity by CSS default. JS
  sets `opacity:0` on elements *only inside* the `try { await import(...) }`
  block — so if the CDN is blocked or the Motion One package fails to load,
  every element stays visible. Caught failures log a single warning to console
  and exit silently.
- **Semantic markup:** trial-pipeline cards remain `<article>` with `<header>`,
  `<h4>`, `<p>`. Judge modes are also `<article>` with `<header>`, `<h3>`,
  `<p>`. Micro-graphic SVG containers carry `aria-hidden="true"` — the
  surrounding prose in the kicker and the `<h3>`/`<p>` text in each mode
  carries the meaning.
- **Color contrast:** all text uses `--charcoal-warm` (#4d4c48) or
  `--near-black` (#141413) — both ≥ AA on `--parchment` (#f5f4ed) and
  `--ivory` (#faf9f5). The terracotta accents on chips, ranks, and weight
  badges use `--terracotta` (#b95838), which is AA on ivory/parchment.

## 6. Mobile responsiveness

Breakpoint at 880px (set in `styles.css`):

- **Trial pipeline:** `.flow-row` switches to `flex-direction: column`;
  `.flow-arrow` rotates 90° via `transform`.
- **Judge split:** `grid-template-columns: 1fr 1fr` → `1fr` (modes stack).
- **Panel diagram:** column widths shrink (78/22/1fr/22/70 → 68/14/1fr/14/62)
  and judge/chip font sizes drop ~1px.
- **Compare diagram:** `1fr 88px 1fr` → `1fr` (input → judge → output stack
  vertically); judge column flips horizontal so its two arrows lay flat.

## 7. Verification

| Check | How |
|---|---|
| HTML well-formed | `xmllint --html --noout docs/index.html` — pre-existing warnings on Google-Fonts URL line 22 (unencoded `&` in HTML5-permitted attribute) ignored; no new errors introduced. |
| Motion One CDN URL responds | `curl -sI https://cdn.jsdelivr.net/npm/motion@10.18.0/+esm \| head -1` returns 200. |
| CSS classes resolve | All `meth-pipeline`, `judge-*`, `panel-*`, `compare-*`, `rank-*`, `ctile` selectors have at least one rule in `styles.css`. |
| Visual smoke (manual) | Open `docs/index.html` in browser; scroll to `#how-it-works`. (a) trial pipeline staggers in with marching arrows; (b) Mode A builds up artifact → judges → chips → mean in sequence; (c) Mode B shows initial fade-in, then re-shuffles tiles + re-orders ranks every 7 s, with a slow border-glow on the judge node. Hover trial cards for terracotta lift. Resize to <880px and verify both diagrams stack cleanly. |
| `prefers-reduced-motion` honored | Toggle macOS *System Settings → Accessibility → Display → Reduce Motion*; reload. Confirm trial arrows static, panel diagram shows final state immediately, compare diagram shows static sorted state with no shuffle cycle and no pulse. |
| JS-fail fallback | Block `cdn.jsdelivr.net` in dev-tools network panel; reload; confirm trial pipeline, panel diagram, and compare diagram all render at full visibility. Console shows one warning, no errors. |

## 8. Optional extensions (not in current scope)

- **Animate the Spearman ρ values** in the convergent-validity badge by typing
  in the per-task numbers when the section enters view (small touch).
- **Add an "agreement heatmap" hover** on the join badge that shows the
  three per-task ρ values from the actual `_aggregate.json`.
- **Particle traversal on panel arrows.** A small SVG circle animates from
  each judge node to the central mean row, suggesting score aggregation.
- **Sequenced arrow draws on trial pipeline.** Each arrow's marching-ants
  delay until its source card's reveal is complete (currently all start
  together once the section enters view).

Each is ~15-30 LOC and can be added without changing the base structure.

## 9. Rollback

If the rebuild causes issues, revert by:

1. Restore `docs/charts/methodology-flow.svg` from git: `git checkout HEAD~ -- docs/charts/methodology-flow.svg`
2. In `docs/index.html`, replace the `<!-- ============ ① TRIAL PIPELINE ============ -->`
   through `</section>` block with the prior `<figure><img src="charts/methodology-flow.svg" …></figure>`
3. Remove the appended CSS block at end of `docs/styles.css` (from
   `/* ============ Methodology · split pipeline` to end-of-file)
4. Remove the end-of-body `<script type="module">` Motion One import

Total rollback diff: ~510 lines reverted across 2 files. The previous
single-pipeline HTML version was committed before this redesign and can also
be restored from git history if needed.

## 10. Out of scope

- Adding a "diagram refresh" hook to the build pipeline — site is statically
  served by Cloudflare Pages, no build step.
- A11y screen-reader narration of the flow — the kicker paragraph above the
  diagram provides a prose explanation; the diagram is supplemental visual aid.
- Translation / i18n — site is English-only.
- ~~Reconciling `5 trials` vs `3 trials` across PAPER.md / index.html~~ —
  **resolved 2026-05-18**: PAPER.md, README, the index.html meta-strip and
  caption, and all per-task reports now consistently state the canonical
  n=5 / 5 trials × 5 judges × 3 rounds / 1800-judgment cohort.

## 11. Why two bespoke micro-graphics (design rationale)

The original single-row + sidecar version made absolute scoring and
head-to-head ranking visually equivalent — both rendered as "cards with text."
The whole point of the methodology section is to teach the reader that these
are **different judging regimes producing different signals**:

| | Mode A · Panel | Mode B · Comparative |
|---|---|---|
| **Visual metaphor** | One artifact → 5 radiating judges → score chips → weighted mean column | 8 shuffled tiles → single judge box → tiles re-ordered 1-8 |
| **What it teaches** | "Each diff is scored *on its own merits*, independently, multiple times." | "All 8 diffs are forced into a *single relative ranking*, side-by-side, in one prompt." |
| **Output unit** | Absolute score in [0, 200] | Rank in [1, 8] |
| **Aggregate** | Weighted mean across judges | Mean rank across rounds + Spearman ρ vs panel |
| **Animation idiom** | Sequential build (parallel parts visible at once after build) | Continuous re-ordering (different rank every cycle) |

The two micro-graphics make this distinction legible without requiring the
reader to parse the prose. The convergent-validity badge below them reframes
the relationship: *if the two regimes agree on rank order, the panel ranking
is robust; where they disagree (e.g., bugfix ρ = −0.41 in v2), that's a
signal that the regime matters.*
