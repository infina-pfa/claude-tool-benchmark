#!/bin/bash
# Generic OpenRouter-routed judge. Wraps the 20-item combined rubric.
# Thin wrappers (judge-grok.sh, judge-deepseek.sh, etc.) set env and exec this.
#
# Required env:
#   JUDGE_NAME   — short id for output filename and the JUDGE_NAME substitution
#                   in the rendered prompt (e.g. "grok", "deepseek", "gemini")
#   OR_MODEL     — model id (e.g. "x-ai/grok-4" on OpenRouter, or
#                   "opencode-go/qwen3.6-plus" on opencode-go)
# Optional env:
#   OR_ENDPOINT     — chat-completions URL. Default: OpenRouter's.
#                      Override to hit any OpenAI-compatible endpoint
#                      (e.g. https://opencode.ai/zen/go/v1/chat/completions).
#   OR_API_KEY      — bearer token. Default: $OPENROUTER_API_KEY.
#                      Override for non-OpenRouter endpoints.
#   OR_PROVIDER     — OpenRouter provider slug to pin (e.g. "xai", "deepseek").
#                      Ignored by non-OpenRouter endpoints since the `provider`
#                      field is OpenRouter-specific.
#   OR_MAX_TOKENS   — default 8000; raise for reasoning models that emit long CoT.
#   OR_TOKEN_FIELD  — default "max_tokens". Set to "max_completion_tokens"
#                      when hitting OpenAI native (gpt-5.x rejects max_tokens).
#   OR_REASONING_EFFORT — optional. "low" | "medium" | "high". When set, adds
#                          `reasoning: {"effort": <value>}` to the request body
#                          (OpenAI/OpenRouter reasoning-control standard).
#                          Used to bound reasoning-loop blow-up on dense diffs.
#   OR_STREAM           — when "1", request `stream: true` and parse the SSE
#                          response. Prevents silent `--max-time` aborts on
#                          slow-CoT models whose first token can lag past the
#                          buffered timeout (observed with glm-5.1 on dense
#                          diffs). Output JSON shape is unchanged downstream.
#
# Positional: <Label>
#
# Reproducibility: temperature pinned to 0. Sampler seed is not exposed by the
# OpenRouter Chat Completions API, so residual nondeterminism is absorbed by
# round-to-round σ (see compare-judge-consistency.py).
set -uo pipefail
source "$(dirname "$0")/env.sh"

