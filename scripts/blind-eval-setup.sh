#!/bin/bash
# Anonymizes trial outputs for blind evaluation.
# Supports incremental tool addition — new tools get new labels
# without disturbing existing mappings or judge results.
#
# Usage:
#   ./blind-eval-setup.sh             # Add new tools incrementally, regenerate artifacts
#   ./blind-eval-setup.sh --reshuffle # Destroy existing mapping, start fresh
set -uo pipefail
source "$(dirname "$0")/env.sh"

EVAL_DIR="$RESULTS_DIR/_blind-eval"
MAPPING_FILE="$EVAL_DIR/.mapping-DO-NOT-OPEN.json"

# Full NATO alphabet + 14 extras — supports 8 tools × 5 trials = 40 labels (with buffer)
ALL_LABELS=(Alpha Bravo Charlie Delta Echo Foxtrot Golf Hotel India Juliet Kilo Lima Mike November Oscar Papa Quebec Romeo Sierra Tango Uniform Victor Whiskey Xray Yankee Zulu Anchor Beacon Cipher Drift Ember Flint Grove Helix Iron Jade Kingpin Lunar Maple Nova Onyx Polaris Quasar Ridge)

RESHUFFLE=false
if [[ "${1:-}" == "--reshuffle" ]]; then
  RESHUFFLE=true
fi

# Build all run IDs by scanning results dirs for commits.txt
RUNS=()
for tool in "${TOOLS[@]}"; do
  for trial_dir in "$RESULTS_DIR/$tool"/t*/; do
    [ -d "$trial_dir" ] || continue
    trial=$(basename "$trial_dir" | sed 's/^t//')
    if [ -f "$trial_dir/commits.txt" ]; then
      RUNS+=("${tool}:${trial}")
    fi
  done
done

