#!/bin/bash
# Comparative-rank gpt-5.4 judge via local cliproxy at http://localhost:8317.
# Parallel to scripts/judge-opus1m-comparative.sh — second comparative lane for
# cross-model convergent validity (PAPER §2.5). Output filename diverges:
# `gpt54-ranking.json` alongside opus1m-ranking.json in the same cell dir.
#
# Slot name `gpt54` is honest about what cliproxy actually returns (gpt-5.4 via
# provider codex). The panel-judge slot stays `gpt54pro` for aggregation
# continuity with t1-t3 panel JSONs (judged by the real gpt-5.4-pro before the
# 2026-05-16 cliproxy flip — see versions.lock.json judges.gpt54pro
# .routing_history). The comparative lane is brand-new and uses gpt-5.4 across
# all trials, so no continuity concern.
#
# Routing: cliproxy /v1/chat/completions, model gpt-5.4. Uses json_schema
# response_format with scripts/judge-schema-comparative.json so the server-side
# validator returns ranking that matches the 8-tool comparative shape.
#
# Usage:
#   TASK=bugfix ./scripts/judge-gpt54-comparative.sh <trial> <round>
set -uo pipefail
source "$(dirname "$0")/env.sh"

TRIAL=${1:-}
ROUND=${2:-}
if [ -z "$TRIAL" ] || [ -z "$ROUND" ]; then
  echo "Usage: TASK=<task> $0 <trial> <round>" >&2
  exit 1
fi

OR_MAX_TOKENS=${OR_MAX_TOKENS:-32000}
CLIPROXY_URL=${CLIPROXY_URL:-http://localhost:8317/v1/chat/completions}
CLIPROXY_MODEL=${CLIPROXY_MODEL:-gpt-5.4}
: "${CLIPROXY_API_KEY:=admin}"

COMP_DIR="$RESULTS_DIR/_comparative-eval/t${TRIAL}/round${ROUND}"
PROMPT_FILE="$COMP_DIR/prompt.md"
MAP_FILE="$COMP_DIR/.mapping-DO-NOT-OPEN.json"
OUT_RAW="$COMP_DIR/gpt54-ranking.raw.json"
OUT_REQ="$COMP_DIR/gpt54-ranking.request.json"
OUT_JSON="$COMP_DIR/gpt54-ranking.json"

if [ ! -f "$PROMPT_FILE" ]; then
  echo "Prompt not found: $PROMPT_FILE — run comparative-eval-setup.sh $TRIAL $ROUND first" >&2
  exit 1
fi

SCHEMA_FILE="$SCRIPTS_DIR/judge-schema-comparative.json"

PROMPT_BYTES=$(wc -c < "$PROMPT_FILE")
echo "comparative-rank gpt54: task=$TASK trial=t$TRIAL round=$ROUND prompt_bytes=$PROMPT_BYTES"

# Build chat/completions body with strict json_schema response_format.
python3 - "$PROMPT_FILE" "$OUT_REQ" "$OR_MAX_TOKENS" "$SCHEMA_FILE" "$CLIPROXY_MODEL" <<'PY'
import json, sys
prompt_file, out, max_tokens, schema_file, model = sys.argv[1:6]
with open(prompt_file) as f:
    prompt = f.read()
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
  HTTP_CODE=$(curl -sS -o "$OUT_RAW" -w "%{http_code}" \
    "$CLIPROXY_URL" \
    -H "Authorization: Bearer $CLIPROXY_API_KEY" \
    -H "Content-Type: application/json" \
    --data-binary "@$OUT_REQ" 2>/dev/null)
  if [ "$HTTP_CODE" = "200" ]; then
    break
  fi
  if [ "$HTTP_CODE" != "429" ] && [ "${HTTP_CODE:0:1}" != "5" ]; then
    break
  fi
  SLEEP=$(( 15 * (1 << (attempt - 1)) ))
  [ "$SLEEP" -gt 120 ] && SLEEP=120
  echo "  gpt54 t$TRIAL round$ROUND: attempt $attempt HTTP $HTTP_CODE, retry in ${SLEEP}s" >&2
  sleep "$SLEEP"
done

if [ "$HTTP_CODE" != "200" ]; then
  echo "comparative-rank gpt54: task=$TASK trial=t$TRIAL round=$ROUND  FAIL (HTTP $HTTP_CODE)"
  head -c 2000 "$OUT_RAW" >&2
  echo >&2
  exit 1
fi

# Extract chat/completions content, validate against schema + mapping, persist
# normalized output with mapping_sha256 provenance (mirrors opus1m wrapper).
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
' "$OUT_RAW")

if [ -z "$CONTENT" ]; then
  echo "comparative-rank gpt54: task=$TASK trial=t$TRIAL round=$ROUND  FAIL (empty content)"
  head -c 2000 "$OUT_RAW" >&2
  echo >&2
  exit 1
fi

python3 - "$CONTENT" "$OUT_JSON" "$MAP_FILE" <<'PY'
import json, sys, re, hashlib

text = sys.argv[1]
out_p = sys.argv[2]
map_p = sys.argv[3]

# Strict response_format should give pure JSON, but be defensive about fences.
fence = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.DOTALL)
if fence:
    blob = fence.group(1)
