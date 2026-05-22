#!/bin/bash
# Qwen3.6-plus judge via opencode-go OpenAI-compatible endpoint
# (https://opencode.ai/zen/go/v1/chat/completions) at temp=0.
#
# Purpose: methodological control for the codex/qwen vs OpenRouter judges
# comparison. The incumbent `qwen` judge runs via `opencode run` CLI, which
# doesn't expose --temperature, so those calls use provider-default sampling.
# This wrapper hits the same opencode-go plan's underlying API directly, with
# temperature pinned to 0, to isolate the "routing layer + temperature"
# confound from inherent qwen3.6-plus behavior.
#
# Output file name is `qwenoc-judge.json` per round to keep separate from the
# incumbent `qwen-judge.json`. Accuracy (MAE vs oracle) should be invariant;
# σ should drop if temperature was the noise driver.
#
# API key is the same one opencode stores in ~/.config/opencode/opencode.json
# under providers.opencode-go.options.apiKey. It's read from $OPENCODE_GO_API_KEY
# so the script itself doesn't embed the secret.
set -uo pipefail

if [ -z "${OPENCODE_GO_API_KEY:-}" ]; then
  # Fall back to reading it from opencode config for dev convenience.
  OPENCODE_GO_API_KEY=$(python3 -c "import json; print(json.load(open('/Users/randytran/.config/opencode/opencode.json'))['provider']['opencode-go']['options']['apiKey'])" 2>/dev/null || true)
fi
if [ -z "$OPENCODE_GO_API_KEY" ]; then
  echo "ERROR: OPENCODE_GO_API_KEY not set and couldn't read from opencode.json" >&2
  exit 1
fi

exec env \
  JUDGE_NAME=qwenoc \
  OR_MODEL=qwen3.6-plus \
  OR_ENDPOINT=https://opencode.ai/zen/go/v1/chat/completions \
  OR_API_KEY="$OPENCODE_GO_API_KEY" \
  OR_MAX_TOKENS=16000 \
  "$(dirname "$0")/judge-openrouter.sh" "$@"
