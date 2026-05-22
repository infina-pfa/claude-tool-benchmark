#!/bin/bash
# Z.AI GLM-5.1 judge via OpenRouter. Thin wrapper around judge-openrouter.sh.
#
# GLM-5.1 has 14 providers on OpenRouter (Chutes, DeepInfra, GMICloud, Phala,
# AtlasCloud, Novita, Parasail, Together, Fireworks, Z.AI, Inceptron,
# SiliconFlow, Friendli, Venice). Pinning DeepInfra for consistency with
# judge-glm.sh (same provider, apples-to-apples comparison between versions).
# ~2.7x the input cost of GLM-4.6 ($1.05/M vs $0.39/M).
#
# Like GLM-4.6, a reasoning model — keep OR_MAX_TOKENS high (20000) so the
# rubric JSON isn't truncated by hidden CoT budget consumption.
exec env JUDGE_NAME=glm51 OR_MODEL=z-ai/glm-5.1 OR_PROVIDER=deepinfra OR_MAX_TOKENS=20000 \
  "$(dirname "$0")/judge-openrouter.sh" "$@"
