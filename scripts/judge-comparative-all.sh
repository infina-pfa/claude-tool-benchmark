#!/bin/bash
# Orchestrator for comparative-rank Opus-1M judge across (task, trial, round) cells.
# Setup + judge in one go; skips cells whose ranking JSON already exists (resume-safe).
#
# Usage:
#   ./scripts/judge-comparative-all.sh                       # pilot: 3 tasks × t1 × 3 rounds
#   ./scripts/judge-comparative-all.sh --trials 1,2,3        # specific trials
#   ./scripts/judge-comparative-all.sh --tasks bugfix        # specific tasks
#   ./scripts/judge-comparative-all.sh --rounds 3            # round count (default 3)
#   ./scripts/judge-comparative-all.sh --concurrent 3        # max parallel calls (default 3)
#   ./scripts/judge-comparative-all.sh --force               # re-run even if output exists
set -uo pipefail
cd "$(dirname "$0")/.."

TASKS="feature,bugfix,refactor"
TRIALS="1"
ROUNDS=3
CONCURRENT=3
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --tasks) TASKS="$2"; shift 2 ;;
    --trials) TRIALS="$2"; shift 2 ;;
    --rounds) ROUNDS="$2"; shift 2 ;;
    --concurrent) CONCURRENT="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

IFS=',' read -r -a TASKS_A <<< "$TASKS"
IFS=',' read -r -a TRIALS_A <<< "$TRIALS"

# Phase 1: setup all prompts sequentially (cheap, no API calls)
echo "=== Phase 1: prompt setup ==="
for task in "${TASKS_A[@]}"; do
  for trial in "${TRIALS_A[@]}"; do
    for round in $(seq 1 "$ROUNDS"); do
      TASK="$task" ./scripts/comparative-eval-setup.sh "$trial" "$round" >/dev/null
      echo "  setup ok: $task t$trial round$round"
    done
  done
done
echo ""

# Phase 2: collect cells needing judging
declare -a CELLS
for task in "${TASKS_A[@]}"; do
  if [ "$task" = "feature" ]; then results_dir="results"; else results_dir="results/$task"; fi
  for trial in "${TRIALS_A[@]}"; do
    for round in $(seq 1 "$ROUNDS"); do
      out="$results_dir/_comparative-eval/t${trial}/round${round}/opus1m-ranking.json"
      if [ "$FORCE" = "1" ] || [ ! -s "$out" ]; then
        CELLS+=("$task|$trial|$round")
      else
        echo "  skip (exists): $task t$trial round$round"
      fi
    done
  done
done

TOTAL=${#CELLS[@]}
if [ "$TOTAL" = "0" ]; then
  echo "=== Nothing to do — all cells already judged. ==="
  exit 0
fi

echo ""
echo "=== Phase 2: judging $TOTAL cells (max $CONCURRENT concurrent) ==="
echo "    Start: $(date)"
echo ""

PIDS=""
DONE=0

run_one() {
  local task="$1" trial="$2" round="$3"
  local started=$(date +%s)
  TASK="$task" ./scripts/judge-opus1m-comparative.sh "$trial" "$round" >/dev/null 2>&1
  local rc=$?
  local elapsed=$(( $(date +%s) - started ))
  if [ "$rc" = "0" ]; then
    echo "  ✓ $task t$trial round$round (${elapsed}s)"
  else
    echo "  ✗ $task t$trial round$round (${elapsed}s) — exit $rc"
  fi
}

# Portable slot-refill (bash 3.2 compatible — `wait -n` is bash 4+ only).
# PIDS is a space-separated string of active background PIDs. reap_finished
# removes any whose process has exited and increments DONE.
reap_finished() {
  local new_pids="" pid
  for pid in $PIDS; do
    if kill -0 "$pid" 2>/dev/null; then
      new_pids="$new_pids $pid"
    else
      wait "$pid" 2>/dev/null || true
      DONE=$((DONE + 1))
    fi
  done
  PIDS="$new_pids"
}

active_count() {
  set -- $PIDS
  echo $#
}

for cell in "${CELLS[@]}"; do
  IFS='|' read -r task trial round <<< "$cell"
  while [ "$(active_count)" -ge "$CONCURRENT" ]; do
    reap_finished
    if [ "$(active_count)" -ge "$CONCURRENT" ]; then
      sleep 1
    fi
  done
  run_one "$task" "$trial" "$round" &
  PIDS="$PIDS $!"
done

# Drain remaining
while [ "$(active_count)" -gt 0 ]; do
  reap_finished
  if [ "$(active_count)" -gt 0 ]; then
    sleep 1
  fi
done

echo ""
echo "=== Phase 2 complete: $DONE/$TOTAL ==="
echo "    End: $(date)"
echo ""

# Phase 3: aggregate
echo "=== Phase 3: aggregate ==="
for task in "${TASKS_A[@]}"; do
  python3 scripts/aggregate-comparative.py --task "$task"
done
