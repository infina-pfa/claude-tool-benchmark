#!/bin/bash
# gpt-5.4-mini judge via OpenAI native API at temp=0.
# Cheaper sibling of codex-oai (gpt-5.4). Tests whether the cheaper tier
# holds σ and MAE well enough to be a viable 4th panelist.
set -uo pipefail

if [ -z "${OPENAI_API_KEY:-}" ]; then
  echo "ERROR: OPENAI_API_KEY not set in environment" >&2
  exit 1
fi

exec env \
  JUDGE_NAME=gpt54mini \
  OR_MODEL=gpt-5.4-mini \
  OR_ENDPOINT=https://api.openai.com/v1/chat/completions \
  OR_API_KEY="$OPENAI_API_KEY" \
  OR_TOKEN_FIELD=max_completion_tokens \
  OR_MAX_TOKENS=16000 \
  "$(dirname "$0")/judge-openrouter.sh" "$@"