LABEL=${1:-}
JUDGE_NAME=${JUDGE_NAME:-}
OR_MODEL=${OR_MODEL:-}
OR_PROVIDER=${OR_PROVIDER:-}
OR_MAX_TOKENS=${OR_MAX_TOKENS:-8000}
OR_ENDPOINT=${OR_ENDPOINT:-https://openrouter.ai/api/v1/chat/completions}
OR_API_KEY=${OR_API_KEY:-${OPENROUTER_API_KEY:-}}
OR_TOKEN_FIELD=${OR_TOKEN_FIELD:-max_tokens}
OR_TEMPERATURE=${OR_TEMPERATURE:-0}
OR_REASONING_EFFORT=${OR_REASONING_EFFORT:-}
OR_STREAM=${OR_STREAM:-}

if [ -z "$LABEL" ] || [ -z "$JUDGE_NAME" ] || [ -z "$OR_MODEL" ]; then
  echo "Usage: JUDGE_NAME=<id> OR_MODEL=<or-model> [OR_PROVIDER=<slug>] $0 <Label>" >&2
  exit 1
fi
if [ -z "$OR_API_KEY" ]; then
  echo "ERROR: OR_API_KEY (or OPENROUTER_API_KEY) not set in environment" >&2
  exit 1
fi

EVAL_DIR="$RESULTS_DIR/_blind-eval"
if [ -n "${ROUND:-}" ]; then
  OUT_DIR="$EVAL_DIR/$LABEL/round${ROUND}"
else
  OUT_DIR="$EVAL_DIR/$LABEL"
fi
OUT_FILE="$OUT_DIR/${JUDGE_NAME}-judge.json"
RAW_FILE="$OUT_FILE.raw.txt"
REQ_FILE="$OUT_FILE.request.json"
mkdir -p "$OUT_DIR"

PROMPT_SCRIPT=${PROMPT_SCRIPT:-generate-judge-prompt-combined.sh}
PROMPT=$("$SCRIPTS_DIR/$PROMPT_SCRIPT" "$LABEL" | sed "s/JUDGE_NAME/${JUDGE_NAME}/g")

python3 - "$PROMPT" "$REQ_FILE" "$OR_MODEL" "$OR_PROVIDER" "$OR_MAX_TOKENS" "$OR_TOKEN_FIELD" "$OR_TEMPERATURE" "${OR_JSON_SCHEMA_FILE:-}" "$OR_REASONING_EFFORT" "$OR_STREAM" <<'PY'
import json, sys
prompt, out, model, provider, max_tokens, token_field, temperature, schema_file, reasoning_effort, stream = sys.argv[1:11]
body = {
    "model": model,
    "messages": [{"role": "user", "content": prompt}],
    "temperature": float(temperature),
    token_field: int(max_tokens),
}
if provider:
    body["provider"] = {"order": [provider], "allow_fallbacks": False}
if schema_file:
    with open(schema_file) as f:
        body["response_format"] = {"type": "json_schema", "json_schema": json.load(f)}
if reasoning_effort:
    body["reasoning"] = {"effort": reasoning_effort}
if stream == "1":
    body["stream"] = True
with open(out, "w") as f:
    json.dump(body, f)
PY

# Retry on 429 / 5xx with exponential backoff: 15, 30, 60, 120, 120 s.
HTTP_CODE=""
# Streaming raises --max-time because the buffered path can silently abort
# before slow-CoT models emit their first byte; SSE keeps the socket warm.
CURL_MAX_TIME=300
CURL_EXTRA=()
if [ "$OR_STREAM" = "1" ]; then
  CURL_MAX_TIME=600
  CURL_EXTRA+=(-N -H "Accept: text/event-stream")
fi
for attempt in 1 2 3 4 5; do
  # --connect-timeout 15s, --max-time bounded so a hung backend
  # (observed with Fireworks-hosted glm-5.1 on large payloads) can't wedge the
  # wrapper indefinitely. Successful judge calls historically land in 30–120 s.
  HTTP_CODE=$(curl -sS --connect-timeout 15 --max-time "$CURL_MAX_TIME" \
    ${CURL_EXTRA[@]+"${CURL_EXTRA[@]}"} \
    -o "$RAW_FILE" -w "%{http_code}" \
    "$OR_ENDPOINT" \
    -H "Authorization: Bearer $OR_API_KEY" \
    -H "Content-Type: application/json" \
    -H "X-Title: ai-tool-benchmark/judge-${JUDGE_NAME}" \
    --data-binary "@$REQ_FILE" 2>/dev/null)
  if [ "$HTTP_CODE" = "200" ]; then
    break
  fi
  if [ "$HTTP_CODE" != "429" ] && [ "${HTTP_CODE:0:1}" != "5" ]; then
    break
  fi
  SLEEP=$(( 15 * (1 << (attempt - 1)) ))
  [ "$SLEEP" -gt 120 ] && SLEEP=120
  echo "${JUDGE_NAME} $LABEL: attempt $attempt got HTTP $HTTP_CODE, retrying in ${SLEEP}s" >&2
  sleep "$SLEEP"
done

if [ "$HTTP_CODE" != "200" ]; then
  echo "${JUDGE_NAME} $LABEL: FAIL (HTTP $HTTP_CODE)"
  head -c 2000 "$RAW_FILE" >&2
  echo >&2
  exit 1
fi

CONTENT=$(python3 -c '
import json, sys
path, streamed = sys.argv[1], sys.argv[2] == "1"
try:
    if streamed:
        parts = []
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line.startswith("data:"):
                    continue
                payload = line[5:].strip()
                if payload == "[DONE]" or not payload:
                    continue
                try:
                    chunk = json.loads(payload)
                except Exception:
                    continue
                choices = chunk.get("choices") or []
                if not choices:
                    continue
                delta = choices[0].get("delta") or {}
                piece = delta.get("content")
                if piece is None:
                    # Some providers stream the full message at completion.
                    msg = choices[0].get("message") or {}
                    piece = msg.get("content")
                if piece:
                    parts.append(piece)
        print("".join(parts), end="")
    else:
        raw = json.load(open(path))
        print((raw.get("choices") or [{}])[0].get("message", {}).get("content") or "", end="")
except Exception:
    pass
' "$RAW_FILE" "$OR_STREAM")

if [ -n "$CONTENT" ]; then
  python3 "$SCRIPTS_DIR/normalize-judge-json.py" "$CONTENT" "$OUT_FILE" "$JUDGE_NAME" "$LABEL" 2>/dev/null || true
fi

if [ -s "$OUT_FILE" ]; then
  echo "${JUDGE_NAME} $LABEL: ok"
else
  echo "${JUDGE_NAME} $LABEL: FAIL (JSON parse or empty response)"
  exit 1
fi
