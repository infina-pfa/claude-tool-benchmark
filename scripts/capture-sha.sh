#!/bin/bash
# Captures current HEAD SHA after a phase commit
# Usage: ./capture-sha.sh <tool> <trial>
source "$(dirname "$0")/env.sh"

TOOL=$1; TRIAL=$2
if [ -z "$TOOL" ] || [ -z "$TRIAL" ]; then
  echo "Usage: ./capture-sha.sh <tool> <trial>"
  exit 1
fi

CLONE_DIR="$RUNS_DIR/${TOOL}-t${TRIAL}"
RESULT_DIR="$RESULTS_DIR/$TOOL/t${TRIAL}"
mkdir -p "$RESULT_DIR"

# On first call, seed commits.txt with the last setup commit (chore:) as the
# BASE so that phase1..phase2 diffs aren't empty for single-shot trials.
if [ ! -s "$RESULT_DIR/commits.txt" ]; then
  BASE=$(git -C "$CLONE_DIR" log --format='%H %s' | awk '/ (chore:|base:)/ {print $1; exit}')
  if [ -n "$BASE" ]; then
    echo "$BASE" > "$RESULT_DIR/commits.txt"
    echo "Seeded BASE: $BASE"
  fi
fi

SHA=$(git -C "$CLONE_DIR" rev-parse HEAD)
echo "$SHA" >> "$RESULT_DIR/commits.txt"

COUNT=$(wc -l < "$RESULT_DIR/commits.txt" | tr -d ' ')
echo "Captured SHA #$COUNT: $SHA"
echo "  (phase-1=$( sed -n '1p' "$RESULT_DIR/commits.txt" 2>/dev/null || echo 'pending' ))"
echo "  (phase-2=$( sed -n '2p' "$RESULT_DIR/commits.txt" 2>/dev/null || echo 'pending' ))"
echo "SHA captured"