else:
    s = text.find('{'); e = text.rfind('}')
    if s == -1 or e == -1 or e <= s:
        print(f"  FAIL — no JSON object (length={len(text)}): {text[:200]}", file=sys.stderr)
        sys.exit(1)
    blob = text[s:e+1]

try:
    parsed = json.loads(blob)
except json.JSONDecodeError as e:
    print(f"  FAIL — JSON parse: {e}", file=sys.stderr)
    print(f"  blob head: {blob[:200]}", file=sys.stderr)
    sys.exit(1)

mapping = json.load(open(map_p))['mapping']
expected_labels = set(mapping.keys())

ranking = parsed.get('ranking')
if not isinstance(ranking, list) or len(ranking) != len(expected_labels):
    print(f"  FAIL — ranking must be list of {len(expected_labels)}, got {type(ranking).__name__} len={len(ranking) if isinstance(ranking, list) else 'n/a'}", file=sys.stderr)
    sys.exit(1)

seen_labels = set(); seen_ranks = set()
for entry in ranking:
    if not isinstance(entry, dict):
        print(f"  FAIL — entry not dict: {entry!r}", file=sys.stderr); sys.exit(1)
    lbl = entry.get('label'); rk = entry.get('rank')
    if lbl not in expected_labels:
        print(f"  FAIL — unknown label {lbl!r}", file=sys.stderr); sys.exit(1)
    if not isinstance(rk, int) or rk < 1 or rk > len(expected_labels):
        print(f"  FAIL — bad rank {rk!r} for {lbl}", file=sys.stderr); sys.exit(1)
    if lbl in seen_labels:
        print(f"  FAIL — duplicate label {lbl}", file=sys.stderr); sys.exit(1)
    if rk in seen_ranks:
        print(f"  FAIL — duplicate rank {rk}", file=sys.stderr); sys.exit(1)
    seen_labels.add(lbl); seen_ranks.add(rk)

if seen_labels != expected_labels:
    print(f"  FAIL — missing labels: {expected_labels - seen_labels}", file=sys.stderr); sys.exit(1)

parsed['ranking'] = sorted(ranking, key=lambda x: x['rank'])
parsed.setdefault('calibration_notes', '')
parsed.setdefault('blinding_concerns', '')
with open(map_p, 'rb') as _mf:
    parsed['mapping_sha256'] = hashlib.sha256(_mf.read()).hexdigest()

json.dump(parsed, open(out_p, 'w'), indent=2)
print(f"  ok — written: {out_p}")
print(f"     top: {parsed['ranking'][0]['label']}  bottom: {parsed['ranking'][-1]['label']}")
if parsed.get('blinding_concerns','').strip():
    print(f"     [!] blinding_concerns: {parsed['blinding_concerns'][:200]}")
PY

if [ ! -s "$OUT_JSON" ]; then
  echo "comparative-rank gpt54: task=$TASK trial=t$TRIAL round=$ROUND  FAIL"
  exit 1
fi

echo "comparative-rank gpt54: task=$TASK trial=t$TRIAL round=$ROUND  ok"
