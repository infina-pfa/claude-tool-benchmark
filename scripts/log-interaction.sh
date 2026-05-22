#!/bin/bash
# Logs a human interaction during a benchmark run
# Usage: ./log-interaction.sh <tool> <trial> <phase> <type> <description>
# Types: approval, clarification, correction, rescue, crash, mode-choice
source "$(dirname "$0")/env.sh"

TOOL=$1; TRIAL=$2; PHASE=$3; TYPE=$4; DESC=$5
if [ -z "$DESC" ]; then
  echo "Usage: ./log-interaction.sh <tool> <trial> <phase> <type> <description>"
  echo "Types: approval, clarification, correction, rescue, crash, mode-choice"
  exit 1
fi

RESULT_DIR="$RESULTS_DIR/$TOOL/t${TRIAL}"
FILE="$RESULT_DIR/phase${PHASE}-interactions.jsonl"
mkdir -p "$RESULT_DIR"

echo "{\"time\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"type\":\"$TYPE\",\"description\":\"$DESC\"}" >> "$FILE"
echo "Logged: [$TOOL t$TRIAL p$PHASE] [$TYPE] $DESC"
