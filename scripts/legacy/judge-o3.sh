#!/bin/bash
# o3 (reasoning) judge via OpenAI native API.
# Reasoning models: temperature is forced to 1 (API rejects 0). σ is therefore
# NOT comparable head-to-head to temp=0 judges — but MAE-vs-oracle is still
# informative. Hidden CoT via reasoning_tokens inflates output tokens 5-20x.
set -uo pipefail

if [ -z "${OPENAI_API_KEY:-}" ]; then
  echo "ERROR: OPENAI_API_KEY not set in environment" >&2
  exit 1
fi

exec env \
  JUDGE_NAME=o3 \
  OR_MODEL=o3 \
  OR_ENDPOINT=https://api.openai.com/v1/chat/completions \
  OR_API_KEY="$OPENAI_API_KEY" \
  OR_TOKEN_FIELD=max_completion_tokens \
  OR_MAX_TOKENS=32000 \
  OR_TEMPERATURE=1 \
  "$(dirname "$0")/judge-openrouter.sh" "$@"
