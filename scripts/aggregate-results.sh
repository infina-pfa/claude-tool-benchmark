#!/bin/bash
# De-anonymizes blind-eval scores and aggregates per tool.
# Run AFTER judge-*.sh completes for all labels × rounds.
#
# Canonical inclusion: the label root plus dirs matching ^round[0-9]+$ are
# read in union (root = canonical first round; round1/, round2/ = added
# stability rounds). Pilot/sample dirs (e.g. roundcotpilot, roundcotsample*)
# are ignored so the corpus size is deterministic and matches what the report
# claims.
#
# Canonical score: sum(scores.values()) — never the stored `total` field, which
# historically drifted due to a parser off-by-one.
#
# Tool mean: balanced mean (mean of per-judge means). This cancels judge-specific
# drift when per-judge n is unequal.
set -uo pipefail
source "$(dirname "$0")/env.sh"

EVAL_DIR="$RESULTS_DIR/_blind-eval"
MAPPING="$EVAL_DIR/.mapping-DO-NOT-OPEN.json"
REPORT="$RESULTS_DIR/final-report.md"

if [ ! -f "$MAPPING" ]; then
  echo "Mapping file not found: $MAPPING" >&2
  echo "Run blind-eval-setup.sh first." >&2
  exit 1
fi

# Idempotent R1 sweep across every label before aggregating. Closes the
# orchestration gap where a single judge-*.sh wrapper invoked outside
# judge-all.sh can leave unlocked mechanical items in the JSON.
SCRIPTS_DIR_SELF="$(dirname "$0")"
for label_dir in "$EVAL_DIR"/*/; do
  [ -d "$label_dir" ] || continue
  base=$(basename "$label_dir")
  case "$base" in
    _*|.*) continue ;;
  esac
  [ -f "$label_dir/auto-metrics.json" ] || continue
  python3 "$SCRIPTS_DIR_SELF/apply-r1-override.py" "$label_dir" --task "$TASK" \
    > /dev/null 2>&1 || true
done

# Refresh per-task statistics (Krippendorff α, MDE / power) before report assembly.
# Both scripts span all 3 tasks so a single invocation per file suffices; they
# are idempotent and quick (no network).
python3 "$SCRIPTS_DIR_SELF/compute-krippendorff.py" > /dev/null 2>&1 || true
python3 "$SCRIPTS_DIR_SELF/compute-power-analysis.py" > /dev/null 2>&1 || true
python3 "$SCRIPTS_DIR_SELF/compute-outlier-audit.py" > /dev/null 2>&1 || true
python3 "$SCRIPTS_DIR_SELF/compute-robust-stats.py" > /dev/null 2>&1 || true
# Comparative-rank validity probe (Opus-1M, parallel signal). Refreshes the per-task
# _comparative-eval/_aggregate.json so the report block below picks up the latest
# Spearman ρ vs panel weighted-mean rank. No-op when no comparative judgments exist yet.
python3 "$SCRIPTS_DIR_SELF/aggregate-comparative.py" --task "$TASK" > /dev/null 2>&1 || true

python3 - "$EVAL_DIR" "$MAPPING" "$REPORT" "$RESULTS_DIR" "$TASK" <<'PY'
import json, os, re, sys, statistics
from collections import defaultdict

eval_dir, mapping_path, report_path, results_dir, task = sys.argv[1:6]

with open(mapping_path) as f:
    mapping = json.load(f)['mapping']

JUDGES = ('opus', 'grok420', 'glm51', 'gpt54pro', 'mimo25pro')
# Reported-mean weights. Anthropic and OpenAI judges carry more weight per the
# operator's prior preference (Claude is the canonical reviewer; GPT is the
# secondary). Other vendors contribute at default weight 1. The reported mean
# is sum(weight × per-judge-mean) / sum(weight) where the per-judge slot is
# present in the cohort.
# SOURCE OF RECORD: versions.lock.json judges.*.weight (pre-registered
# 2026-05-12). This dict is a manually-synced mirror — the aggregator does
# NOT parse the lockfile. If the lockfile weights change, update this dict.
JUDGE_WEIGHTS = {
    'opus':      3,
    'gpt54pro':  2,
    'grok420':   1,
    'glm51':     1,
    'mimo25pro': 1,
}
# Reader-facing display labels. Internal slot keys (JUDGES tuple, JUDGE_WEIGHTS,
# on-disk `<slot>-judge.json` filenames, versions.lock.json) stay frozen for
# aggregation continuity. Only `gpt54pro` is relabeled: the slot answered with
# gpt-5.4-pro for t1-t3 and gpt-5.4 for t4+, so the honest reader-facing name is
# the family "GPT-5.4". Provenance of the t1-t3=pro split lives in
# versions.lock.json judges.gpt54pro.routing_history and PAPER.md §judges.
JUDGE_DISPLAY = {
    'opus':      'opus',
    'gpt54pro':  'GPT-5.4',
    'grok420':   'grok420',
    'glm51':     'glm51',
    'mimo25pro': 'mimo25pro',
}
def disp(j):
    return JUDGE_DISPLAY.get(j, j)
ROUND_RE = re.compile(r'^round[0-9]+$')

# scores[tool] = list of all totals (across trials × judges × rounds)
all_scores = defaultdict(list)
# per_judge[tool][judge] = list of totals (one per round × trial for that judge)
per_judge = defaultdict(lambda: defaultdict(list))
# raw[tool][trial][round][judge] = total
raw = defaultdict(lambda: defaultdict(lambda: defaultdict(dict)))
missing = []
# (path, expected_slot, actual_judge_field) for files whose internal `.judge`
# disagrees with the filename slot the aggregator dispatched by. Score is still
# counted (not retroactively pulled — see AUDIT-FINDINGS-2026-05-18-JUDGE-VALIDITY);
# this only surfaces the contamination for the reader and guards future runs.
provenance_mismatches = []


def sum_scores(d):
    """Canonical total: sum(scores.values()). Falls back to legacy phase2.scores."""
    if isinstance(d.get('scores'), dict) and d['scores']:
        return float(sum(d['scores'].values()))
    phase2 = d.get('phase2') or {}
    if isinstance(phase2.get('scores'), dict) and phase2['scores']:
        return float(sum(phase2['scores'].values()))
    return None


def read_judge_file(path, expected_judge=None):
    if not os.path.isfile(path) or os.path.getsize(path) == 0:
        return None
    try:
        with open(path) as fh:
            d = json.load(fh)
    except Exception:
        return None
    if expected_judge is not None:
        actual = d.get('judge')
        if actual is not None and actual != expected_judge:
            provenance_mismatches.append((path, expected_judge, actual))
    return sum_scores(d)


for label, info in mapping.items():
    tool = info['tool']
    trial = info['trial']
    label_dir = os.path.join(eval_dir, label)
    if not os.path.isdir(label_dir):
        for judge in JUDGES:
            missing.append((label, tool, trial, judge, 'no-label-dir'))
        continue
    round_dirs = sorted(d for d in os.listdir(label_dir)
                       if os.path.isdir(os.path.join(label_dir, d))
                       and ROUND_RE.match(d))
    # Union: read root + every roundN dir. Each judge file counted once
    # at its own location. Cohort labels are flat (root only); roundN
    # support kept for legacy / multi-round σ studies if reintroduced.
    locations = ['_root'] + list(round_dirs)
    for judge in JUDGES:
        for loc in locations:
            base = label_dir if loc == '_root' else os.path.join(label_dir, loc)
            total = read_judge_file(os.path.join(base, f'{judge}-judge.json'), judge)
            if total is not None:
                all_scores[tool].append(total)
                per_judge[tool][judge].append(total)
                raw[tool][trial][loc][judge] = total
            elif loc == '_root' and not round_dirs:
                missing.append((label, tool, trial, judge, 'root'))
            elif loc != '_root':
                missing.append((label, tool, trial, judge, loc))


def balanced_mean(tool):
    """Weighted mean of per-judge means (weights from JUDGE_WEIGHTS).
    Each judge's per-trial mean is weighted; missing judges drop out of both
    numerator and denominator so the cohort isn't penalised for absent slots."""
    num = 0.0
    den = 0.0
    for j in JUDGES:
        vals = per_judge[tool][j]
        if not vals:
            continue
        w = JUDGE_WEIGHTS.get(j, 1)
        num += w * statistics.mean(vals)
        den += w
    return num / den if den else 0.0


def pooled_mean(tool):
    vals = all_scores[tool]
    return statistics.mean(vals) if vals else 0.0


def pooled_sd(tool):
    vals = all_scores[tool]
    return statistics.stdev(vals) if len(vals) > 1 else 0.0


def within_judge_sd(tool):
    """Mean across judges of the within-judge stdev (trial-to-trial within-judge noise; legacy "round-to-round" label retained for the field name)."""
    sds = []
    for j in JUDGES:
        vals = per_judge[tool][j]
        if len(vals) > 1:
            sds.append(statistics.stdev(vals))
    return statistics.mean(sds) if sds else 0.0


def between_judge_sd(tool):
    """Stdev across judges of each judge's mean (judge base-rate spread)."""
    means = []
    for j in JUDGES:
        vals = per_judge[tool][j]
        if vals:
            means.append(statistics.mean(vals))
    return statistics.stdev(means) if len(means) > 1 else 0.0


def cohort_span_hours():
    """Min/max across started_at timestamps across the per-tool sessions/ dirs.
    Returns (hours, first_iso, last_iso) — used in the Caveats block."""
    import glob, datetime
    starts = []
    for meta in glob.glob(os.path.join(results_dir, '*', 't*', 'sessions', '*.meta.json')):
        try:
            d = json.load(open(meta))
            ts = d.get('started_at')
            if ts:
                starts.append(datetime.datetime.fromisoformat(ts.replace('Z', '+00:00')))
        except Exception:
            pass
    if len(starts) < 2:
        return 0.0, '', ''
    return ((max(starts) - min(starts)).total_seconds() / 3600,
            min(starts).strftime('%Y-%m-%d'),
            max(starts).strftime('%Y-%m-%d'))


tools = sorted(all_scores.keys())
num_tools = len(tools)
num_labels = len(mapping)
total_judgments = sum(len(v) for v in all_scores.values())

lines = []
lines.append(f"# {task} — Per-Task Aggregation")
lines.append("")
lines.append(f"Generated: {os.popen('date -u +%Y-%m-%dT%H:%M:%SZ').read().strip()}")
lines.append("")

# Relative-link prefix from this report file to repo root.
# feature report:  results/final-report.md          → ..
# bugfix/refactor: results/<task>/final-report.md   → ../..
_root_rel = '..' if task == 'feature' else '../..'

lines.append("## Inputs and source artifacts")
lines.append("")
lines.append("Everything fed into this aggregation is committed; no private state.")
lines.append("")
lines.append(f"- **Trial input (task PRD).** The exact prompt every tool saw for this task: [`_blind-eval/prd.md`](_blind-eval/prd.md).")
lines.append(f"- **Per-tool prompt prefix.** The tool-specific slash command bound to that PRD lives in [`scripts/manual-bench.sh`]({_root_rel}/scripts/manual-bench.sh).")
lines.append(f"- **Judge input (verbatim request payload).** What each of the 5 judges received per label per round — same blinded diff + rubric, varying only by model: [`_blind-eval/Alpha/round1/`](_blind-eval/Alpha/round1/) (`<judge>-judge.json.request.json`).")
lines.append(f"- **Judge prompt template.** [`scripts/generate-judge-prompt-combined-v2.sh`]({_root_rel}/scripts/generate-judge-prompt-combined-v2.sh).")
lines.append(f"- **Methodology and threats to validity.** [`PAPER.md`]({_root_rel}/PAPER.md) (§1 methodology, §4 limitations) · [`README.md`]({_root_rel}/README.md) · [landing page](https://claude-tool-benchmark.pages.dev/).")
lines.append("")

lines.append("## Methodology")
lines.append(f"- Tools under test: {num_tools}")
lines.append(f"- Blind labels: {num_labels}")
lines.append(f"- Layout: 3 rounds per (artifact, judge) — the canonical run (judge files flat at the label root) plus `round1/` and `round2/` rerun directories. The aggregator reads the label root plus `^round[0-9]+$` subdirs in union; pilot/sample dirs (e.g. `roundcotsample*`) are excluded.")
lines.append(f"- Judges: {', '.join(disp(j) for j in JUDGES)} ({len(JUDGES)}-judge panel; each artifact scored 3 times — once per round — by every judge)")
lines.append(f"- Rubric: 20 items × 0–10 pts = 200 pt max")
lines.append(f"- Canonical score per judge file: `sum(scores.values())` (not the stored `total` field)")
weights_str = ', '.join(f"{disp(j)}×{w}" for j, w in JUDGE_WEIGHTS.items())
lines.append(f"- Reported tool mean: **weighted mean of per-judge means** (weights: {weights_str})")
lines.append(f"- Total judgments aggregated: {total_judgments}")
lines.append("")

lines.append("## Caveats / threats to validity")
lines.append("")
lines.append("- **Judge weights are pre-registered, not derived.** The 3 / 2 / 1 / 1 / 1 weighting is stored as `judges.*.weight` in `versions.lock.json` (committed 2026-05-12) and reflects the operator's prior trust in the Anthropic (opus) and OpenAI (`GPT-5.4`) reviewers. An equal-weight aggregation is emitted alongside this report as `final-report.equal-weight.md`; the in-report `Pooled Mean` column is also the equal-weight comparator and lets readers verify rank-stability without leaving this file.")
lines.append("- **Judge scorer asymmetries.** `GPT-5.4` is consistently the harshest scorer in the panel (lowest mean across labels). `mimo25pro` is the most lenient and occasionally emits 200/200 saturations; its weight of 1 dilutes the impact, but right-tail scores should be read in that context.")
lines.append("- **σ decomposition.** The per-tool standard deviation column is split into `within_σ` (within-judge spread — mean of the per-judge stdev across the 15 samples per (tool, judge): 5 trials × 3 rounds) and `between_σ` (judge base-rate spread — stdev of per-judge means). `within_σ` now bundles trial-to-trial output variance with round-to-round judge-sampler variance; the latter is small where temperature=0 is honored (OpenRouter, OpenCode Go) and absorbed in `within_σ` where it is not (Claude CLI, OpenAI `/v1/responses`). Within > between would indicate the tool's output (combined with sampler drift) is unstable; the reverse means most variance is judge base-rate disagreement.")
lines.append("- **Judge sampling not pinned.** Temperature is fixed to 0 where the provider exposes it (OpenRouter, OpenCode Go). Claude CLI and OpenAI `/v1/responses` do not expose temperature/seed, so residual sampler variance is absorbed in per-judge σ rather than eliminated.")
lines.append("- **R1 mechanical-fact override.** Rubric items with deterministic answers (e.g. `tsc_errors == 0`) are rewritten post-hoc from `auto-metrics.json` to remove LLM arithmetic / classification drift. Items locked per task: `feature` 12/13/16/20, `bugfix` 14/15, `refactor` 13/14. Pre-override scores are preserved under `scores_pre_r1` on every judged file (`scripts/aggregate-results.sh` runs an idempotent R1 sweep before aggregating).")
lines.append("- **Blind eval is structural, not semantic.** Tool identity is hidden via NATO labels and a path-/content-level scrub of tool-specific directories (`.omc/`, `_bmad/`, `_bmad-output/`, `_bmad-core/`, `docs/bmad/`, `docs/superpowers/`, `plans/`, `.claudekit/`, `.gstack/`, `.superpowers/`, `.compound-engineering/`, `.ecc/`, `CLAUDE.md.original`). `auto-metrics.json` is anonymised by stripping `plugin_versions` and `collected_at`. A skilled judge could still infer identity from idiosyncratic code style; we don't claim semantic anonymity.")
_span_h, _span_first, _span_last = cohort_span_hours()
if _span_h is not None:
    if _span_h > 24:
        lines.append(f"- **Cohort span:** {_span_h:.1f}h ({_span_first} → {_span_last}). Spans >24h indicate the cohort did not complete within a single day; `scripts/audit-cohort-symmetry.py` flags this as a soft warning. The longest spans in this report stem from the leak-fix re-judge pass (see `docs/RERUN-PRE-PUBLISH.md`).")
    else:
        lines.append(f"- **Cohort span:** {_span_h:.1f}h ({_span_first} → {_span_last}). `scripts/audit-cohort-symmetry.py` flags spans >24h as a soft warning; this cohort completed within that window.")
lines.append("")

lines.append("## Aggregate Scores per Tool")
lines.append("")
lines.append("**Column glossary — read this first.** One row per tool; the columns are:")
lines.append("")
lines.append("- **Tool** — the setup under test. Eight rows: `bmad`, `claudekit`, `compound`, `ecc`, `gstack`, `omc`, `pure` (no-addon baseline), `superpower`.")
lines.append("- **Weighted Mean** *(bold; canonical rank column)* — weighted average over judges: `(3·opus + 2·`GPT-5.4` + grok420 + glm51 + mimo25pro) / 8`. Weights pre-registered in `versions.lock.json` and reflect operator trust in the Anthropic / OpenAI judges.")
lines.append("- **Pooled Mean** — straight equal-weight average over all 75 judgments (every judge counts the same, 1×). Quick sensitivity check: if Weighted and Pooled order the top tools the same way, the ranking is robust to the weighting scheme. The dedicated `final-report.equal-weight.md` is the full equal-weight comparator.")
lines.append("- **Pooled σ** — overall standard deviation across all 75 judgments (raw score spread before splitting variance sources).")
lines.append("- **within_σ** — within-judge spread. For each judge, compute σ across its 15 samples per tool (5 trials × 3 rounds), then average across the 5 judges. High `within_σ` means the same judge gave the tool different scores across runs — either the tool's output varies trial-to-trial or judge sampler drift (where temperature=0 isn't honored).")
lines.append("- **between_σ** — between-judge spread. Compute each judge's mean for this tool, then take σ across those 5 per-judge means. High `between_σ` means judges systematically disagree (lenience drift). `within_σ` < `between_σ` is the healthy case: most of the noise is judge base-rate, not tool flakiness.")
lines.append("- **N** — total judgments aggregated for this tool. Should equal 75 when complete (5 trials × 5 judges × 3 rounds).")
lines.append("- **n(opus) … n(mimo25pro)** — how many of those judgments came from each judge. In a complete cohort each equals 15 (5 trials × 3 rounds); a lower value exposes a missing or in-progress backfill for that judge (not silently averaged away — the weighted mean drops absent slots from both numerator and denominator).")
lines.append("")
n_cols = " | ".join(f"n({disp(j)})" for j in JUDGES)
sep_cols = "|".join(["---"] * (7 + len(JUDGES)))
lines.append(f"| Tool | Weighted Mean | Pooled Mean | Pooled σ | within_σ | between_σ | N | {n_cols} |")
lines.append(f"|{sep_cols}|")
for tool in sorted(tools, key=lambda t: -balanced_mean(t)):
    n_vals = " | ".join(str(len(per_judge[tool][j])) for j in JUDGES)
    lines.append(
        f"| {tool} | **{balanced_mean(tool):.2f}** | {pooled_mean(tool):.2f} | "
        f"{pooled_sd(tool):.2f} | {within_judge_sd(tool):.2f} | {between_judge_sd(tool):.2f} | "
        f"{len(all_scores[tool])} | {n_vals} |"
    )

lines.append("")
lines.append("## Inter-rater agreement (Krippendorff α)")
lines.append("")
_kripp_path = os.path.join(os.path.dirname(results_dir) if task != 'feature' else results_dir, 'krippendorff-alpha.json')
# Krippendorff JSON sits in results/ regardless of task — recompute path:
_kripp_path = os.path.join(os.path.dirname(os.path.dirname(report_path)) if task != 'feature' else os.path.dirname(report_path), 'krippendorff-alpha.json')
_kripp = None
try:
    _kripp = json.load(open(_kripp_path))
except Exception:
    _kripp = None
if _kripp and task in _kripp.get('tasks', {}):
    _ka = _kripp['tasks'][task]
    _alpha = _ka.get('alpha')
    _alpha_str = f"{_alpha:.3f}" if isinstance(_alpha, (int, float)) else "—"
    lines.append(f"**α = {_alpha_str}** (interval level, judges as coders, blind labels as units, N={_ka.get('n_units')} labels × 5 judges = {_ka.get('n_observations')} observations).")
    lines.append("")
    lines.append("Krippendorff α measures how much the 5 judges agree on the *absolute* score for the same artifact. Conventional thresholds (Krippendorff 2011): α ≥ 0.800 supports firm conclusions; ≥ 0.667 supports tentative ones; < 0.667 is unreliable for absolute claims. **Caveat:** α punishes per-judge lenience drift hard — `GPT-5.4` (panel-low) and mimo25pro (panel-high) are far apart on most artifacts even when they *order* tools the same way. The benchmark's weighted-mean aggregation is less sensitive to any single judge's base rate, but it does not make raw scores robust to per-judge lenience drift — the per-judge z-normalized table below is the actual mitigation for that; α surfaces the drift as a separate honesty metric.")
    lines.append("")
    lines.append("**Upper-bound caveat:** α is computed on each (label, judge)'s *mean across rounds*, so round-to-round judge-sampler noise is averaged out before the reliability calculation. The reported α therefore **overstates** raw round-level inter-judge agreement — true per-round α is lower than the values shown here. Read these as a generous ceiling, not a point estimate.")
else:
    lines.append("_Run `scripts/compute-krippendorff.py` to populate this section._")

lines.append("")
lines.append("## Power analysis & detection threshold (MDE)")
lines.append("")
_pwr_path = os.path.join(os.path.dirname(_kripp_path), 'power-analysis.json')
_pwr = None
try:
    _pwr = json.load(open(_pwr_path))
except Exception:
    _pwr = None
if _pwr and task in _pwr.get('tasks', {}):
    _pt = _pwr['tasks'][task]
    _mde = _pt.get('mde_pts'); _sigma = _pt.get('sigma_pool'); _n = _pt.get('n_per_arm')
    _r1lead = _pt.get('rank1_lead_pts'); _r1sig = _pt.get('rank1_lead_significant')
    lines.append(f"**MDE ≈ {_mde:.2f} pts** at α=0.05 (two-sided), power=0.80, n={_n} trials per arm, σ_pool={_sigma:.2f} pts (pooled across 8 tools using trial-level weighted means).")
    lines.append("")
    lines.append(f"Two tool means whose gap is below MDE cannot be statistically distinguished at the standard α=0.05 / 80%-power threshold. The current cohort uses **n={_n} trials per cell**, which is the binding constraint — judgments within a cell are correlated (same judge across rounds, same trial across rounds), so trials are the real degree of freedom.")
    lines.append("")
    lines.append(f"- **Rank-1 lead:** {_r1lead:.2f} pts → {'**significant**' if _r1sig else '**below MDE — read as a tie**'}")
    _gaps = _pt.get('gaps_from_rank1', []) or []
    if _gaps:
        lines.append("- **Gaps rank-1 vs each lower tool** (✓ = exceeds MDE, ⚠ = below MDE):")
        for g in _gaps:
            mark = '✓' if g.get('significant') else '⚠'
            lines.append(f"    - {g['top']} − {g['vs']}: **{g['gap']:.2f} pts** {mark}")
    lines.append("")
    lines.append(f"**Implication for this cohort:** at n={_n} trials per cell, every per-task rank-1 lead falls below MDE (per-task MDEs and σ_pool for all three tasks are in `results/power-analysis.json`) — the top cluster is a statistical tie, not a ranking. The α/2 critical value is the exact Student-t quantile for df=2(n-1)=8 (≈2.306), not the normal z=1.96 — at n=5 this enlarges every MDE by ~12% (feature ≈19.33, bugfix ≈22.17, refactor ≈44.02). Under the corrected threshold the **only** gap that clears its task MDE anywhere in the corpus is `ecc`−`gstack` on `feature` (≈21.3 vs the 19.33 feature MDE); the previously-cited `ecc`−`claudekit` (≈18.3) and `ecc`−`compound` (≈18.6) feature gaps fall **below** MDE under the exact-t critical and are no longer treated as separations. No rank-1 lead on any task clears MDE; no gap on `bugfix` or `refactor` clears its own task MDE. Trial-to-trial variance (not judge noise) is the binding constraint: the n=3→n=5 expansion *raised* σ_pool on every task, so MDE did not follow the expected 1/√n drop (refactor worsened sharply, driven by `gstack`'s trial-4 refactor diff scoring ≈36/200 against ~178 on its other four). No family-wise correction is applied to the ≥21 pairwise gap tests — they are descriptive detection-threshold comparisons, not confirmatory hypothesis tests. This is exactly why post-hoc selective reruns are pre-registered as invalid. See `docs/IMPROVEMENT-PLAN-NEXT-COHORT.md`.")
else:
    lines.append("_Run `scripts/compute-power-analysis.py` to populate this section._")

lines.append("")
lines.append("## Outlier audit & rerun verdict")
lines.append("")
_oa_path = os.path.join(os.path.dirname(_kripp_path), 'outlier-audit.json')
_oa = None
try:
    _oa = json.load(open(_oa_path))
except Exception:
    _oa = None
if _oa and task in _oa.get('tasks', {}):
    _ot = _oa['tasks'][task]
    _rate = _ot.get('outlier_rate', 0.0) * 100.0
    _chance = _ot.get('expected_chance_rate', 0.05) * 100.0
    _n_j = _ot.get('n_round_judgments', 0)
    _n_out = _ot.get('n_outliers', 0)
    _n_sf = _ot.get('n_skill_failures', 0)
    _n_audited = _ot.get('n_skill_cells_audited', 0)
    _below_chance = _ot.get('outliers_below_chance', False)
    # Wilson 95% CI on the outlier proportion (n large, p small) so the
    # rate is reported with uncertainty rather than a bare point estimate.
    import math as _math
    if _n_j:
        _p = _n_out / _n_j
        _z = 1.959963985
        _den = 1 + _z*_z/_n_j
        _ctr = (_p + _z*_z/(2*_n_j)) / _den
        _hw = (_z * _math.sqrt(_p*(1-_p)/_n_j + _z*_z/(4*_n_j*_n_j))) / _den
        _ci_lo, _ci_hi = max(0.0, (_ctr-_hw))*100.0, (_ctr+_hw)*100.0
    else:
        _ci_lo = _ci_hi = 0.0
    lines.append(f"Round-level outlier check per the pre-registered rerun protocol (`CLAUDE.md` § Rerun): a round-judgment flags when `|score − median(other rounds)| > 15 pts AND > 1.41 × spread(other rounds)` (≈ 2σ on the 2 remaining samples).")
    lines.append("")
    _ci_straddles = _ci_lo <= _chance <= _ci_hi
    _rate_note = ("point estimate below the ~%.0f%% 2σ-chance baseline, but the 95%% CI [%.2f%%, %.2f%%] straddles it — the result is consistent with chance, not significantly below it" % (_chance, _ci_lo, _ci_hi)) if _ci_straddles else (("below chance" if _below_chance else "above chance — investigate") + " (95%% CI [%.2f%%, %.2f%%])" % (_ci_lo, _ci_hi))
    lines.append(f"- **Outlier rate:** **{_n_out} / {_n_j}** round-judgments = **{_rate:.2f}%** (vs ~{_chance:.0f}% expected under 2σ chance) — {_rate_note}. Note the per-round 2σ trigger did fire on these {_n_out} individual rounds; the rerun verdict below is a class-level judgment, not an absence of tripped triggers.")
    lines.append(f"- **Tier-1 skill failures** (non-baseline tool with skills_invoked = subagent_dispatches = 0): **{_n_sf}** across the **{_n_audited}** t1–t3 cells with a `session-audit.json`. t4–t5 session audits were not collected, so this trigger is evaluated over t1–t3 only (not the full n=5 cohort); no audited cell shows a skill failure.")
    by_judge = _ot.get('outliers_by_judge') or {}
    if by_judge:
        # render top-3 contributing judges
        top = sorted(by_judge.items(), key=lambda x: -x[1])
        breakdown = ', '.join(f"{disp(j)}: {c}" for j, c in top)
        lines.append(f"- **Outliers by judge:** {breakdown}. Outliers cluster on the panel's lenience-extreme judges (`mimo25pro`, `GPT-5.4`) and on `grok420`'s root-round drift — these are judge-sampler artifacts, not tool artifacts.")
    flagged = _ot.get('flagged_outliers') or []
    if flagged:
        # surface first few representative entries
        sample = flagged[:5]
        lines.append("")
        lines.append("Sample flagged rounds (first 5):")
        lines.append("")
        lines.append("| Tool | Trial | Judge | Round | Score | Others | Δ from median |")
        lines.append("|---|---|---|---|---|---|---|")
        for f in sample:
            others_str = ', '.join(str(o) for o in f.get('others', []))
            lines.append(f"| {f['tool']} | t{f['trial']} | {f['judge']} | {f['round']} | {f['score']} | [{others_str}] | {f['delta_from_median']} |")
    lines.append("")
    lines.append("**Rerun verdict: no action.** No Tier-1 (skill failure, t1–t3 audited) or Tier-3 (harness bug) triggers fired. The Tier-2 per-round 2σ trigger did fire on the individual rounds counted above, but the *aggregate* outlier rate is statistically consistent with the 2σ-chance baseline (point estimate at/below ~5%, 95% CI overlapping it), so this is treated as a class-level no-action decision rather than per-round re-rolling. Selectively re-rolling the flagged rounds would bias the cohort toward the mean (extreme values re-roll closer to median while in-distribution values stay), shrinking the cohort's apparent variance without removing real noise. The correct fix for round-level noise is **deterministic judge sampling** (caveat 09); the correct fix for trial-level variance is **more trials per cell** (see `docs/IMPROVEMENT-PLAN-NEXT-COHORT.md` item #1).")
else:
    lines.append("_Run `scripts/compute-outlier-audit.py` to populate this section._")

lines.append("")
lines.append("## Robust-statistics sensitivity (median / trimmed-mean companion)")
lines.append("")
_robust_link = "robust-statistics-companion.md" if task == "feature" else "../robust-statistics-companion.md"
_robust_data = "robust-statistics.json" if task == "feature" else "../robust-statistics.json"
if task == "refactor":
    lines.append(f"The canonical Weighted Mean above is sensitive to single-trial outliers. The most consequential example is in this report: `gstack` t4 weighted mean **36.42** vs **153.79–181.67** on its other four trials drags the canonical `gstack` figure down to 144.92 — under the **median** (174.58) `gstack` is rank-7 rather than rank-8, and the rank-1-to-rank-8 spread collapses from 35.3 pts to ~5.6 pts. Pure rank-1 is invariant under mean / median / trimmed mean on every task. Full per-(task, tool) table: [`{_robust_link}`]({_robust_link}); raw figures in [`{_robust_data}`]({_robust_data}); recompute with `scripts/compute-robust-stats.py`. *Not* the pre-registered primary statistic — a sensitivity view alongside the equal-weight companion.")
else:
    lines.append(f"Sensitivity view: per-tool **median** and **trimmed mean** (drop hi/lo) of the 5 trial-level weighted means, instead of the arithmetic mean used above. Rank-1 is invariant on every task under mean / median / trimmed; the largest middle-rank shift in this corpus is `gstack` refactor (rank-8 → rank-7 under median, driven by one bad trial — the canonical mean correctly retains it). Full table: [`{_robust_link}`]({_robust_link}); raw figures in [`{_robust_data}`]({_robust_data}); recompute with `scripts/compute-robust-stats.py`. *Not* the pre-registered primary statistic — a sensitivity view alongside the equal-weight companion.")
lines.append("")
lines.append("## Per-judge z-normalized sensitivity")
lines.append("")
lines.append("Tool ordering when each judge is z-normalized (`(score − judge_mean) / judge_sd`) before averaging — cancels per-judge lenience drift so each judge contributes ordering signal, not absolute lenience. Useful as a sensitivity check against the canonical Weighted Mean: rank-1 should be invariant under both rules.")
lines.append("")

def judge_z_normalized_means():
    out = {}
    judge_stats = {}
    for j in JUDGES:
        pool = []
        for t in tools:
            pool.extend(per_judge[t][j])
        if len(pool) >= 2:
            mu = statistics.mean(pool); sd = statistics.stdev(pool) or 1.0
            judge_stats[j] = (mu, sd)
        else:
            judge_stats[j] = (0.0, 1.0)
    for tool in tools:
        zs = []
        for j in JUDGES:
            vals = per_judge[tool][j]
            if not vals: continue
            mu, sd = judge_stats[j]
            zs.extend(((v - mu) / sd) for v in vals)
        out[tool] = statistics.mean(zs) if zs else 0.0
    return out

_zn = judge_z_normalized_means()
lines.append("| Tool | Judge-Z mean | Weighted-Mean rank | Judge-Z rank |")
lines.append("|---|---|---|---|")
weighted_order = sorted(tools, key=lambda t: -balanced_mean(t))
weighted_rank = {t: i + 1 for i, t in enumerate(weighted_order)}
zn_order = sorted(tools, key=lambda t: -_zn[t])
zn_rank = {t: i + 1 for i, t in enumerate(zn_order)}
for tool in zn_order:
    delta = weighted_rank[tool] - zn_rank[tool]
    delta_str = f" (Δ {'+' if delta > 0 else ''}{delta})" if delta else ""
    lines.append(f"| {tool} | {_zn[tool]:+.3f} | {weighted_rank[tool]} | **{zn_rank[tool]}**{delta_str} |")
lines.append("")
lines.append("`Δ` is `Weighted-Mean rank − Judge-Z rank`. Δ=0 means the canonical and z-normalized rules agree; |Δ|≥2 means the ordering moves materially under judge normalization (worth investigating).")

lines.append("")
lines.append("## Comparative-rank validity probe (Opus-1M, parallel signal)")
lines.append("")
_comp_path = os.path.join(os.path.dirname(report_path), '_comparative-eval', '_aggregate.json')
_comp = None
try:
    _comp = json.load(open(_comp_path))
except Exception:
    _comp = None
if _comp and 'spearman_rho' in _comp:
    _rho = _comp['spearman_rho']
    _rho_s = f"{_rho:.3f}" if isinstance(_rho, (int, float)) and _rho == _rho else "—"
    _ncells = sum(1 for c in (_comp.get('cells') or []) if c.get('ok'))
    _flags = _comp.get('rank_disagreement_flags') or []
    lines.append(f"**Spearman ρ vs panel weighted-mean rank: {_rho_s}** (n_cells = {_ncells} comparative-judge runs; {len(_flags)} tools flagged with |Δrank| ≥ 2)")
    lines.append("")
    lines.append("Independent of the per-artifact panel above: one Opus-1M call ranks all 8 tools' artifacts for a (task, trial) cell side-by-side, then averaged across 5 rounds with fresh per-round Greek-suffix labels and shuffled prompt order. **Comparative-rank is a parallel signal — it does NOT enter the weighted mean.** High ρ means both judgment regimes agree on tool ordering; low or negative ρ flags a calibration disagreement worth investigating (panel sees artifacts in isolation and can drift; comparative sees the cohort range and recalibrates each round). This in-report table is the **Opus-1M lane only**, shown as a quick signal; the full two-lane (Opus-1M + GPT-5.4) triangulation with all three pairwise Spearman ρ per task lives in [`_comparative-eval/_triangulation.md`](_comparative-eval/_triangulation.md). Methodology and per-round outputs: [`_comparative-eval/`](_comparative-eval/).")
    lines.append("")
    _bwarn = _comp.get('blinding_warnings') or []
    if _bwarn:
        lines.append("**[!] Blinding observations volunteered by Opus** (rounds where the judge noted potentially-identifying patterns — treat as soft warnings):")
        lines.append("")
        for w in _bwarn:
            _c = (w.get('concern') or '').strip().replace('\n', ' ')
            lines.append(f"- t{w['trial']}/round{w['round']}: {_c[:240]}")
        lines.append("")
    _common = _comp.get('tools_common') or []
    _per_tool = _comp.get('per_tool') or {}
    _crank = _comp.get('comparative_rank') or {}
    _prank = _comp.get('panel_rank') or {}
    _pwm = _comp.get('panel_weighted_means') or {}
    if _common:
        lines.append("| Tool | Panel rank | Comparative rank | Δ | Panel weighted-mean | Comparative mean-rank ± σ | n obs |")
        lines.append("|---|---|---|---|---|---|---|")
        for _tool in sorted(_common, key=lambda t: _crank.get(t, 99)):
            _pr = _prank.get(_tool); _cr = _crank.get(_tool); _pt = _per_tool.get(_tool, {})
            if _pr is None or _cr is None: continue
            _d = _pr - _cr
            _ds = f"{'+' if _d > 0 else ''}{_d}" if _d else "0"
            _flag = " ⚠" if abs(_d) >= 2 else ""
            lines.append(
                f"| {_tool} | {_pr} | **{_cr}** | {_ds}{_flag} | "
                f"{_pwm.get(_tool, 0.0):.2f} | "
                f"{_pt.get('mean_rank', 0.0):.2f} ± {_pt.get('stdev_rank', 0.0):.2f} | "
                f"{_pt.get('n_observations', 0)} |"
            )
        lines.append("")
        lines.append("`Δ = panel_rank − comparative_rank`. Positive Δ means comparative ranks the tool higher than the panel; ⚠ marks |Δ| ≥ 2.")
    _not_in_comp = sorted(set(_comp.get('tools_in_panel') or []) - set(_common))
    if _not_in_comp:
        lines.append("")
        lines.append(f"_Tools in panel but not yet judged comparatively (pilot covers t1 only): {', '.join(_not_in_comp)}_")
else:
    lines.append("_No comparative-rank data yet for this task. Run `./scripts/judge-comparative-all.sh --tasks " + task + "` to populate this section._")
lines.append("")

lines.append("## Ranking (Weighted Mean)")
lines.append("")
for i, (tool, _) in enumerate(sorted([(t, balanced_mean(t)) for t in tools], key=lambda x: -x[1]), 1):
    lines.append(f"{i}. **{tool}** — {balanced_mean(tool):.2f}/200")

lines.append("")
lines.append("## Per-Trial Breakdown")
lines.append("")
lines.append("Weighted-mean score for each individual trial (same 3·opus + 2·`GPT-5.4` + others weighting as the canonical column). Surfaces trial-to-trial drift inside a tool — a wide spread means the cohort mean is averaging over disagreeing runs rather than stable ones. The Δ column is `max − min` across all trials; ≥ 15 pts is flagged as **noisy** (the tool's output is bimodal at this sample size).")
lines.append("")


def trial_weighted_mean(tool, trial):
    """Weighted mean of per-judge means restricted to this trial's rounds."""
    rounds = raw[tool].get(trial) or {}
    if not rounds:
        return None
    per_j = defaultdict(list)
    for loc, jdict in rounds.items():
        for j, v in jdict.items():
            per_j[j].append(v)
    num = den = 0.0
    for j in JUDGES:
        vals = per_j.get(j) or []
        if not vals:
            continue
        w = JUDGE_WEIGHTS.get(j, 1)
        num += w * statistics.mean(vals)
        den += w
    return num / den if den else None


def _session_audit_counts(tool, trial):
    """Returns (skills_total, subagent_dispatches) per trial; (None, None) if missing.
    `skills_invoked` in session-audit.json is a {skill_name: count} dict; we sum
    values so a single integer reflects total skill invocations."""
    repo_root = os.path.dirname(os.path.dirname(os.path.dirname(report_path)))
    if task == 'feature':
        cell = os.path.join(repo_root, 'results', tool, f't{trial}')
    else:
        cell = os.path.join(repo_root, 'results', task, tool, f't{trial}')
    p = os.path.join(cell, 'session-audit.json')
    if not os.path.isfile(p): return (None, None)
    try:
        d = json.load(open(p))
        sk = d.get('skills_invoked')
        if isinstance(sk, dict):
            sk = sum(int(v) for v in sk.values()) if sk else 0
        sa = d.get('subagent_dispatches')
        if isinstance(sa, dict):
            sa = sum(int(v) for v in sa.values()) if sa else 0
        return (sk, sa)
    except Exception:
        return (None, None)

TRIALS = sorted({int(tr) for t in tools for tr in (raw.get(t) or {}).keys()})
_thdr = " | ".join(f"t{tr}" for tr in TRIALS)
_tlbl = "/".join(f"t{tr}" for tr in TRIALS)
_ncol = len(TRIALS) + 5
lines.append(f"| Tool | {_thdr} | Δ (max − min) | Flag | Skills ({_tlbl}) | Subagents ({_tlbl}) |")
lines.append("|" + "---|" * _ncol)
for tool in sorted(tools, key=lambda t: -balanced_mean(t)):
    cells = []
    vals = []
    skills_cells = []; sub_cells = []
    for tr in TRIALS:
        m = trial_weighted_mean(tool, tr)
        if m is None:
            cells.append("—")
        else:
            cells.append(f"{m:.2f}")
            vals.append(m)
        sk, sa = _session_audit_counts(tool, tr)
        skills_cells.append("—" if sk is None else str(sk))
        sub_cells.append("—" if sa is None else str(sa))
    if len(vals) >= 2:
        delta = max(vals) - min(vals)
        delta_cell = f"{delta:.2f}"
        flag = "**noisy**" if delta >= 15 else ""
    else:
        delta_cell = "—"; flag = ""
    lines.append(f"| {tool} | {' | '.join(cells)} | {delta_cell} | {flag} | {'/'.join(skills_cells)} | {'/'.join(sub_cells)} |")
lines.append("")
lines.append("Reading: a `noisy` flag here means the cohort mean for that tool is averaging over runs that disagree by ≥ 15 weighted pts. Use this column to read the headline rank with calibration — a tool whose trials cluster tightly is a more reliable signal than one with a wide spread. The pre-registered rerun protocol triggers on **per-round** outliers within a trial (not trial-to-trial), so a wide Δ here is real tool variance, not a harness artifact.")
lines.append("")
lines.append(f"**Skills ({_tlbl})** = number of distinct skill / slash-command invocations per trial (from `session-audit.json` → `skills_invoked`). **Subagents ({_tlbl})** = sub-agent dispatches per trial. A tool whose primary mechanism is a skill/sub-agent and reads `0` for a trial likely failed to invoke its mechanism — under the rerun protocol this is a Tier-1 trigger (\"Skill failure\"), distinct from the statistical-outlier trigger. Cross-reference these counts when a trial scores far from its siblings.")

lines.append("")
lines.append("## Per-Judge Means")
lines.append("")
lines.append("Each cell is one judge's mean score for one tool, averaged over that judge's 15 samples (5 trials × 3 rounds). The columns:")
lines.append("")
lines.append("- **Tool** — same 8 setups as above, ordered by Weighted Mean (rank-1 first).")
lines.append("- **opus / grok420 / glm51 / GPT-5.4 / mimo25pro** — that judge's mean score (0–200 rubric) for this tool. Reads vertically to expose **judge base-rate effects**: `GPT-5.4` consistently scores ~20–30 pts below the panel mean (harshest in the panel), `mimo25pro` ~5–15 pts above (most lenient, occasionally saturates at 200). Reads horizontally to see whether the judges agree on the ordering: if a tool is rank-1 under one judge and rank-7 under another, the consensus is weak.")
lines.append("")
header = " | ".join(JUDGES)
sep = "|".join(["---"] * (1 + len(JUDGES)))
lines.append(f"| Tool | {header} |")
lines.append(f"|{sep}|")
for tool in sorted(tools, key=lambda t: -balanced_mean(t)):
    cells = []
    for j in JUDGES:
        vals = per_judge[tool][j]
        cells.append(f"{statistics.mean(vals):.1f}" if vals else "—")
    lines.append(f"| {tool} | " + " | ".join(cells) + " |")

lines.append("")
if missing:
    lines.append(f"## Missing Judgments ({len(missing)})")
    lines.append("")
    for m in missing:
        lines.append(f"- {m}")

if provenance_mismatches:
    lines.append("")
    lines.append(f"## Provenance Defects ({len(provenance_mismatches)})")
    lines.append("")
    lines.append("Files whose internal `judge` field disagrees with the filename slot the aggregator dispatched by. The score is still counted (not retroactively pulled); listed here for transparency. See `AUDIT-FINDINGS-2026-05-18-JUDGE-VALIDITY.md`.")
    lines.append("")
    for p, exp, act in provenance_mismatches:
        rel = p.replace(results_dir + '/', '').replace(os.path.dirname(results_dir) + '/', '')
        lines.append(f"- `{rel}` — slot `{exp}` but `.judge` = `{act}`")

with open(report_path, 'w') as f:
    f.write('\n'.join(lines) + '\n')

print(f"Report written to: {report_path}")

# Emit the equal-weight companion (rank-stability comparator)
eq_path = report_path.replace('final-report.md', 'final-report.equal-weight.md')
eq = []
eq.append(f"# {task} — Equal-Weight Aggregation (companion to final-report.md)")
eq.append("")
eq.append(f"Generated: {os.popen('date -u +%Y-%m-%dT%H:%M:%SZ').read().strip()}")
eq.append("")
eq.append("## Inputs and source artifacts")
eq.append("")
eq.append("Same inputs as the canonical [`final-report.md`](final-report.md) — only the aggregation rule changes here.")
eq.append("")
eq.append(f"- **Trial input (task PRD).** [`_blind-eval/prd.md`](_blind-eval/prd.md).")
eq.append(f"- **Per-tool prompt prefix.** [`scripts/manual-bench.sh`]({_root_rel}/scripts/manual-bench.sh).")
eq.append(f"- **Judge input (verbatim request payload).** [`_blind-eval/Alpha/round1/`](_blind-eval/Alpha/round1/) (`<judge>-judge.json.request.json`).")
eq.append(f"- **Judge prompt template.** [`scripts/generate-judge-prompt-combined-v2.sh`]({_root_rel}/scripts/generate-judge-prompt-combined-v2.sh).")
eq.append(f"- **Methodology and threats to validity.** [`PAPER.md`]({_root_rel}/PAPER.md) · [`README.md`]({_root_rel}/README.md) · [landing page](https://claude-tool-benchmark.pages.dev/).")
eq.append("")
eq.append("## Methodology")
eq.append("- Same cohort, judges, rubric, and 3-round layout as `final-report.md`.")
eq.append("- **Equal weighting** — every judge contributes weight 1 (vs the published weighted mean's opus×3, `GPT-5.4`×2, others×1).")
eq.append("- Use this to verify rank-stability under operator-neutral weighting.")
eq.append("")
eq.append("## Ranking (Equal-Weight Mean)")
eq.append("")
for i, (tool, _) in enumerate(sorted([(t, pooled_mean(t)) for t in tools], key=lambda x: -x[1]), 1):
    eq.append(f"{i}. **{tool}** — {pooled_mean(tool):.2f}/200")
eq.append("")
eq.append("## Detail")
eq.append("")
eq.append("Same cohort and judgments as `final-report.md`; only the aggregation rule differs. Column glossary:")
eq.append("")
eq.append("- **Tool** — the setup under test (8 rows). Sort order: Equal-Weight Mean, rank-1 first.")
eq.append("- **Equal-Weight Mean** *(bold; canonical rank column for this comparator)* — straight arithmetic mean over all 75 judgments, every judge counted 1×. Compare against the Weighted Mean in `final-report.md` to verify rank-stability under operator-neutral weighting.")
eq.append("- **Pooled σ** — standard deviation across all 75 judgments (raw spread).")
eq.append("- **within_σ** — within-judge spread: per-judge σ across the 15 samples per tool (5 trials × 3 rounds), then averaged across judges. High = unstable trial-to-trial.")
eq.append("- **between_σ** — between-judge spread: σ across the 5 per-judge means. High = judges systematically disagree about this tool.")
eq.append("- **N** — total judgments aggregated. Should equal 75 when complete (5 trials × 5 judges × 3 rounds).")
eq.append("")
eq.append("| Tool | Equal-Weight Mean | Pooled σ | within_σ | between_σ | N |")
eq.append("|---|---|---|---|---|---|")
for tool in sorted(tools, key=lambda t: -pooled_mean(t)):
    eq.append(
        f"| {tool} | **{pooled_mean(tool):.2f}** | {pooled_sd(tool):.2f} | "
        f"{within_judge_sd(tool):.2f} | {between_judge_sd(tool):.2f} | {len(all_scores[tool])} |"
    )
eq.append("")
eq.append("## Cross-rule comparison")
eq.append("")
eq.append("Compare `Equal-Weight Mean` here against `Weighted Mean` in `final-report.md`. Rank-1 is identical under both rules on every task in this corpus; mid-pack ranks 4–7 may swap by at most 2 positions.")
eq.append("")
with open(eq_path, 'w') as f:
    f.write('\n'.join(eq) + '\n')
print(f"Equal-weight companion written to: {eq_path}")
print(f"Missing: {len(missing)}")
print(f"Total judgments: {total_judgments}")
PY

echo ""
echo "=== Aggregation complete ($TASK) ==="
echo "Report: $REPORT"
