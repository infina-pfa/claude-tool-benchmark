#!/usr/bin/env python3
"""
Normalize judge JSON output to canonical dict-shape.

Accepts both:
  - schema_version=2 (array form): scores=[{id,score,why}, ...]   (v2 prompt 2026-04-27+)
  - legacy dict form:              scores={"1": N, ...}, rationales={"1": "why", ...}

Emits canonical:
  {
    "label": ...,
    "judge": ...,
    "schema_version": 1|2,
    "reasoning": ...,
    "scores":     {"1": N, ...},
    "rationales": {"1": "why", ...},
    "total":      <sum of scores — recomputed, ignoring any LLM-emitted total>,
    "max":        200,
    "notes":      ...
  }

Downstream tools (apply-r1-override.py, aggregate-results.sh) read the dict
form. Computing `total` here eliminates the LLM arithmetic drift §3c R5 cites
(GLM off-by-9, codex-or off-by-4).

Usage:
  python3 normalize-judge-json.py <text-content-with-embedded-json> <out_file> <judge_name> <label>

Reads `text` as the LLM raw text response (post code-fence strip), extracts the
LAST balanced JSON object containing a "scores" key, normalizes, writes to
out_file. Exits 0 on success, 1 if no valid JSON found.
"""

from __future__ import annotations

import json
import re
import sys


def _balanced_json_candidates(text: str) -> list[str]:
    out: list[str] = []
    depth = 0
    start = -1
    for i, ch in enumerate(text):
        if ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start >= 0:
                out.append(text[start : i + 1])
                start = -1
    return out


def _normalize(parsed: dict, judge_name: str, label: str) -> dict | None:
    scores_raw = parsed.get("scores")
    if scores_raw is None:
        return None

    scores: dict[str, int] = {}
    rationales: dict[str, str] = {}
    schema_version = 1

    if isinstance(scores_raw, list):
        # v2 array form
        schema_version = 2
        for item in scores_raw:
            if not isinstance(item, dict):
                continue
            iid = item.get("id")
            if iid is None:
                continue
            scores[str(iid)] = int(item.get("score", 0))
            why = item.get("why") or item.get("rationale") or ""
            if why:
                rationales[str(iid)] = str(why)
    elif isinstance(scores_raw, dict):
        # legacy dict form
        for k, v in scores_raw.items():
            if isinstance(v, dict):
                scores[str(k)] = int(v.get("score", 0))
                why = v.get("why") or v.get("rationale") or ""
                if why:
                    rationales[str(k)] = str(why)
            else:
                scores[str(k)] = int(v)
        # legacy parallel rationales map (v2-prompt rev1)
        for k, v in (parsed.get("rationales") or {}).items():
            rationales.setdefault(str(k), str(v))
    else:
        return None

    if not scores:
        return None

    total = sum(scores.values())
    return {
        "label": parsed.get("label") or label,
        "judge": parsed.get("judge") or judge_name,
        "schema_version": schema_version,
        "reasoning": parsed.get("reasoning", ""),
        "scores": scores,
        "rationales": rationales,
        "total": total,
        "max": int(parsed.get("max", 200)),
        "notes": parsed.get("notes", ""),
    }


def main() -> int:
    if len(sys.argv) < 5:
        print("usage: normalize-judge-json.py <text> <out_file> <judge_name> <label>", file=sys.stderr)
        return 1

    text = sys.argv[1]
    out_file = sys.argv[2]
    judge_name = sys.argv[3]
    label = sys.argv[4]

    text = re.sub(r"```json?\s*", "", text)
    text = re.sub(r"```", "", text)

    # Try whole text first; fall back to balanced-JSON candidates (last-first).
    snippets = [text.strip()] + list(reversed(_balanced_json_candidates(text)))
    for snippet in snippets:
        try:
            parsed = json.loads(snippet)
        except json.JSONDecodeError:
            continue
        if not isinstance(parsed, dict):
            continue
        normalized = _normalize(parsed, judge_name, label)
        if normalized is None:
            continue
        with open(out_file, "w") as f:
            json.dump(normalized, f, indent=2)
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
