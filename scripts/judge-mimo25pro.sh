#!/bin/bash
# Xiaomi MiMo V2.5-Pro via OpenRouter at temp=0.
# Reasoning-tuned 1M ctx model released 2026-04-22.
# Migrated from opencode-go to OpenRouter on 2026-05-17 because the Xiaomi BYOK
# wallet on the opencode-go account (user_2z4xm5...) ran out mid-cohort; the
# OpenRouter Xiaomi endpoint (xiaomi/mimo-v2.5-pro, is_byok:false) has independent
# balance and serves the same upstream model.
# REQUIRES the v2 prompt — without the mechanical-fact pre-block this model
# rubber-stamps every item at 10 (smoke-tested 2026-04-24, sum=200/200).
set -uo pipefail

if [ -z "${OPENROUTER_API_KEY:-}" ]; then
  echo "ERROR: OPENROUTER_API_KEY not set in environment" >&2
  exit 1
fi

exec env \
  JUDGE_NAME=mimo25pro \
  OR_MODEL=xiaomi/mimo-v2.5-pro \
  OR_ENDPOINT=https://openrouter.ai/api/v1/chat/completions \
  OR_API_KEY="$OPENROUTER_API_KEY" \
  OR_MAX_TOKENS="${OR_MAX_TOKENS:-32000}" \
  OR_REASONING_EFFORT="${OR_REASONING_EFFORT:-medium}" \
  "$(dirname "$0")/judge-openrouter.sh" "$@"
