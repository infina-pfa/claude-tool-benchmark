#!/bin/bash
# Comparative-rank evaluation: bundle all 8 tools' artifacts for ONE (task, trial)
# into a single ranking prompt for an Opus-1M judge. Run once per round per (task, trial).
#
# Layout produced (kept strictly OUT of _blind-eval/ so existing aggregation is untouched):
#   results/_comparative-eval/<task>/<trial>/round<N>/
#     ├── .mapping-DO-NOT-OPEN.json    (R<N>-Greek label -> {tool, trial})
#     ├── prompt.md                     (full ranking prompt — paste-runnable)
#     └── (judge output will land as opus1m-ranking.json after judge-opus1m-comparative.sh)
#
# Fresh per-round labels (R1-Alpha…, R2-Alpha…, R3-Alpha…) — never collide with NATO.
# Both label-assignment AND artifact-order in the prompt are randomly shuffled per round.
#
# Usage:
#   TASK=feature ./scripts/comparative-eval-setup.sh <trial> <round>
#   TASK=bugfix  ./scripts/comparative-eval-setup.sh 1 1
set -uo pipefail
source "$(dirname "$0")/env.sh"

TRIAL=${1:-}
ROUND=${2:-}
if [ -z "$TRIAL" ] || [ -z "$ROUND" ]; then
  echo "Usage: TASK=<task> $0 <trial> <round>" >&2
  echo "  trial: 1..5    round: 1..3" >&2
  exit 1
fi

BLIND_DIR="$RESULTS_DIR/_blind-eval"
BLIND_MAP="$BLIND_DIR/.mapping-DO-NOT-OPEN.json"
if [ ! -f "$BLIND_MAP" ]; then
  echo "Blind-eval mapping not found: $BLIND_MAP — run blind-eval-setup.sh first" >&2
  exit 1
fi

COMP_DIR="$RESULTS_DIR/_comparative-eval/t${TRIAL}/round${ROUND}"
mkdir -p "$COMP_DIR"
COMP_MAP="$COMP_DIR/.mapping-DO-NOT-OPEN.json"
PROMPT_FILE="$COMP_DIR/prompt.md"
PRD_FILE="$BLIND_DIR/prd.md"

# Idempotency guard: if mapping + prompt already exist, the round is already set up
# (and may have been judged against this exact mapping). Re-running setup would
# re-shuffle the seed and silently mis-attribute any pre-existing ranking JSON.
# Force a regenerate by deleting the mapping file first.
if [ -s "$COMP_MAP" ] && [ -s "$PROMPT_FILE" ]; then
  echo "=== Comparative-eval setup: SKIP (already exists) ==="
  echo "Task=$TASK  Trial=t$TRIAL  Round=$ROUND  Dir=$COMP_DIR"
  echo "To force regenerate (will invalidate any prior ranking JSON): rm $COMP_MAP $PROMPT_FILE"
  exit 0
fi

if [ ! -f "$PRD_FILE" ]; then
  echo "PRD not found: $PRD_FILE" >&2
  exit 1
fi

# Build mapping: 8 tools' artifacts for this trial -> fresh R<round>-Greek labels.
# Greek alphabet (lower-cased prefix avoids any visual collision with NATO).
GREEK=(Alpha Beta Gamma Delta Epsilon Zeta Eta Theta)
python3 - "$BLIND_MAP" "$TRIAL" "$ROUND" "$COMP_MAP" "${GREEK[*]}" <<'PY'
import json, sys, random, hashlib, time
from datetime import datetime, timezone

blind_map_p, trial, round_n, out_p, greek_str = sys.argv[1:6]
trial = int(trial); round_n = int(round_n)
greek = greek_str.split()

blind = json.load(open(blind_map_p))['mapping']
# Pick the NATO labels for this trial — one per tool
trial_entries = []
for nato, info in blind.items():
    if info['trial'] == trial:
        trial_entries.append({'nato': nato, 'tool': info['tool'], 'trial': trial})

if not trial_entries:
    print(f"ERROR: no artifacts found for trial {trial} in blind mapping", file=sys.stderr)
    sys.exit(1)

