#!/bin/bash
# Z.AI GLM-4.6 judge via OpenRouter. Thin wrapper around judge-openrouter.sh.
#
# Provider pinning: GLM-4.6 is served by 6+ providers on OpenRouter
# (SiliconFlow, DeepInfra, Novita, Z.AI, AtlasCloud, Venice) with materially
# different pricing, quantization, and serving stacks. Unpinned routing
# would jump across providers between rounds and inflate σ with provider
# variance instead of model variance. We pin DeepInfra as a reputable
# mid-price endpoint (202k ctx); swap via OR_PROVIDER env if desired.
#
# Reasoning model: GLM-4.6 emits hidden CoT in `reasoning_tokens`.
# We bump OR_MAX_TOKENS to 20000 so the rubric JSON isn't truncated when
# reasoning consumes the budget before emission.
exec env JUDGE_NAME=glm OR_MODEL=z-ai/glm-4.6 OR_PROVIDER=deepinfra OR_MAX_TOKENS=20000 \
  "$(dirname "$0")/judge-openrouter.sh" "$@"
