#!/bin/bash
# o4-mini (reasoning) judge via OpenAI native API.
# Same caveats as o3: temp=1 forced, hidden CoT inflates output tokens.
# Cheaper reasoning alternative to o3 for cost/quality comparison.
set -uo pipefail

if [ -z "${OPENAI_API_KEY:-}" ]; then
  echo "ERROR: OPENAI_API_KEY not set in environment" >&2
  exit 1
fi

exec env \
  JUDGE_NAME=o4mini \
  OR_MODEL=o4-mini \
  OR_ENDPOINT=https://api.openai.com/v1/chat/completions \
  OR_API_KEY="$OPENAI_API_KEY" \
  OR_TOKEN_FIELD=max_completion_tokens \
  OR_MAX_TOKENS=32000 \
  OR_TEMPERATURE=1 \
  "$(dirname "$0")/judge-openrouter.sh" "$@"
