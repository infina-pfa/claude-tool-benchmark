#!/bin/bash
# Codex GPT-5.4 judge — combined review of all 3 phases in one call.
#
# Reproducibility note: `opencode run` does not expose --temperature or
# --sampler-seed. `--variant high` selects reasoning depth, not sampling
# determinism. Round-to-round σ (FINAL-REPORT §7) absorbs sampler variance;
# three-judge averaging is the primary mitigation.
set -uo pipefail
source "$(dirname "$0")/env.sh"

LABEL=${1:-}
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
OUT_FILE="$OUT_DIR/codex-judge.json"
mkdir -p "$OUT_DIR"

PROMPT=$("$SCRIPTS_DIR/generate-judge-prompt-combined.sh" "$LABEL" | sed 's/JUDGE_NAME/codex/g')

# Route through opencode with GPT-5.4 (avoids codex CLI hangs on large prompts)
/Users/randytran/.opencode/bin/opencode run --pure --model openai/gpt-5.4 --variant high "$PROMPT" > "$OUT_FILE.raw.txt" 2>/dev/null

python3 - "$OUT_FILE.raw.txt" "$OUT_FILE" <<'PY' 2>/dev/null
import json, re, sys
in_path, out_path = sys.argv[1], sys.argv[2]
try:
    text = open(in_path).read()
    text = re.sub(r'```json?\s*', '', text)
    text = re.sub(r'```', '', text)
    try:
        json.dump(json.loads(text.strip()), open(out_path, 'w'), indent=2)
    except json.JSONDecodeError:
        candidates = []
        depth = 0
        start = -1
        for i, ch in enumerate(text):
            if ch == '{':
                if depth == 0: start = i
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
                    break
            except json.JSONDecodeError:
                continue
except Exception:
    pass
PY

if [ -s "$OUT_FILE" ]; then
  echo "codex $LABEL: ok"
else
  echo "codex $LABEL: FAIL"
  exit 1
fi
