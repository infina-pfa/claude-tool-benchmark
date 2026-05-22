# Pre-publish rerun runbook

## Patches applied to the harness

The re-publish pass applied the following script-level fixes; the runbook
below assumes they are in place.

- `scripts/apply-r1-override.py` —
  - **Item 16 field**: reads `tests_core_failed`, matching the Mode-1 rubric wording.
  - **Item 20 added** to the `feature` lock list with the same formula the
    judge prompt uses: `s20 = 10 if lines_removed == 0 else max(0, 10 - ceil(lines_removed / 10))`.
  - **`scores_pre_r1` snapshot is now always written** on first sweep
    (previously only written when the override changed at least one item, so
    files where the LLM happened to be correct silently lacked the audit
    trail).
- `scripts/blind-eval-setup.sh` —
  - Path-level excludes extended with `docs/bmad/**`, `.superpowers/**`,
    `.compound-engineering/**`, `.ecc/**`.
  - Awk content-scrub list extended with `plans/`, `research/` and the new
    tool-state dirs above.
  - **`auto-metrics.json` anonymisation**: `plugin_versions` and
    `collected_at` are stripped before the file lands under `_blind-eval/`
    (both are identity fingerprints).
- `scripts/aggregate-results.sh` —
  - Idempotent **R1 sweep** runs before every aggregation, closing the
    single-judge-retry bypass orchestration gap.
  - σ decomposition: `within_σ` (trial-to-trial within-judge noise) and `between_σ`
    (judge base-rate spread) are emitted alongside pooled σ.
  - Cohort-span hours and weight pre-registration date are surfaced in the
    Caveats block.
- `versions.lock.json` — `judges.*.weight` block added with the pre-registered
  3 / 2 / 1 / 1 / 1 scheme; `_weight_comment` documents the registration
  date (2026-05-12).
- `scripts/env.sh` — `BENCH_COMMIT` for all three tasks switched from 7-char
  short SHAs to full 40-char SHAs to remove ambiguity.

After applying these patches, regenerate the six leak-fix re-judge labels
(Grove, Delta, Mike, Xray, November, Quebec — all feature) on clean diffs:

```bash
# from the repo root
TASK=feature ./scripts/blind-eval-setup.sh
TASK=feature ./scripts/judge-all.sh Grove Delta Mike Xray November Quebec
TASK=feature  ./scripts/aggregate-results.sh
TASK=bugfix   ./scripts/aggregate-results.sh
TASK=refactor ./scripts/aggregate-results.sh
```

Verify `scores_pre_r1` coverage across the corpus (expect 1800 / 1800):

```bash
python3 -c "
import json, pathlib
files = list(pathlib.Path('results').rglob('_blind-eval/*/[!.]*-judge.json'))
files = [f for f in files if '_archive' not in f.parts and 'request' not in f.name and 'raw' not in f.name]
total = len(files); with_snap = sum(1 for f in files if 'scores_pre_r1' in json.loads(f.read_text()))
print(f'{with_snap}/{total} files carry scores_pre_r1')
"
```

Verify no fingerprint leaks:

```bash
grep -rlE "\.omc/|_bmad-output/|docs/bmad/|\.superpowers/|\.compound-engineering/|\.ecc/|CLAUDE\.md\.original|plugin_versions" \
  results/{,bugfix/,refactor/}_blind-eval/*/{implementation-diff.patch,auto-metrics.json} 2>/dev/null \
  | grep -v "\.pre-" \
  | head
# Expect: empty.
```

---
