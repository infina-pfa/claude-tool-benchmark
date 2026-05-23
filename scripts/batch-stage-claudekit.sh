#!/bin/bash
# Batch-stage a claudekit trial for plan-first rerun.
# Installs fork skills at user-level (CLAUDE_CONFIG_DIR) and dedupes clone.
# Usage: ./batch-stage-claudekit.sh <task> <trial> <label>
set -eu
BENCH_HOME="${BENCH_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$BENCH_HOME"

TASK="$1"; TRIAL="$2"; LABEL="$3"
STAMP=$(date +%Y%m%d)

if [ "$TASK" = "feature" ]; then
  CLONE_DIR="runs/claudekit-t${TRIAL}"
  RESULTS_DIR="results/claudekit/t${TRIAL}"
  RESULTS_PARENT="results/claudekit"
  CONFIG_DIR="config/claudekit-t${TRIAL}"
  BE_DIR="results/_blind-eval/${LABEL}"
else
  CLONE_DIR="runs/${TASK}/claudekit-t${TRIAL}"
  RESULTS_DIR="results/${TASK}/claudekit/t${TRIAL}"
  RESULTS_PARENT="results/${TASK}/claudekit"
  CONFIG_DIR="config/${TASK}/claudekit-t${TRIAL}"
  BE_DIR="results/${TASK}/_blind-eval/${LABEL}"
fi

echo "=== Staging: $TASK claudekit t$TRIAL (label $LABEL) ==="

# 1) Archive existing results (if present and non-empty)
if [ -d "$RESULTS_DIR" ] && [ -n "$(ls -A "$RESULTS_DIR" 2>/dev/null)" ]; then
  ARCH="${RESULTS_PARENT}/archive-t${TRIAL}-${STAMP}-prerun"
  # Avoid collision if already archived today
  if [ -d "$ARCH" ]; then ARCH="${ARCH}-$(date +%H%M%S)"; fi
  echo "  1. Archive $RESULTS_DIR → $ARCH"
  mv "$RESULTS_DIR" "$ARCH"
  mkdir -p "$RESULTS_DIR"
else
  echo "  1. No prior results to archive (empty or missing)"
  mkdir -p "$RESULTS_DIR"
fi

# 2) Archive blind-eval judge JSONs (if any currently live, rename to .pre-rerun-v2)
if [ -d "$BE_DIR" ]; then
  for r in "$BE_DIR"/round*; do
    [ -d "$r" ] || continue
    for j in "$r"/opus-judge.json "$r"/codex-judge.json "$r"/qwen-judge.json; do
      if [ -f "$j" ]; then
        target="${j}.pre-rerun-v2-${STAMP}"
        # Keep original if not yet preserved
        [ -f "${j}.pre-rerun.json" ] || mv "$j" "${j}.pre-rerun.json"
        # If a current live file exists, move it aside
        [ -f "$j" ] && mv "$j" "$target"
      fi
    done
  done
  echo "  2. Archived any live judge JSONs in $BE_DIR"
fi

# 3) Clone: ensure pristine base + config-install (create if missing, reset if present)
if [ ! -d "$CLONE_DIR" ]; then
  echo "  3a. Creating fresh clone"
  TASK=$TASK ./scripts/create-clones.sh "$TRIAL" 2>&1 | tail -3 | sed 's/^/     /'
else
  echo "  3a. Clone exists — resetting to pristine (keep CLAUDE.md.original from base-repo)"
  (cd "$CLONE_DIR" && git reset --hard "$(git log --format=%H --grep='^base:' | head -1)" 2>&1 | sed 's/^/     /')
  # Remove any scratch files created by prior trial runs (plans/, _bmad/, etc.)
  (cd "$CLONE_DIR" && git clean -fdx -e node_modules 2>&1 | sed 's/^/     /' | head -5)
fi

# 4) Install claudekit fork into clone (writes .claude/ in clone + fixes hook node paths + commits)
echo "  4. Install claudekit fork into clone"
TASK=$TASK ./scripts/setup-tool-config.sh claudekit "$TRIAL" 2>&1 | tail -3 | sed 's/^/     /'

# 5) Install fork .claude/* into CONFIG dir (user-level skills for /ck:plan dispatch)
SRC=/tmp/internal-claudekit/.claude
if [ ! -d "$SRC" ]; then
  echo "  ERROR: $SRC missing — clone # first"
  exit 1
fi
mkdir -p "$CONFIG_DIR"
# Preserve existing harness settings.json keys (effortLevel, skipDangerousModePermissionPrompt, etc.)
# by saving a sidecar copy that Python can read from disk — avoids shell-expansion breakage on complex JSON.
STUB_SIDECAR=""
if [ -f "$CONFIG_DIR/settings.json" ]; then
  STUB_SIDECAR="$CONFIG_DIR/settings.json.stub-before-merge"
  cp "$CONFIG_DIR/settings.json" "$STUB_SIDECAR"
fi
# Copy fork contents (skip session-state template)
for item in "$SRC"/*; do
  name=$(basename "$item")
  [ "$name" = "session-state" ] && continue
  cp -R "$item" "$CONFIG_DIR/"
done
# Merge settings: fork base + harness stub keys (stub wins where keys overlap), fix node paths.
NODE_BIN=$(which node)
STUB_SIDECAR="$STUB_SIDECAR" NODE_BIN="$NODE_BIN" SRC="$SRC" CONFIG_DIR="$CONFIG_DIR" python3 <<'PY'
import json, os
fork = json.load(open(os.path.join(os.environ['SRC'], 'settings.json')))
stub_path = os.environ.get('STUB_SIDECAR')
stub = {}
if stub_path and os.path.exists(stub_path):
    try:
        stub = json.load(open(stub_path))
    except Exception:
        stub = {}
# Preserve known harness keys if present in stub; otherwise ensure defaults.
out = dict(fork)
for k in ('effortLevel', 'skipDangerousModePermissionPrompt'):
    if k in stub:
        out[k] = stub[k]
out.setdefault('effortLevel', 'medium')
out.setdefault('skipDangerousModePermissionPrompt', True)
# Fix hook node paths for isolated env
s = json.dumps(out).replace('"command": "node ', f'"command": "{os.environ["NODE_BIN"]} ')
json.dump(json.loads(s), open(os.path.join(os.environ['CONFIG_DIR'], 'settings.json'), 'w'), indent=2)
# Clean up sidecar
if stub_path and os.path.exists(stub_path):
    os.remove(stub_path)
PY
echo "  5. Installed fork .claude/* into $CONFIG_DIR (skills, agents, hooks; effortLevel preserved)"

# 6) Dedupe: remove project-level skills from clone (user-level only via config dir)
if [ -d "$CLONE_DIR/.claude/skills" ]; then
  rm -rf "$CLONE_DIR/.claude/skills"
  echo "  6. Removed $CLONE_DIR/.claude/skills (dedupe — user-level in config)"
fi

# 7) Wipe config session state
echo "  7. Wipe session state"
TASK=$TASK ./scripts/wipe-session-state.sh claudekit "$TRIAL" 2>&1 | tail -2 | sed 's/^/     /'

# 8) Verify clean
echo "  8. Verify clean"
TASK=$TASK ./scripts/verify-clean.sh claudekit "$TRIAL" 2>&1 | tail -5 | sed 's/^/     /'

echo "=== $TASK t$TRIAL ready ==="
echo
