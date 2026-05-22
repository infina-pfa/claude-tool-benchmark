#!/bin/bash
# xAI Grok-4 judge via OpenRouter. Thin wrapper around judge-openrouter.sh.
#
# Note on safety filter: grok-4 occasionally emits SAFETY_CHECK_TYPE_BIO
# refusals on short, benign prompts. Real 20-item rubric prompts (~16k tokens
# of code review context) do not trip the filter in our tests, but a refusal
# will surface as "FAIL (JSON parse or empty response)" with finish_reason
# "content_filter" in the .raw.txt — retry once manually if that happens.
exec env JUDGE_NAME=grok OR_MODEL=x-ai/grok-4 OR_PROVIDER=xai \
  "$(dirname "$0")/judge-openrouter.sh" "$@"
