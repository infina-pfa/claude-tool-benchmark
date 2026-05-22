#!/bin/bash
# Verifies a clone is in clean state before a benchmark run
# Usage: ./verify-clean.sh <tool> <trial>
source "$(dirname "$0")/env.sh"

TOOL=$1; TRIAL=$2
if [ -z "$TOOL" ] || [ -z "$TRIAL" ]; then
  echo "Usage: ./verify-clean.sh <tool> <trial>"
  exit 1
fi

DIR="$RUNS_DIR/${TOOL}-t${TRIAL}"
echo "=== Pre-run verification: $TOOL t$TRIAL ==="

# 1. Dir exists
if [ ! -d "$DIR" ]; then
  echo "FAIL: $DIR does not exist. Run create-clones.sh first."
  exit 1
fi

# 2. Correct commit — verify HEAD is at (or descends from) a known baseline.
# Accepts both old full-history clones (BENCH_COMMIT) and new base-repo clones
# (squashed single commit). The key check is that the PRD submodule is present.
COMMIT=$(git -C "$DIR" log --oneline -1)
EXPECTED=$(echo "$BENCH_COMMIT" | cut -c1-9)
BASE_COMMIT=$(git -C "$DIR" log --format='%H %s' | awk '/ (chore:|base:)/ {print $1; exit}')
HEAD_SHA=$(git -C "$DIR" rev-parse HEAD)
if [ "$HEAD_SHA" != "$BASE_COMMIT" ] && [[ "$COMMIT" != "$EXPECTED"* ]]; then
  echo "WARNING: Not at base commit. Current: $COMMIT"
fi
echo "Commit: $COMMIT"

# 3. Clean state
STATUS=$(git -C "$DIR" status --porcelain)
if [ -n "$STATUS" ]; then
  echo "FAIL: Clone is dirty!"
  echo "$STATUS" | head -10
  echo ""
  echo "Fix: cd $DIR && git checkout -- . && git clean -fd"
  exit 1
fi
echo "State: clean"

# 4. PRD exists
if [ -f "$DIR/$PRD_PATH" ]; then
  LINES=$(wc -l < "$DIR/$PRD_PATH")
  echo "PRD: present ($LINES lines)"
else
  echo "FAIL: PRD not found"
  exit 1
fi

# 5. node_modules
if [ -d "$DIR/node_modules" ]; then
  echo "node_modules: present"
else
  echo "WARNING: node_modules missing — run: cd $DIR && yarn install --frozen-lockfile"
fi

# 6. Config dir
if [ -d "$CONFIG_DIR/${TOOL}-t${TRIAL}" ]; then
  echo "Config dir: present"
else
  echo "WARNING: Config dir missing — run: mkdir -p $CONFIG_DIR/${TOOL}-t${TRIAL}"
fi

echo "=== PASSED ==="
