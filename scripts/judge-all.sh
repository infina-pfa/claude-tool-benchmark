#!/bin/bash
# Runs judges for given labels (Phase 1+2 combined review).
#
# Concurrency model: per-label barrier (the original).
#   - Inside one label, all 5 judges run in parallel.
#   - The script waits for every judge of that label to finish before moving
#     to the next label, then applies R1 mechanical-fact override across all
#     newly-written judge files for that label.
#   - This naturally rate-limits the fast judges (they idle while waiting on
#     the slow ones), which avoided upstream rate-limit failures observed
#     in the prior independent-lane variant.
#
# Usage:
#   ./judge-all.sh                        # All judges, all labels
#   ./judge-all.sh Alpha                  # All judges, single label
#   ./judge-all.sh Alpha Bravo            # All judges, specific labels
#   ./judge-all.sh --judge sonnet Alpha   # Single judge, specific labels
#   ./judge-all.sh --judge sonnet         # Single judge, all labels
#   ./judge-all.sh --missing-only         # Skip (label, judge) pairs already done
set -uo pipefail
source "$(dirname "$0")/env.sh"

# Read labels dynamically from the mapping file
EVAL_DIR="$RESULTS_DIR/_blind-eval"
MAPPING_FILE="$EVAL_DIR/.mapping-DO-NOT-OPEN.json"
if [ ! -f "$MAPPING_FILE" ]; then
  echo "Mapping file not found. Run blind-eval-setup.sh first." >&2
  exit 1
fi
ALL_LABELS=($(python3 -c "import json; m=json.load(open('$MAPPING_FILE'))['mapping']; print(' '.join(m.keys()))"))
# v2 panel (locked 2026-04-25 after 8-judge × 3-label cross-validation; see docs/v2-plan.md §3b).
# Mean σ across {Alpha, Bravo, Uniform} under v2 prompt:
#   glm51 2.64 · grok420 2.97 · gpt54pro 3.37 · mimo25pro 5.51 · opus 12.17
# 5 vendors: Anthropic / xAI / Z.ai / OpenAI / Xiaomi.
ALL_JUDGES=(opus grok420 glm51 gpt54pro mimo25pro)
# gpt54pro promoted to active panel 2026-05-07 after Uniform 3-round stability
# test (σ=5.13, best of all candidates; mean=95.7, harshest scorer). 5 vendors:
# Anthropic / xAI / Z.ai / OpenAI / Xiaomi.
SCRIPTS_DIR=$(dirname "$0")
# v2 prompt (mechanical-fact pre-block + N/A defaults + per-item rationales) is the default.
# Override with PROMPT_SCRIPT=generate-judge-prompt-combined.sh for the v1 form.
export PROMPT_SCRIPT=${PROMPT_SCRIPT:-generate-judge-prompt-combined-v2.sh}

# Parse flags. `--missing-only` skips (label, judge) pairs whose JSON already
# exists and is non-empty — turns judge-all.sh into a resume primitive without
# re-billing successful runs. Combine with `--judge <name>` to retry a single
# provider after a credit / outage incident.
JUDGES=()
LABELS=()
MISSING_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --judge)
      shift
      JUDGES+=("$1")
      shift
      ;;
    --missing-only)
      MISSING_ONLY=1
      shift
      ;;
    *)
      LABELS+=("$1")
      shift
      ;;
  esac
done

[ ${#JUDGES[@]} -eq 0 ] && JUDGES=("${ALL_JUDGES[@]}")
[ ${#LABELS[@]} -eq 0 ] && LABELS=("${ALL_LABELS[@]}")

TOTAL=$(( ${#LABELS[@]} * ${#JUDGES[@]} ))
DONE=0

echo "=== Starting $TOTAL evaluations (${#JUDGES[@]} judges × ${#LABELS[@]} labels, combined 2-phase review) ==="
echo "=== Judges: ${JUDGES[*]} ==="
echo "=== Start: $(date) ==="
echo ""

for label in "${LABELS[@]}"; do
  echo "--- $label (${#JUDGES[@]} judges in parallel) ---"

  # Save the prompt template (pre JUDGE_NAME substitution) for research reproducibility.
  # All judges receive an identical prompt except for the JUDGE_NAME field.
  mkdir -p "$EVAL_DIR/$label"
  "$SCRIPTS_DIR/$PROMPT_SCRIPT" "$label" > "$EVAL_DIR/$label/judge-prompt.md" 2>/dev/null

  # --missing-only must honor ROUND so multi-round reruns can resume without
  # double-billing. Root files exist for the canonical run; round subdirs are
  # the per-round artifact path the wrappers write to when ROUND is set.
  if [ -n "${ROUND:-}" ]; then
    CHECK_DIR="$EVAL_DIR/$label/round${ROUND}"
  else
    CHECK_DIR="$EVAL_DIR/$label"
  fi

  PIDS=()
  for judge in "${JUDGES[@]}"; do
    if [ "$MISSING_ONLY" = "1" ] && [ -s "$CHECK_DIR/${judge}-judge.json" ]; then
      echo "$judge $label: skip (already present)"
      continue
    fi
    "$SCRIPTS_DIR/judge-${judge}.sh" "$label" &
    PIDS+=($!)
  done

  if [ ${#PIDS[@]} -gt 0 ]; then
    wait "${PIDS[@]}"
  fi

  # R1 mechanical-fact override (v2-plan §3c R1 + §3.5.2): after all judges
  # for the label have written their JSONs, deterministically rewrite the
  # task's locked items from auto-metrics.json. Per-task item IDs:
  #   feature  12 tsc / 13 eslint / 16 Mode 1 tests / 20 back-compat
  #   bugfix   14 tsc / 15 eslint
  #   refactor 13 savings-cd tests / 14 core tests
  python3 "$SCRIPTS_DIR/apply-r1-override.py" "$EVAL_DIR/$label" 2>&1 \
    | grep -E '→[0-9]|no override' | sed 's/^/  R1: /' || true

  DONE=$((DONE + ${#JUDGES[@]}))
  echo "    Progress: $DONE/$TOTAL"
  echo ""
done

echo "=== All $TOTAL evaluations complete ==="
echo "=== End: $(date) ==="
