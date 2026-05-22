#!/bin/bash
# gpt-5.4 judge via OpenRouter at temp=0 (provider pinned to OpenAI upstream).
# Control test sibling for judge-codex-oai.sh: same model, same temp, but
# routed through OpenRouter. Comparing codex-oai to codex-or isolates the
# OpenRouter abstraction layer as a variable.
exec env \
  JUDGE_NAME=codexor \
  OR_MODEL=openai/gpt-5.4 \
  OR_PROVIDER=openai \
  OR_MAX_TOKENS=16000 \
  "$(dirname "$0")/judge-openrouter.sh" "$@"
