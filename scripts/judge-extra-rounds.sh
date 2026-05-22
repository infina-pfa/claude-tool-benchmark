#!/bin/bash
# Run additional judging rounds across all tasks/labels.
#
# Usage:
#   ./judge-extra-rounds.sh                 # rounds 1 2 for all 3 tasks
#   ROUNDS="1 2" TASKS="feature bugfix refactor" ./judge-extra-rounds.sh
#   ROUNDS="1"   TASKS="refactor"             ./judge-extra-rounds.sh
#
# Each (task, round) invocation calls judge-all.sh --missing-only, so a
# resumed run skips (label, judge) pairs whose JSON already exists in the
# target round subdir. Per-round artifacts land in
#   results/[<task>/]_blind-eval/<Label>/round<N>/<judge>-judge.json
# and are picked up by aggregate-results.sh's `^round[0-9]+$` filter.
#
# Per-label R1 mechanical-fact override is applied by judge-all.sh after
# each label completes (recursively via rglob), so new round files inherit
# the same locked items.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
BENCH_HOME=$(cd "$SCRIPT_DIR/.." && pwd)
TASKS=${TASKS:-"feature bugfix refactor"}
ROUNDS=${ROUNDS:-"1 2"}

# Optional judge whitelist. JUDGES="opus grok420 glm51 mimo25pro" restricts
# the panel (e.g. to exclude a rate-limited provider temporarily); a later
# --missing-only pass with JUDGES="gpt54pro" backfills the excluded one.
# Empty (default) = full ALL_JUDGES panel from judge-all.sh.
JUDGE_ARGS=()
for j in ${JUDGES:-}; do
  JUDGE_ARGS+=(--judge "$j")
done

LOG_DIR="$BENCH_HOME/results/_logs"
mkdir -p "$LOG_DIR"
TS=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$LOG_DIR/extra-rounds-${TS}.log"

echo "=== judge-extra-rounds.sh ==="           | tee -a "$LOG_FILE"
echo "Tasks:  $TASKS"                          | tee -a "$LOG_FILE"
echo "Rounds: $ROUNDS"                         | tee -a "$LOG_FILE"
echo "Log:    $LOG_FILE"                       | tee -a "$LOG_FILE"
echo "Start:  $(date)"                         | tee -a "$LOG_FILE"
echo ""                                        | tee -a "$LOG_FILE"

for task in $TASKS; do
  for round in $ROUNDS; do
    echo "===== TASK=$task ROUND=$round =====" | tee -a "$LOG_FILE"
    echo "Begin: $(date)"                      | tee -a "$LOG_FILE"
    TASK="$task" ROUND="$round" \
      "$SCRIPT_DIR/judge-all.sh" --missing-only ${JUDGE_ARGS[@]+"${JUDGE_ARGS[@]}"} 2>&1 | tee -a "$LOG_FILE"
    echo "End:   $(date)"                      | tee -a "$LOG_FILE"
    echo ""                                    | tee -a "$LOG_FILE"
  done
done

echo "=== All requested (task, round) pairs finished ===" | tee -a "$LOG_FILE"
echo "End: $(date)"                                       | tee -a "$LOG_FILE"
