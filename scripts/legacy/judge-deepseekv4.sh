#!/bin/bash
# DeepSeek V4 Pro via opencode-go direct API at temp=0.
# Routed via opencode-go zen plan endpoint (same pattern as judge-glm51.sh,
# judge-mimo25pro.sh). Test wrapper for consistency re-check; not part of the
# locked v2 panel (deepseek was retired per docs/v2-plan.md §3b — mechanical
# block partially ignored, MAE 1.62).
set -uo pipefail

if [ -z "${OPENCODE_GO_API_KEY:-}" ]; then
  OPENCODE_GO_API_KEY=$(python3 -c "import json; print(json.load(open('/Users/randytran/.config/opencode/opencode.json'))['provider']['opencode-go']['options']['apiKey'])" 2>/dev/null || true)
fi

if [ -z "${OPENCODE_GO_API_KEY:-}" ]; then
  echo "ERROR: OPENCODE_GO_API_KEY not set and opencode.json lookup failed" >&2
  exit 1
fi

exec env \
  JUDGE_NAME=deepseekv4 \
  OR_MODEL=deepseek-v4-pro \
  OR_ENDPOINT=https://opencode.ai/zen/go/v1/chat/completions \
  OR_API_KEY="$OPENCODE_GO_API_KEY" \
  OR_MAX_TOKENS=16000 \
  "$(dirname "$0")/judge-openrouter.sh" "$@"
