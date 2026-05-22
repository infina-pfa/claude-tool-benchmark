#!/bin/bash
# generate-lockfile.sh — introspect installed plugin/tool versions across all
# trial config dirs and print a per-trial drift report. Used to regenerate the
# `trial_drift_observed_*` block of versions.lock.json after a cohort refresh.
#
# Does NOT mutate versions.lock.json directly — prints to stdout. Pipe through
# the maintainer's editor of choice or compare against the existing lockfile
# with `scripts/verify-versions.sh`.
#
# Usage:
#   ./scripts/generate-lockfile.sh                       # human-readable
#   ./scripts/generate-lockfile.sh --json                # machine-readable
set -euo pipefail
cd "$(dirname "$0")/.."

FORMAT=${1:-text}

# Per-trial plugin install state from installed_plugins.json
collect_trials() {
  python3 - <<'PY'
import json, glob, os, sys
rows = []
for p in sorted(glob.glob("config/*/plugins/installed_plugins.json")):
    trial = p.split("/")[1]
    try:
        d = json.load(open(p))
    except Exception:
        continue
    for plugin_id, entries in (d.get("plugins") or {}).items():
        for e in entries:
            rows.append({
                "trial": trial,
                "plugin": plugin_id,
                "version": e.get("version", "?"),
                "sha": (e.get("gitCommitSha") or "")[:8],
            })
print(json.dumps(rows))
PY
}

# Gstack clone state per trial dir (not a plugin — direct skill-pack clone)
collect_gstack() {
  for d in config/gstack-t*/skills/gstack; do
    [ -d "$d" ] || continue
    trial=$(echo "$d" | sed -E 's|config/([^/]+)/.*|\1|')
    ver=$(cat "$d/VERSION" 2>/dev/null | tr -d '\n' || echo '?')
    sha=$(git -C "$d" rev-parse --short HEAD 2>/dev/null || echo '?')
    printf '{"trial":"%s","plugin":"gstack@local-clone","version":"%s","sha":"%s"}\n' "$trial" "$ver" "$sha"
  done
}

# Claudekit fork state (cached at /tmp/internal-claudekit by setup-tool-config.sh)
collect_claudekit() {
  d=/tmp/internal-claudekit
  if [ -d "$d/.git" ]; then
    sha=$(git -C "$d" rev-parse --short HEAD)
    branch=$(git -C "$d" branch --show-current)
    printf '{"trial":"_global","plugin":"claudekit@fork","version":"branch=%s","sha":"%s"}\n' "$branch" "$sha"
  fi
}

# Base repos
collect_base_repos() {
  for task in feature bugfix refactor; do
    TASK=$task source scripts/env.sh 2>/dev/null
    full=$(git -C "$BASE_REPO" rev-parse "$BENCH_COMMIT" 2>/dev/null || echo '?')
    printf '{"trial":"_base","plugin":"base-repo:%s","version":"%s","sha":"%s"}\n' "$task" "$BENCH_COMMIT" "${full:0:8}"
  done
}

# Claude CLI
collect_cli() {
  ver=$(claude --version 2>/dev/null | head -1 | awk '{print $1}')
  printf '{"trial":"_global","plugin":"claude-cli","version":"%s","sha":"-"}\n' "$ver"
}

if [ "$FORMAT" = "--json" ] || [ "$FORMAT" = "json" ]; then
  echo '['
  first=1
  collect_trials | python3 -c "import sys,json; [print(json.dumps(r)) for r in json.load(sys.stdin)]"
  collect_gstack
  collect_claudekit
  collect_base_repos
  collect_cli
  echo ']'
else
  printf '%-18s | %-50s | %-12s | %s\n' "trial" "plugin" "version" "sha"
  printf '%-18s | %-50s | %-12s | %s\n' "------" "------" "-------" "---"
  collect_trials | python3 -c "
import sys, json
for r in json.load(sys.stdin):
    print(f\"{r['trial']:<18} | {r['plugin']:<50} | {r['version']:<12} | {r['sha']}\")
"
  for line in $(collect_gstack); do
    echo "$line" | python3 -c "
import sys, json
for line in sys.stdin:
    r = json.loads(line)
    print(f\"{r['trial']:<18} | {r['plugin']:<50} | {r['version']:<12} | {r['sha']}\")
"
  done
  collect_claudekit | python3 -c "
import sys, json
for line in sys.stdin:
    r = json.loads(line)
    print(f\"{r['trial']:<18} | {r['plugin']:<50} | {r['version']:<12} | {r['sha']}\")
"
  collect_base_repos | python3 -c "
import sys, json
for line in sys.stdin:
    r = json.loads(line)
    print(f\"{r['trial']:<18} | {r['plugin']:<50} | {r['version']:<12} | {r['sha']}\")
"
  collect_cli | python3 -c "
import sys, json
for line in sys.stdin:
    r = json.loads(line)
    print(f\"{r['trial']:<18} | {r['plugin']:<50} | {r['version']:<12} | {r['sha']}\")
"
fi
