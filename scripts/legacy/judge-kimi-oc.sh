#!/bin/bash
# Kimi K2.6 via opencode-go direct API at temp=0.
# Moonshot K2.6 is a 1T MoE / 32B-active reasoning model released 2026-04-20,
# routing via opencode-go (same family as qwenoc and glm51oc wrappers).
set -uo pipefail

if [ -z "${OPENCODE_GO_API_KEY:-}" ]; then
  OPENCODE_GO_API_KEY=$(python3 -c "import json; print(json.load(open('/Users/randytran/.config/opencode/opencode.json'))['provider']['opencode-go']['options']['apiKey'])" 2>/dev/null || true)
fi

if [ -z "${OPENCODE_GO_API_KEY:-}" ]; then
  echo "ERROR: OPENCODE_GO_API_KEY not set and opencode.json lookup failed" >&2
  exit 1
fi

exec env \
  JUDGE_NAME=kimioc \
  OR_MODEL=kimi-k2.6 \
  OR_ENDPOINT=https://opencode.ai/zen/go/v1/chat/completions \
  OR_API_KEY="$OPENCODE_GO_API_KEY" \
  OR_MAX_TOKENS=50000 \
  "$(dirname "$0")/judge-openrouter.sh" "$@"
