#!/bin/bash
# gpt-5.4 judge via local cliproxy at http://localhost:8317/v1/chat/completions.
#
# 2026-05-16: routing flipped from api.openai.com /v1/responses (gpt-5.4-pro) to
# cliproxy /v1/chat/completions (gpt-5.4). Scope of swap is documented in
# versions.lock.json `judges.gpt54pro.routing_history`. Slot name stays
# `gpt54pro` for aggregation continuity with t1-t3 JSONs; the `model` field
# written into the returned JSON reflects what cliproxy returns (gpt-5.4), so
# the per-file metadata is honest about which upstream answered.
#
# gpt-5.x is a reasoning model; temperature is not pinned (cliproxy passes
# through default sampling). `max_completion_tokens` is required — `max_tokens`
# is rejected by gpt-5.x.
#
# Auth: $CLIPROXY_API_KEY (defaults to "admin" — matches the local dev pin in
# ~/.zshrc / ~/.cli-proxy-api/config.yaml).
set -uo pipefail
source "$(dirname "$0")/env.sh"

LABEL=${1:-}
JUDGE_NAME=gpt54pro
OR_MAX_TOKENS=${OR_MAX_TOKENS:-32000}
CLIPROXY_URL=${CLIPROXY_URL:-http://localhost:8317/v1/chat/completions}
CLIPROXY_MODEL=${CLIPROXY_MODEL:-gpt-5.4}
: "${CLIPROXY_API_KEY:=admin}"

if [ -z "$LABEL" ]; then
  echo "Usage: $0 <Label>" >&2
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

SCHEMA_FILE="$SCRIPTS_DIR/judge-schema-v2.json"
python3 - "$PROMPT" "$REQ_FILE" "$OR_MAX_TOKENS" "$SCHEMA_FILE" "$CLIPROXY_MODEL" <<'PY'
import json, sys
prompt, out, max_tokens, schema_file, model = sys.argv[1:6]
with open(schema_file) as f:
    schema = json.load(f)
body = {
    "model": model,
    "messages": [{"role": "user", "content": prompt}],
    "max_completion_tokens": int(max_tokens),
    "response_format": {"type": "json_schema", **schema},
}
with open(out, "w") as f:
    json.dump(body, f)
PY

# Retry on 429 / 5xx with exponential backoff: 15, 30, 60, 120, 120 s.
HTTP_CODE=""
for attempt in 1 2 3 4 5; do
  HTTP_CODE=$(curl -sS -o "$RAW_FILE" -w "%{http_code}" \
    "$CLIPROXY_URL" \
    -H "Authorization: Bearer $CLIPROXY_API_KEY" \
    -H "Content-Type: application/json" \
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

# Extract chat/completions content, normalize via shared parser.
CONTENT=$(python3 -c '
import json, sys
try:
    raw = json.load(open(sys.argv[1]))
    choices = raw.get("choices") or []
    text = ""
    if choices:
        msg = choices[0].get("message") or {}
        text = msg.get("content") or ""
    print(text, end="")
except Exception:
    pass
' "$RAW_FILE")

if [ -n "$CONTENT" ]; then
  python3 "$SCRIPTS_DIR/normalize-judge-json.py" "$CONTENT" "$OUT_FILE" "$JUDGE_NAME" "$LABEL" 2>/dev/null || true
fi

if [ -s "$OUT_FILE" ]; then
  echo "${JUDGE_NAME} $LABEL: ok"
else
  echo "${JUDGE_NAME} $LABEL: FAIL (JSON parse or empty response)"
  exit 1
fi
