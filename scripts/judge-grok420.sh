#!/bin/bash
# Grok 4.20 via OpenRouter (xAI provider) at temp=0.
# Successor to grok-4 which is in our current v2 panel. This wrapper enables
# a direct A/B test.
#
# KNOWN RISK: Grok family has triggered spurious SAFETY_CHECK_TYPE_BIO filters
# on even trivial 8-token smoke prompts (charged $0.05 for the refusal). Full
# 16k-token judge prompts have not tripped the filter historically, but it is
# a non-zero risk budget item.
exec env \
  JUDGE_NAME=grok420 \
  OR_MODEL=x-ai/grok-4.20 \
  OR_PROVIDER=xai \
  OR_MAX_TOKENS=6000 \
  OR_JSON_SCHEMA_FILE="$(dirname "$0")/judge-schema-v2.json" \
  "$(dirname "$0")/judge-openrouter.sh" "$@"
