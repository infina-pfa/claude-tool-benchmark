#!/bin/bash
# Opus 4.7 judge (replaced Sonnet 4.6 / MiMo-V2-Pro) — combined review of Phase 1+2 in one call.
# Routes through Claude Code CLI with --model claude-opus-4-7.
#
# Reproducibility note: Claude CLI does not expose --temperature or --sampler-seed
# flags, so judge inference uses the provider's default sampling. Round-to-round σ
# reported in FINAL-REPORT §7 absorbs this sampler variance; three-judge averaging
# is the primary mitigation. See PAPER.md §7 "Judge sampling not pinned" caveat.
set -uo pipefail
source "$(dirname "$0")/env.sh"

LABEL=${1:-}
if [ -z "$LABEL" ]; then
  echo "Usage: $0 <Label>" >&2
  exit 1
fi

EVAL_DIR="$RESULTS_DIR/_blind-eval"
if [ -n "${ROUND:-}" ]; then
  OUT_DIR="$EVAL_DIR/$LABEL/round${ROUND}"
else
  OUT_DIR="$EVAL_DIR/$LABEL"
fi
OUT_FILE="$OUT_DIR/opus-judge.json"
mkdir -p "$OUT_DIR"

PROMPT_SCRIPT=${PROMPT_SCRIPT:-generate-judge-prompt-combined.sh}
PROMPT=$("$SCRIPTS_DIR/$PROMPT_SCRIPT" "$LABEL" | sed 's/JUDGE_NAME/opus/g')

# Use a clean config dir to avoid hooks/skills influencing the judge
# Judges use a shared, task-independent config dir (auth lives once).
JUDGE_CONFIG="$BENCH_HOME/config/judge-opus"
mkdir -p "$JUDGE_CONFIG"

echo "$PROMPT" | env CLAUDE_CONFIG_DIR="$JUDGE_CONFIG" \
  claude -p --dangerously-skip-permissions --output-format json --model claude-opus-4-7 \
  > "$OUT_FILE.raw.json" 2>/dev/null

# Extract result text from Claude's JSON output, normalize via shared parser.
CONTENT=$(python3 -c '
import json, sys
try:
    raw = json.load(open(sys.argv[1]))
    print(raw.get("result", ""), end="")
except Exception:
    pass
' "$OUT_FILE.raw.json")

if [ -n "$CONTENT" ]; then
  python3 "$SCRIPTS_DIR/normalize-judge-json.py" "$CONTENT" "$OUT_FILE" "opus" "$LABEL" 2>/dev/null || true
fi

if [ -s "$OUT_FILE" ]; then
  echo "opus $LABEL: ok"
else
  echo "opus $LABEL: FAIL"
  exit 1
fi
