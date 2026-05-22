#!/bin/bash
# Wipes prior Claude Code session state from a trial's CLAUDE_CONFIG_DIR so a
# rerun starts with no carryover (history, session logs, project cache, etc.)
# while preserving the installed plugins and settings.json.
#
# Usage: TASK=<task> ./scripts/wipe-session-state.sh <tool> <trial>
# Example: TASK=feature ./scripts/wipe-session-state.sh ecc 3
set -uo pipefail
source "$(dirname "$0")/env.sh"

TOOL=${1:-}
TRIAL=${2:-}
if [ -z "$TOOL" ] || [ -z "$TRIAL" ]; then
  echo "Usage: TASK=<task> ./scripts/wipe-session-state.sh <tool> <trial>"
  exit 1
fi

TOOL_CONFIG="$CONFIG_DIR/${TOOL}-t${TRIAL}"
if [ ! -d "$TOOL_CONFIG" ]; then
  echo "SKIP: $TOOL_CONFIG does not exist (nothing to wipe)"
  exit 0
fi

# Preserve: plugins/, settings.json. Wipe everything else that Claude Code
# writes during a session.
cd "$TOOL_CONFIG"
rm -rf backups cache file-history history.jsonl paste-cache plans projects \
       session-env sessions shell-snapshots
cd - >/dev/null

# .claude.json also carries per-project session history + skill usage counts,
# but holds auth (oauthAccount) and org state we need. Surgically clear only
# the stateful keys that bias a rerun.
if [ -f "$TOOL_CONFIG/.claude.json" ]; then
  python3 - "$TOOL_CONFIG/.claude.json" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
data = json.loads(p.read_text())
# Wipe the keys that carry session carryover; leave auth/org/onboarding alone.
for key in ("projects", "skillUsage", "tipsHistory"):
    if key in data:
        data[key] = {} if isinstance(data[key], dict) else []
p.write_text(json.dumps(data, indent=2))
print(f"  Scrubbed projects/skillUsage/tipsHistory in {p.name}")
PY
fi

echo "Wiped session state in $TOOL_CONFIG"
echo "Kept:"
ls -1 "$TOOL_CONFIG" | sed 's/^/  /'