if len(trial_entries) != len(greek):
    print(f"ERROR: expected {len(greek)} artifacts for trial t{trial}, got {len(trial_entries)}", file=sys.stderr)
    sys.exit(1)

# Seed = deterministic-per-(trial, round, wall-clock-day) so reruns can reproduce same shuffle if needed
seed_str = f"t{trial}|r{round_n}|{datetime.now(timezone.utc).strftime('%Y-%m-%d')}|{time.time_ns()}"
seed_hash = hashlib.sha256(seed_str.encode()).hexdigest()
rng = random.Random(int(seed_hash[:16], 16))

# Shuffle in place (both label assignment AND prompt position — single shuffle achieves both
# since prompt order will follow label order R1-Alpha, R1-Beta, ...)
shuffled = trial_entries[:]
rng.shuffle(shuffled)

mapping = {}
for i, entry in enumerate(shuffled):
    label = f"R{round_n}-{greek[i]}"
    mapping[label] = {
        'tool': entry['tool'],
        'trial': entry['trial'],
        'source_nato': entry['nato'],  # provenance: which NATO blind-label these bytes came from
    }

out = {
    'generated_at': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'trial': trial,
    'round': round_n,
    'seed': seed_hash[:16],
    'mapping': mapping,
}
json.dump(out, open(out_p, 'w'), indent=2)
print(f"  Mapping written: {out_p}")
for lbl, info in mapping.items():
    print(f"    {lbl}  <-  {info['source_nato']}  ({info['tool']}-t{info['trial']})")
PY

# Build the ranking prompt. Bundle: PRD + 8 artifacts (each with auto-metrics + plan + diff)
# in the order the mapping assigned (R<N>-Alpha first, …, R<N>-Theta last).
python3 - "$COMP_MAP" "$BLIND_DIR" "$PRD_FILE" "$PROMPT_FILE" "$TASK" "$TRIAL" "$ROUND" <<'PY'
import json, sys, os
from datetime import datetime, timezone

map_p, blind_dir, prd_p, out_p, task, trial, round_n = sys.argv[1:8]
mapping = json.load(open(map_p))['mapping']
prd = open(prd_p).read()

artifacts_in_order = sorted(mapping.items(), key=lambda kv: kv[0])  # R<N>-Alpha, R<N>-Beta, ...

lines = []
lines.append(f"# Comparative ranking — task={task}  trial=t{trial}  round={round_n}")
lines.append("")
lines.append("## Your role")
lines.append("")
lines.append("You are a senior code reviewer asked to **rank 8 anonymous implementations** of the same task, from best (rank 1) to worst (rank 8). Each implementation is one tool's output; identities are hidden behind fresh Greek-suffix labels (`R" + str(round_n) + "-Alpha` … `R" + str(round_n) + "-Theta`).")
lines.append("")
lines.append("**This is a comparative judgment, not absolute scoring.** Use the 20-item rubric below as your *evaluation lens*, but produce ONLY a ranking — do not emit per-item scores. Reasoning must be defensible: each rank position needs a short rationale grounded in concrete observations from the diffs.")
lines.append("")
lines.append("## Inputs")
lines.append("")
lines.append("Below you have:")
lines.append("1. The **PRD** every implementation was working against (identical input across all 8).")
lines.append("2. **8 implementations**, each consisting of: `auto-metrics.json` (deterministic mechanical metrics — tsc/eslint/tests/lines) and `implementation-diff.patch` (the actual code change).")
lines.append("")
lines.append("Plans are intentionally NOT included — they were leaking tool identity through formatting vocabulary in early rounds. The implementation diff plus the deterministic metrics are sufficient signal for the rubric.")
lines.append("")
lines.append("Compare them side-by-side. Use the comparative context to calibrate — you can now see what the *range* of solutions looks like for this task, which you couldn't when scoring individual artifacts in isolation.")
lines.append("")
lines.append("## Rubric (evaluation lens — do NOT emit per-item scores)")
lines.append("")
lines.append("Items 1-11 are qualitative; items 12, 13, 16, 20 are deterministic (already computed in auto-metrics.json). Use the rubric to *organize your comparative reasoning*, not to produce a number.")
lines.append("")
lines.append("- **Correctness & spec coverage** (1-5): Does the implementation satisfy the PRD's stated requirements?")
lines.append("- **Edge cases & robustness** (6-8): How are boundary conditions, errors, and unusual inputs handled?")
lines.append("- **Code quality & idiom fit** (9-11, 14, 15, 17): Naming, structure, error handling, idiom alignment with the existing codebase.")
lines.append("- **Mechanical health** (12 tsc=0, 13 eslint=0, 16 tests pass, 20 minimal-lines): mostly deterministic from auto-metrics.")
lines.append("- **Backward compatibility** (18, 19): No unintended schema/API breakage.")
lines.append("")
lines.append("## PRD (identical for all 8)")
lines.append("")
lines.append("```")
lines.append(prd.rstrip())
lines.append("```")
lines.append("")
lines.append("## Implementations to rank")
lines.append("")

