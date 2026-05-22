#!/bin/bash
# Generates randomized execution order.
# Usage:
#   ./randomize-order.sh                 # trials 1 2 3 (legacy default)
#   ./randomize-order.sh 1 2 3 4         # explicit trial list
#   TASK=bugfix ./randomize-order.sh 1 2 3 4
# Writes to:
#   feature  -> $BENCH_HOME/execution-order.txt
#   other  -> $RESULTS_DIR/execution-order.txt (task-scoped)
source "$(dirname "$0")/env.sh"

TRIALS=("$@")
if [ $# -eq 0 ]; then
  TRIALS=(1 2 3)
fi

RUNS=()
for tool in "${TOOLS[@]}"; do
  for trial in "${TRIALS[@]}"; do
    RUNS+=("${tool}:t${trial}")
  done
done

SHUFFLED=($(gshuf -e "${RUNS[@]}" 2>/dev/null || shuf -e "${RUNS[@]}"))

N=${#SHUFFLED[@]}
NTOOLS=${#TOOLS[@]}
NTRIALS=${#TRIALS[@]}

echo "=== RANDOMIZED EXECUTION ORDER — TASK=$TASK ($N runs: $NTOOLS tools × $NTRIALS trials) ==="
for i in "${!SHUFFLED[@]}"; do
  IFS=':' read -r TOOL TRIAL <<< "${SHUFFLED[$i]}"
  echo "  Run #$((i+1)): $TOOL ($TRIAL)"
done

if [ "$TASK" = "feature" ]; then
  OUT="$BENCH_HOME/execution-order.txt"
else
  mkdir -p "$RESULTS_DIR"
  OUT="$RESULTS_DIR/execution-order.txt"
fi

cat > "$OUT" << EOF
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# TASK=$TASK — $NTOOLS tools × $NTRIALS trials = $N runs, fully randomized
# Follow this order exactly. Do NOT re-randomize.
$(for i in "${!SHUFFLED[@]}"; do
  IFS=':' read -r TOOL TRIAL <<< "${SHUFFLED[$i]}"
  echo "$((i+1)). $TOOL $TRIAL"
done)
EOF

echo ""
echo "Order saved to $OUT"
echo "Follow this order. Do not re-shuffle."
