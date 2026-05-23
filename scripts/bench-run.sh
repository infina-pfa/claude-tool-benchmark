#!/bin/bash
# Launches a benchmark session with session logging and timeout
# Usage: ./bench-run.sh <tool> <trial>
source "$(dirname "$0")/env.sh"

TOOL=$1; TRIAL=$2
if [ -z "$TOOL" ] || [ -z "$TRIAL" ]; then
  echo "Usage: ./bench-run.sh <tool> <trial>"
  echo "Tools: ${TOOLS[*]}"
  echo "Trials: 1 2 3"
  exit 1
fi

RESULT_DIR="$RESULTS_DIR/$TOOL/t${TRIAL}"
CLONE_DIR="$RUNS_DIR/${TOOL}-t${TRIAL}"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
TIMEOUT=3600  # 1 hour per session, adjust as needed

mkdir -p "$RESULT_DIR/sessions"

# Pre-run verification
"$SCRIPTS_DIR/verify-clean.sh" "$TOOL" "$TRIAL"
if [ $? -ne 0 ]; then
  echo "Pre-run verification failed. Fix issues before starting."
  exit 1
fi

# Session metadata
cat > "$RESULT_DIR/sessions/session-$TIMESTAMP.meta.json" << EOF
{
  "tool": "$TOOL",
  "trial": $TRIAL,
  "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "clone_dir": "$CLONE_DIR",
  "base_commit": "$(git -C "$CLONE_DIR" log --oneline -1)",
  "os": "$(uname -srm)",
  "node_version": "$(node -v 2>/dev/null || echo 'N/A')",
  "claude_code_version": "$(claude --version 2>/dev/null || echo 'unknown')"
}
EOF

echo ""
echo "=== Starting benchmark: $TOOL trial $TRIAL ==="
echo "=== Session log: $RESULT_DIR/sessions/session-$TIMESTAMP.log ==="
echo "=== Timeout: ${TIMEOUT}s ==="
echo "=== Start: $(date) ==="
echo ""

# Launch with clean env from clone directory
# No `script` wrapper — it corrupts Claude Code's interactive UI on macOS
# Session data is captured from Claude's own logs in CLAUDE_CONFIG_DIR/sessions/
cd "$CLONE_DIR"

env -i \
  HOME=$BENCH_HOME \
  PATH="${HOME}/.local/bin:${HOME}/.opencode/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$(dirname "$(which node)")" \
  CLAUDE_CONFIG_DIR=$CONFIG_DIR/${TOOL}-t${TRIAL} \
  TERM=${TERM:-xterm-256color} \
  USER=$USER \
  LANG=${LANG:-en_US.UTF-8} \
  claude --model claude-opus-4-6 --dangerously-skip-permissions

EXIT_CODE=$?
END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo ""
if [ $EXIT_CODE -eq 124 ]; then
  echo "=== SESSION TIMED OUT after ${TIMEOUT}s ==="
else
  echo "=== Session ended: $(date) ==="
fi

# Update metadata with end time
python3 -c "
import json
f = '$RESULT_DIR/sessions/session-$TIMESTAMP.meta.json'
with open(f) as fp:
    d = json.load(fp)
d['ended_at'] = '$END_TIME'
d['exit_code'] = $EXIT_CODE
d['timed_out'] = $( [ $EXIT_CODE -eq 124 ] && echo 'true' || echo 'false' )
with open(f, 'w') as fp:
    json.dump(d, fp, indent=2)
"

echo "Session metadata saved."
echo "Next steps:"
echo "  1. Log interactions: $SCRIPTS_DIR/log-interaction.sh $TOOL $TRIAL <phase> <type> <desc>"
echo "  2. Collect metrics:  $SCRIPTS_DIR/collect-metrics.sh $TOOL $TRIAL"
