#!/bin/bash
# gpt-5.4 judge via OpenAI native API at temp=0.
# Control test for the incumbent `codex` judge, which routes through
# opencode-go CLI (provider=openai, baseURL=local cliproxy, temperature
# unpinned). This wrapper hits api.openai.com directly with temperature=0
# to isolate the "routing layer + temperature" confound from inherent
# gpt-5.4 judge behavior.
#
# gpt-5.x models require `max_completion_tokens` — `max_tokens` is rejected.
# API key: $OPENAI_API_KEY.
set -uo pipefail

if [ -z "${OPENAI_API_KEY:-}" ]; then
  echo "ERROR: OPENAI_API_KEY not set in environment" >&2
  exit 1
fi

exec env \
  JUDGE_NAME=codexoai \
  OR_MODEL=gpt-5.4 \
  OR_ENDPOINT=https://api.openai.com/v1/chat/completions \
  OR_API_KEY="$OPENAI_API_KEY" \
  OR_TOKEN_FIELD=max_completion_tokens \
  OR_MAX_TOKENS=16000 \
  "$(dirname "$0")/judge-openrouter.sh" "$@"
