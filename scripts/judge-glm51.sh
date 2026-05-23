#!/bin/bash
# GLM-5.1 (Z.ai) via opencode-go direct API at temp=0.
# (Earlier OpenRouter/deepinfra-routed glm-5.1 lives at
# scripts/legacy/judge-glm51.sh — retired because mean σ across labels
# was higher; opencode-go pin gives mean σ ≤ 2.64 across {Alpha,Bravo,Uniform}.)
set -uo pipefail

if [ -z "${OPENCODE_GO_API_KEY:-}" ]; then
  OPENCODE_GO_API_KEY=$(python3 -c "import json,os; print(json.load(open(os.path.expanduser('~/.config/opencode/opencode.json')))['provider']['opencode-go']['options']['apiKey'])" 2>/dev/null || true)
fi

if [ -z "${OPENCODE_GO_API_KEY:-}" ]; then
  echo "ERROR: OPENCODE_GO_API_KEY not set and opencode.json lookup failed" >&2
  exit 1
fi

exec env \
  JUDGE_NAME=glm51 \
  OR_MODEL=glm-5.1 \
  OR_ENDPOINT=https://opencode.ai/zen/go/v1/chat/completions \
  OR_API_KEY="$OPENCODE_GO_API_KEY" \
  OR_MAX_TOKENS=16000 \
  OR_STREAM=1 \
  "$(dirname "$0")/judge-openrouter.sh" "$@"