for label, info in artifacts_in_order:
    nato = info['source_nato']
    src_dir = os.path.join(blind_dir, nato)
    am_p = os.path.join(src_dir, 'auto-metrics.json')
    plan_p = os.path.join(src_dir, 'phase1-plan.md')
    impl_p = os.path.join(src_dir, 'implementation-diff.patch')

    lines.append(f"### Implementation `{label}`")
    lines.append("")

    # auto-metrics — relabel tool name to the comparative label so identity isn't leaked
    if os.path.isfile(am_p):
        am = json.load(open(am_p))
        am['tool'] = label  # was NATO label; relabel to comparative label
        lines.append("**Mechanical metrics** (`auto-metrics.json`):")
        lines.append("")
        lines.append("```json")
        lines.append(json.dumps(am, indent=2))
        lines.append("```")
        lines.append("")

    # Plans intentionally omitted — they leak tool identity via formatting vocabulary
    # (RALPLAN-DR / `mode: fast` frontmatter / "Implementation Units" templates).
    # See blinding_concerns dump from bugfix/t1/round1 pilot (2026-05-16).

    if os.path.isfile(impl_p) and os.path.getsize(impl_p) > 0:
        lines.append("**Implementation diff** (`implementation-diff.patch`):")
        lines.append("")
        lines.append("```diff")
        lines.append(open(impl_p).read().rstrip())
        lines.append("```")
        lines.append("")

    lines.append("---")
    lines.append("")

lines.append("## Output format")
lines.append("")
lines.append("Emit **exactly one JSON object** matching this schema. No prose before or after — start with `{` and end with `}`. Wrap in a fenced ```json block.")
lines.append("")
lines.append("```json")
lines.append(json.dumps({
    "ranking": [
        {"rank": 1, "label": f"R{round_n}-XXX", "rationale": "≤40 words: concrete observation grounded in the diff"}
        for _ in range(1)
    ] + ["…repeat for ranks 2-8 — all 8 labels must appear exactly once…"],
    "calibration_notes": "≤120 words: what distinguishes the top from the bottom overall? Patterns you noticed across the cohort?",
    "blinding_concerns": "Empty string if no leak. Otherwise: name any label you suspect you can identify (specific tool/setup) and what tipped you off. This is a HONESTY field — false negatives here invalidate the ranking."
}, indent=2))
lines.append("```")
lines.append("")
lines.append("**Rules:**")
lines.append(f"- All 8 labels (`R{round_n}-Alpha` … `R{round_n}-Theta`) must appear exactly once in the ranking, ranks 1-8.")
lines.append("- Ranks must be strictly 1-8 with no ties or skips.")
lines.append("- `blinding_concerns` must be filled honestly — if a tool's style is identifiable, say so.")

with open(out_p, 'w') as f:
    f.write('\n'.join(lines) + '\n')

print(f"  Prompt written: {out_p} ({os.path.getsize(out_p):,} bytes)")
print(f"  Bundle est. tokens: ~{os.path.getsize(out_p) // 3.5:,.0f} (chars/3.5)")
PY

echo ""
echo "=== Comparative-eval setup complete ==="
echo "Task=$TASK  Trial=t$TRIAL  Round=$ROUND"
echo "Output dir: $COMP_DIR"
echo ""
echo "Next: ./scripts/judge-opus1m-comparative.sh $TRIAL $ROUND"
echo "(or open $PROMPT_FILE and paste into a 1M-context Opus session manually)"