if [ ${#RUNS[@]} -gt ${#ALL_LABELS[@]} ]; then
  echo "Too many runs (${#RUNS[@]}) for available labels (${#ALL_LABELS[@]})" >&2
  exit 1
fi

mkdir -p "$EVAL_DIR"

if [ "$RESHUFFLE" = true ] || [ ! -f "$MAPPING_FILE" ]; then
  # Generate brand new random mapping
  if command -v gshuf >/dev/null 2>&1; then
    SHUFFLED_LABELS=($(printf '%s\n' "${ALL_LABELS[@]:0:${#RUNS[@]}}" | gshuf))
  else
    SHUFFLED_LABELS=($(printf '%s\n' "${ALL_LABELS[@]:0:${#RUNS[@]}}" | sort -R))
  fi

  # Also shuffle runs so label assignment is random
  if command -v gshuf >/dev/null 2>&1; then
    SHUFFLED_RUNS=($(printf '%s\n' "${RUNS[@]}" | gshuf))
  else
    SHUFFLED_RUNS=($(printf '%s\n' "${RUNS[@]}" | sort -R))
  fi

  python3 - "$MAPPING_FILE" "${#SHUFFLED_RUNS[@]}" "${SHUFFLED_LABELS[*]}" "${SHUFFLED_RUNS[*]}" <<'PY'
import json, sys
from datetime import datetime, timezone
out_path = sys.argv[1]
count = int(sys.argv[2])
labels = sys.argv[3].split()
runs = sys.argv[4].split()
mapping = {}
for i in range(count):
    tool, trial = runs[i].split(':')
    mapping[labels[i]] = {"tool": tool, "trial": int(trial)}
json.dump({
    "generated_at": datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    "mapping": mapping
}, open(out_path, 'w'), indent=2)
PY
  echo "Generated NEW random mapping (${#RUNS[@]} runs)"
else
  # Incremental: load existing mapping, add only new runs
  python3 - "$MAPPING_FILE" "${RUNS[*]}" "${ALL_LABELS[*]}" <<'PY'
import json, sys
mapping_path = sys.argv[1]
all_runs = sys.argv[2].split()  # tool:trial pairs
all_labels = sys.argv[3].split()

with open(mapping_path) as f:
    data = json.load(f)
mapping = data.get('mapping', {})

# Find which runs are already mapped
existing_runs = set()
for info in mapping.values():
    existing_runs.add(f"{info['tool']}:{info['trial']}")

# Find new runs not yet in the mapping
new_runs = [r for r in all_runs if r not in existing_runs]

if not new_runs:
    print("All runs already mapped — no changes needed")
    sys.exit(0)

# Find unused labels
used_labels = set(mapping.keys())
available_labels = [l for l in all_labels if l not in used_labels]

if len(new_runs) > len(available_labels):
    print(f"Not enough labels: need {len(new_runs)}, have {len(available_labels)}", file=sys.stderr)
    sys.exit(1)

# Randomly assign labels to new runs
import random
random.shuffle(available_labels)
random.shuffle(new_runs)

for i, run in enumerate(new_runs):
    tool, trial = run.split(':')
    label = available_labels[i]
    mapping[label] = {"tool": tool, "trial": int(trial)}
    print(f"  NEW: {label} -> {tool}-t{trial}")

data['mapping'] = mapping
data['updated_at'] = __import__('datetime').datetime.now(
    __import__('datetime').timezone.utc
).strftime('%Y-%m-%dT%H:%M:%SZ')

with open(mapping_path, 'w') as f:
    json.dump(data, f, indent=2)

print(f"Added {len(new_runs)} new mappings (total: {len(mapping)})")
PY
  echo "Reusing existing mapping (incremental update if new tools found)"
fi

# Read mapping into parallel arrays
MAPPED_LABELS=()
MAPPED_TOOLS=()
MAPPED_TRIALS=()
while IFS= read -r line; do
  IFS='|' read -r l t n <<< "$line"
  MAPPED_LABELS+=("$l")
  MAPPED_TOOLS+=("$t")
  MAPPED_TRIALS+=("$n")
done < <(python3 -c "
import json
m = json.load(open('$MAPPING_FILE'))['mapping']
for k,v in m.items():
    print(f'{k}|{v[\"tool\"]}|{v[\"trial\"]}')
")

echo "=== Blind Evaluation Setup (${#MAPPED_LABELS[@]} runs) ==="
echo ""

for i in "${!MAPPED_LABELS[@]}"; do
  LABEL="${MAPPED_LABELS[$i]}"
  TOOL="${MAPPED_TOOLS[$i]}"
  TRIAL="${MAPPED_TRIALS[$i]}"
  TARGET="$EVAL_DIR/$LABEL"
  SOURCE="$RESULTS_DIR/$TOOL/t${TRIAL}"
  CLONE="$RUNS_DIR/${TOOL}-t${TRIAL}"

  # Clean only artifact files, preserve judge results and backups
  mkdir -p "$TARGET"
  rm -f "$TARGET/auto-metrics.json" "$TARGET/tsc-output.txt" "$TARGET/eslint-output.txt" \
       "$TARGET/test-output.txt" "$TARGET/diff-stats.txt" "$TARGET/phase1-plan.md" \
       "$TARGET/implementation-diff.patch" "$TARGET/testing-diff.patch" 2>/dev/null

  set +e
  (
    # No set -e: zsh glob failures and grep pipeline exits would kill the subshell

    # Copy auto-metrics, anonymize tool name. plugin_versions and collected_at
    # are 1:1 tool fingerprints (e.g. {"oh-my-claudecode": "..."} names omc
    # outright; collected_at correlates with cohort start logs) — strip them
    # before exposing the JSON in the blind dir.
    if [ -f "$SOURCE/auto-metrics.json" ]; then
      python3 -c "
import json
with open('$SOURCE/auto-metrics.json') as f:
    d = json.load(f)
d['tool'] = '$LABEL'
d.pop('trial', None)
d.pop('plugin_versions', None)
d.pop('collected_at', None)
with open('$TARGET/auto-metrics.json', 'w') as f:
    json.dump(d, f, indent=2)
"
    fi

    cp "$SOURCE/tsc-output.txt" "$TARGET/" 2>/dev/null || true
    cp "$SOURCE/eslint-output.txt" "$TARGET/" 2>/dev/null || true
    cp "$SOURCE/test-output.txt" "$TARGET/" 2>/dev/null || true
    cp "$SOURCE/diff-stats.txt" "$TARGET/" 2>/dev/null || true

    if [ -f "$SOURCE/commits.txt" ] && [ -d "$CLONE" ]; then
      PHASE1_SHA=$(sed -n '1p' "$SOURCE/commits.txt")
      PHASE2_SHA=$(sed -n '2p' "$SOURCE/commits.txt")
      PHASE3_SHA=$(sed -n '3p' "$SOURCE/commits.txt")

      cd "$CLONE"

      # Plan file resolution — use find to avoid zsh glob errors
      PLAN_FILE=""
      PLAN_EXTRACTED=false
      PLAN_FILE=$(find . \( \
        -path './_bmad-output/implementation-artifacts/spec-*mode*.md' -o \
        -path './_bmad-output/implementation-artifacts/spec-*.md' -o \
        -path './.omc/plans/*mode*.md' -o \
        -path './.omc/plans/*.md' -o \
        -path './docs/superpowers/specs/*mode*.md' -o \
        -path './docs/superpowers/plans/*mode*.md' -o \
        -path './docs/plans/*.md' -o \
        -path './plans/*.md' \
      \) -type f 2>/dev/null | head -1)

      # Multi-file plan detection (e.g. claudekit: plan.md + phase-*.md in same dir)
      if [ -n "$PLAN_FILE" ] && [ -f "$PLAN_FILE" ]; then
        PLAN_DIR=$(dirname "$PLAN_FILE")
        PHASE_FILES=$(find "$PLAN_DIR" -maxdepth 1 -name 'phase-*.md' -type f 2>/dev/null | sort -V)
        if [ -n "$PHASE_FILES" ]; then
          # Concatenate overview (plan.md) + all phase files in order
          {
            if [ -f "$PLAN_DIR/plan.md" ]; then
              cat "$PLAN_DIR/plan.md"
              echo ""
              echo "---"
              echo ""
            fi
            echo "$PHASE_FILES" | while read -r pf; do
              cat "$pf"
              echo ""
              echo "---"
              echo ""
            done
          } > "$TARGET/phase1-plan.md"
          PLAN_EXTRACTED=true
        fi
      fi

      # Single-file plan
      if [ "$PLAN_EXTRACTED" = false ] && [ -n "$PLAN_FILE" ] && [ -f "$PLAN_FILE" ]; then
        cp "$PLAN_FILE" "$TARGET/phase1-plan.md"
        PLAN_EXTRACTED=true
      fi

      # Fallback: find plan from git diff
      if [ "$PLAN_EXTRACTED" = false ] && [ -n "$PHASE1_SHA" ]; then
        BASE=$(git log --all --grep "pin product-docs" --format=%H | head -1)
        if [ -n "$BASE" ] && [ "$BASE" != "$PHASE1_SHA" ]; then
          PLAN_FILE=$(git diff --name-only "$BASE".."$PHASE1_SHA" 2>/dev/null | grep -E '\.md$' | grep -vE 'spec-wip|deferred-work' | head -1 || true)
          if [ -n "$PLAN_FILE" ] && [ -f "$PLAN_FILE" ]; then
            cp "$PLAN_FILE" "$TARGET/phase1-plan.md"
            PLAN_EXTRACTED=true
          fi
        fi
      fi

      # Fallback: extract plan from phase1-output.json result text
      if [ "$PLAN_EXTRACTED" = false ]; then
        if [ -f "$SOURCE/phase1-output.json" ]; then
          python3 -c "
import json
d = json.load(open('$SOURCE/phase1-output.json'))
result = d.get('result', '')
if result and len(result) > 200:
    with open('$TARGET/phase1-plan.md', 'w') as f:
        f.write(result)
" 2>/dev/null
        fi
      fi

      # Implementation diff = phase1..phase2.
      #
      # Path-level exclusions strip:
      # - *.md            : plan / spec docs that would leak phase-1 reasoning
      # - CLAUDE.md.original : claudekit setup script backs up the project's
      #                        CLAUDE.md before overwriting it; unique claudekit
      #                        fingerprint, breaks blind eval.
      # - tool state dirs : .omc/, _bmad/, _bmad-output/, docs/superpowers/,
      #                     plans/, .claudekit/, .gstack/  — these are tool-
      #                     specific scratch surfaces, never production code.
      #
      # Content-level scrub (sed pass below) normalises text-level references
      # inside source comments (e.g. `Audit reference: .omc/research/X.md`)
      # so the diff still compiles and is judgeable while not naming a tool.
      DIFF_EXCLUDES=(
        ':(exclude)*.md'
        ':(exclude)CLAUDE.md.original'
        ':(exclude).omc/**'
        ':(exclude)_bmad/**'
        ':(exclude)_bmad-output/**'
        ':(exclude)_bmad-core/**'
        ':(exclude)docs/bmad/**'
        ':(exclude)docs/superpowers/**'
        ':(exclude)plans/**'
        ':(exclude).claudekit/**'
        ':(exclude).gstack/**'
        ':(exclude).superpowers/**'
        ':(exclude).compound-engineering/**'
        ':(exclude).ecc/**'
      )

      # Content-level scrub: strip tool-state directory prefixes when they
      # appear inside diff body lines (`+`, `-`, or context). Path-header
      # lines (`diff --git`, `+++ b/`, `--- a/`, `index ...`, `@@ ... @@`)
      # are left intact — the path excludes above guarantee they never name a
      # tool dir. Substitutions are minimal: drop the leading tool prefix
      # so a phrase like `Audit reference: .omc/research/X.md` becomes
      # `Audit reference: research/X.md` rather than disappearing entirely.
      scrub_tool_fingerprints() {
        local f="$1"
        [ -f "$f" ] || return 0
        awk '
          /^(diff |index |\+\+\+ |--- |@@|similarity index |rename from |rename to |new file mode |deleted file mode |Binary files |\\ No newline)/ { print; next }
          {
            gsub(/\.omc\//, "")
            gsub(/_bmad-output\//, "")
            gsub(/_bmad-core\//, "")
            gsub(/_bmad\//, "")
            gsub(/docs\/bmad\//, "docs/")
            gsub(/docs\/superpowers\//, "docs/")
            gsub(/plans\//, "")
            gsub(/research\//, "")
            gsub(/\.claudekit\//, "")
            gsub(/\.gstack\//, "")
            gsub(/\.superpowers\//, "")
            gsub(/\.compound-engineering\//, "")
            gsub(/\.ecc\//, "")
            print
          }
        ' "$f" > "$f.scrub" && mv "$f.scrub" "$f"
      }

      if [ -n "$PHASE1_SHA" ] && [ -n "$PHASE2_SHA" ]; then
        git diff "$PHASE1_SHA".."$PHASE2_SHA" -- . "${DIFF_EXCLUDES[@]}" > "$TARGET/implementation-diff.patch" 2>/dev/null || true
        scrub_tool_fingerprints "$TARGET/implementation-diff.patch"
      fi

      if [ -n "$PHASE2_SHA" ] && [ -n "$PHASE3_SHA" ]; then
        git diff "$PHASE2_SHA".."$PHASE3_SHA" -- . "${DIFF_EXCLUDES[@]}" > "$TARGET/testing-diff.patch" 2>/dev/null || true
        scrub_tool_fingerprints "$TARGET/testing-diff.patch"
      fi
    fi
  )
  RC=$?
  set -e

  HAS_PLAN="-"; [ -s "$TARGET/phase1-plan.md" ] && HAS_PLAN="✓"
  HAS_IMPL="-"; [ -s "$TARGET/implementation-diff.patch" ] && HAS_IMPL="✓"
  HAS_TEST="-"; [ -s "$TARGET/testing-diff.patch" ] && HAS_TEST="✓"
  STATUS=""; [ "$RC" -ne 0 ] && STATUS=" (subshell rc=$RC)"
  printf "  %-8s [%s] plan=%s impl=%s test=%s%s\n" "$LABEL" "${TOOL}-t${TRIAL}" "$HAS_PLAN" "$HAS_IMPL" "$HAS_TEST" "$STATUS"
done

# Cohort freshness check — if any tool has trials whose latest session started_at
# span more than 24h, flag asymmetric reruns. Per CLAUDE.md rerun protocol, a
# single-trial rerun should be accompanied by same-trial-number reruns for all
# other tools, or explicitly acknowledged in the final report.
echo ""
echo "=== Cohort freshness check (24h threshold) ==="
python3 - "$RESULTS_DIR" <<'PY'
import json
from datetime import datetime, timezone
from pathlib import Path

results = Path(__import__('sys').argv[1])
warnings = 0
for tool_dir in sorted(results.iterdir()):
    if not tool_dir.is_dir() or tool_dir.name.startswith(('_','FINAL')) or tool_dir.name == 'archive':
        continue
    tool = tool_dir.name
    latest_per_trial = {}
    for trial_dir in sorted(tool_dir.glob('t*')):
        if not trial_dir.is_dir(): continue
        sess_dir = trial_dir / 'sessions'
        if not sess_dir.exists(): continue
        candidates = []
        for meta in sess_dir.glob('*.meta.json'):
            try:
                d = json.load(open(meta))
                ts = d.get('started_at')
                if ts:
                    candidates.append(datetime.fromisoformat(ts.replace('Z','+00:00')))
            except Exception:
                pass
        if candidates:
            latest_per_trial[trial_dir.name] = max(candidates)
    if len(latest_per_trial) < 2:
        continue
    tmin = min(latest_per_trial.values())
    tmax = max(latest_per_trial.values())
    gap_hours = (tmax - tmin).total_seconds() / 3600
    if gap_hours > 24:
        warnings += 1
        newest_trial = max(latest_per_trial, key=latest_per_trial.get)
        oldest_trial = min(latest_per_trial, key=latest_per_trial.get)
        print(f"  [WARN] {tool}: {gap_hours:.0f}h gap — {newest_trial} is fresher than {oldest_trial}")
        print(f"         Consider cohort-rerun for {tool} or acknowledge asymmetry in the report.")

if warnings == 0:
    print("  ok — all tools' trials were run within 24h of each other.")
PY

echo ""
echo "=== READY FOR BLIND EVALUATION ==="
echo "${#MAPPED_LABELS[@]} anonymized sets in: $EVAL_DIR/"
echo ""
echo "Next: ./scripts/judge-all.sh"
echo "DO NOT open .mapping-DO-NOT-OPEN.json until all judging is complete."
