#!/bin/bash
# Comparative-rank Opus judge. Reads the per-(task, trial, round) prompt produced by
# comparative-eval-setup.sh and sends it to Opus via the Claude CLI. Saves both the raw
# envelope and the parsed ranking JSON.
#
# Mirrors scripts/judge-opus.sh CLI invocation (--model claude-opus-4-7, subscription auth
# via CLAUDE_CONFIG_DIR=$BENCH_HOME/config/judge-opus). If the bundle exceeds the
# subscription window, the call errors out and the operator runs the prompt manually
# (open prompt.md in a 1M-context session, paste the JSON response back in place of
# opus1m-ranking.json).
#
# Usage:
#   TASK=bugfix ./scripts/judge-opus1m-comparative.sh <trial> <round>
set -uo pipefail
source "$(dirname "$0")/env.sh"

TRIAL=${1:-}
ROUND=${2:-}
if [ -z "$TRIAL" ] || [ -z "$ROUND" ]; then
  echo "Usage: TASK=<task> $0 <trial> <round>" >&2
  exit 1
fi

COMP_DIR="$RESULTS_DIR/_comparative-eval/t${TRIAL}/round${ROUND}"
PROMPT_FILE="$COMP_DIR/prompt.md"
MAP_FILE="$COMP_DIR/.mapping-DO-NOT-OPEN.json"
OUT_RAW="$COMP_DIR/opus1m-ranking.raw.json"
OUT_JSON="$COMP_DIR/opus1m-ranking.json"

if [ ! -f "$PROMPT_FILE" ]; then
  echo "Prompt not found: $PROMPT_FILE — run comparative-eval-setup.sh $TRIAL $ROUND first" >&2
  exit 1
fi

JUDGE_CONFIG="$BENCH_HOME/config/judge-opus"
mkdir -p "$JUDGE_CONFIG"

PROMPT_BYTES=$(wc -c < "$PROMPT_FILE")
echo "comparative-rank opus1m: task=$TASK trial=t$TRIAL round=$ROUND prompt_bytes=$PROMPT_BYTES"

# Send. --dangerously-skip-permissions matches existing judge invocations; output-format=json
# gives us the .result envelope. No --temperature flag is exposed by Claude CLI; comparative
# variance is mitigated by the multi-round design (3 rounds × per-round shuffle).
cat "$PROMPT_FILE" | env CLAUDE_CONFIG_DIR="$JUDGE_CONFIG" \
  claude -p --dangerously-skip-permissions --output-format json --model claude-opus-4-7 \
  > "$OUT_RAW" 2>"$OUT_RAW.stderr" || true

# Extract result text from envelope
RESULT_TEXT=$(python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    if d.get("is_error"):
        print(json.dumps({"_error": True, "envelope": d}), file=sys.stderr)
        sys.exit(0)
    print(d.get("result", ""), end="")
except Exception as e:
    print(f"_parse_error: {e}", file=sys.stderr)
' "$OUT_RAW" 2>"$OUT_JSON.parse-err")

# The 2> redirections above always create the sidecars even on a clean run;
# an empty sidecar is not a failure. Drop zero-byte ones so the published
# corpus tree does not look littered with phantom parse/stderr errors.
[ -s "$OUT_RAW.stderr" ] || rm -f "$OUT_RAW.stderr"
[ -s "$OUT_JSON.parse-err" ] || rm -f "$OUT_JSON.parse-err"

if [ -z "$RESULT_TEXT" ]; then
  echo "  FAIL — no result text. Envelope dump:"
  head -5 "$OUT_RAW"
  echo "  --- stderr ---"
  head -5 "$OUT_RAW.stderr"
  echo "  --- parse-err ---"
  head -5 "$OUT_JSON.parse-err"
  exit 1
fi

# Extract the JSON object from the result (strip optional fenced ```json wrapper)
python3 - "$RESULT_TEXT" "$OUT_JSON" "$MAP_FILE" <<'PY'
import json, sys, re, hashlib

text = sys.argv[1]
out_p = sys.argv[2]
map_p = sys.argv[3]

# Strip ```json ... ``` fence if present
fence = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.DOTALL)
if fence:
    blob = fence.group(1)
else:
    # Fall back: first { to last }
    s = text.find('{')
    e = text.rfind('}')
    if s == -1 or e == -1 or e <= s:
        print(f"  FAIL — no JSON object in result text (length={len(text)})", file=sys.stderr)
        sys.exit(1)
    blob = text[s:e+1]

try:
    parsed = json.loads(blob)
except json.JSONDecodeError as e:
    print(f"  FAIL — JSON parse error: {e}", file=sys.stderr)
    print(f"  blob head: {blob[:200]}", file=sys.stderr)
    sys.exit(1)

# Validate schema
mapping = json.load(open(map_p))['mapping']
expected_labels = set(mapping.keys())

ranking = parsed.get('ranking')
if not isinstance(ranking, list) or len(ranking) != len(expected_labels):
    print(f"  FAIL — ranking must be list of {len(expected_labels)}, got {type(ranking).__name__} len={len(ranking) if isinstance(ranking, list) else 'n/a'}", file=sys.stderr)
    sys.exit(1)

seen_labels = set()
seen_ranks = set()
for entry in ranking:
    if not isinstance(entry, dict):
        print(f"  FAIL — ranking entry not a dict: {entry!r}", file=sys.stderr)
        sys.exit(1)
    lbl = entry.get('label'); rk = entry.get('rank')
    if lbl not in expected_labels:
        print(f"  FAIL — unknown label {lbl!r} (expected one of {sorted(expected_labels)})", file=sys.stderr)
        sys.exit(1)
    if not isinstance(rk, int) or rk < 1 or rk > len(expected_labels):
        print(f"  FAIL — invalid rank {rk!r} for {lbl}", file=sys.stderr)
        sys.exit(1)
    if lbl in seen_labels:
        print(f"  FAIL — duplicate label {lbl}", file=sys.stderr)
        sys.exit(1)
    if rk in seen_ranks:
        print(f"  FAIL — duplicate rank {rk}", file=sys.stderr)
        sys.exit(1)
    seen_labels.add(lbl); seen_ranks.add(rk)

if seen_labels != expected_labels:
    print(f"  FAIL — missing labels: {expected_labels - seen_labels}", file=sys.stderr)
    sys.exit(1)

# Persist normalized output (sort by rank). Embed a provenance hash of the mapping
# file bytes — aggregator verifies this against the on-disk mapping at read time,
# detecting any post-judging mapping mutation (re-shuffle, accidental edit, etc.)
# regardless of file mtime.
parsed['ranking'] = sorted(ranking, key=lambda x: x['rank'])
parsed.setdefault('calibration_notes', '')
parsed.setdefault('blinding_concerns', '')
with open(map_p, 'rb') as _mf:
    parsed['mapping_sha256'] = hashlib.sha256(_mf.read()).hexdigest()

json.dump(parsed, open(out_p, 'w'), indent=2)
print(f"  ok — ranking written: {out_p}")
print(f"     top: {parsed['ranking'][0]['label']}  bottom: {parsed['ranking'][-1]['label']}")
if parsed['blinding_concerns'].strip():
    print(f"     [!] blinding_concerns: {parsed['blinding_concerns'][:200]}")
PY

if [ ! -s "$OUT_JSON" ]; then
  echo "comparative-rank opus1m: task=$TASK trial=t$TRIAL round=$ROUND  FAIL"
  exit 1
fi

echo "comparative-rank opus1m: task=$TASK trial=t$TRIAL round=$ROUND  ok"
