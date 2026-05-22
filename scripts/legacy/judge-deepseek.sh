#!/bin/bash
# DeepSeek V4 Pro judge — combined review of all 3 phases in one call.
# Routes through OpenRouter (model: deepseek/deepseek-v4-pro).
# Requires $OPENROUTER_API_KEY in the environment.
#
# Reproducibility note: OpenRouter's chat/completions API does not expose a
# sampler-seed parameter. Temperature is explicitly pinned to 0 here; that
# reduces but does not eliminate nondeterminism (MoE routing, provider-side
# batching). Round-to-round σ across rounds 1..N absorbs residual variance;
# three-judge averaging (when used in the final panel) is the primary mitigation.
set -uo pipefail
source "$(dirname "$0")/env.sh"

LABEL=${1:-}
if [ -z "$LABEL" ]; then
  echo "Usage: $0 <Label>" >&2
  exit 1
fi

if [ -z "${OPENROUTER_API_KEY:-}" ]; then
  echo "ERROR: OPENROUTER_API_KEY not set in environment" >&2
  exit 1
fi

EVAL_DIR="$RESULTS_DIR/_blind-eval"
if [ -n "${ROUND:-}" ]; then
  OUT_DIR="$EVAL_DIR/$LABEL/round${ROUND}"
else
  OUT_DIR="$EVAL_DIR/$LABEL"
fi
OUT_FILE="$OUT_DIR/deepseek-judge.json"
RAW_FILE="$OUT_FILE.raw.txt"
REQ_FILE="$OUT_FILE.request.json"
mkdir -p "$OUT_DIR"

PROMPT=$("$SCRIPTS_DIR/generate-judge-prompt-combined.sh" "$LABEL" | sed 's/JUDGE_NAME/deepseek/g')

# Build the request body. Temperature pinned to 0 for max determinism the API
# allows. provider.require_parameters + order forces the DeepSeek-hosted
# endpoint (currently the only one) and fails fast if it disappears.
python3 - "$PROMPT" "$REQ_FILE" <<'PY'
import json, sys
prompt, out = sys.argv[1], sys.argv[2]
body = {
    "model": "deepseek/deepseek-v4-pro",
    "messages": [{"role": "user", "content": prompt}],
    "temperature": 0,
    "max_tokens": 8000,
    "provider": {
        "order": ["deepseek"],
        "allow_fallbacks": False,
    },
}
with open(out, "w") as f:
    json.dump(body, f)
PY

# Retry on 429 (upstream rate limit) with exponential backoff:
# 15s, 30s, 60s, 120s. ~4 minutes max wall time before giving up.
HTTP_CODE=""
for attempt in 1 2 3 4 5; do
  HTTP_CODE=$(curl -sS -o "$RAW_FILE" -w "%{http_code}" \
    https://openrouter.ai/api/v1/chat/completions \
    -H "Authorization: Bearer $OPENROUTER_API_KEY" \
    -H "Content-Type: application/json" \
    -H "X-Title: ai-tool-benchmark/judge-deepseek" \
    --data-binary "@$REQ_FILE" 2>/dev/null)
  if [ "$HTTP_CODE" = "200" ]; then
    break
  fi
  # Treat 429 and 5xx as retriable; other codes fail immediately.
  if [ "$HTTP_CODE" != "429" ] && [ "${HTTP_CODE:0:1}" != "5" ]; then
    break
  fi
  SLEEP=$(( 15 * (1 << (attempt - 1)) ))
  [ "$SLEEP" -gt 120 ] && SLEEP=120
  echo "deepseek $LABEL: attempt $attempt got HTTP $HTTP_CODE, retrying in ${SLEEP}s" >&2
  sleep "$SLEEP"
done

if [ "$HTTP_CODE" != "200" ]; then
  echo "deepseek $LABEL: FAIL (HTTP $HTTP_CODE)"
  echo "--- raw response: ---" >&2
  head -c 2000 "$RAW_FILE" >&2
  echo >&2
  exit 1
fi

# Extract the assistant content from OpenRouter's chat-completion response,
# then parse the embedded judge JSON the same way judge-qwen.sh does.
python3 - "$RAW_FILE" "$OUT_FILE" <<'PY' 2>/dev/null
import json, re, sys
in_path, out_path = sys.argv[1], sys.argv[2]
try:
    raw = json.load(open(in_path))
    text = raw.get("choices", [{}])[0].get("message", {}).get("content", "") or ""
    text = re.sub(r'```json?\s*', '', text)
    text = re.sub(r'```', '', text)
    try:
        parsed = json.loads(text.strip())
        if 'total' in parsed and 'scores' in parsed:
            json.dump(parsed, open(out_path, 'w'), indent=2)
            sys.exit(0)
    except json.JSONDecodeError:
        pass
    # Fallback: find the LAST balanced JSON object containing both fields.
    candidates = []
    depth = 0
    start = -1
    for i, ch in enumerate(text):
        if ch == '{':
            if depth == 0:
                start = i
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0 and start >= 0:
                candidates.append(text[start:i+1])
                start = -1
    for snippet in reversed(candidates):
        try:
            parsed = json.loads(snippet)
            if 'total' in parsed and 'scores' in parsed:
                json.dump(parsed, open(out_path, 'w'), indent=2)
                sys.exit(0)
        except json.JSONDecodeError:
            continue
except Exception:
    pass
PY

if [ -s "$OUT_FILE" ]; then
  echo "deepseek $LABEL: ok"
else
  echo "deepseek $LABEL: FAIL (JSON parse)"
  exit 1
fi
