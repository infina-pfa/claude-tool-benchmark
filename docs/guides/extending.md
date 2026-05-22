# Extending — Add a new tool or a new judge

The benchmark is built to be forked. The scripts are shell, the aggregation is ~500 lines of Python + bash, every artifact is on disk. No database, no service. This guide walks through the two extension paths.

---

## Add a new tool

### 1. Use the scaffolding script

```bash
./scripts/add-tool.sh --dry-run     # preview the edits
./scripts/add-tool.sh               # interactive: name, install command, entry-point slash command
```

The script interactively wires your tool into:

- `scripts/env.sh` — appends to the `TOOLS` array.
- `scripts/setup-tool-config.sh` — inserts the per-tool install block (plugin marketplace, git clone, or npm install).
- `scripts/create-clones.sh` — adds `.gitignore` safety patterns (so your tool's state files stay out of the benchmark commits).
- `versions.lock.json` `tools.<name>` — bump the count and pin the version + SHA.

It `bash -n` checks every modified script and can optionally run `create-clones.sh` to provision trial clones immediately.

### 2. Decide plan-mode vs. native-planning

| Your tool has … | Configure it as |
|---|---|
| A native planning/review workflow (e.g. `/mytool:plan`, `/mytool:cook`) | Just a `PROMPT=` case. No plan-mode flag. |
| A mixed mode (`plan` for feature/refactor, `build-fix` for bugfix) | A per-task `case "$TASK"` inside your tool's branch. See `ecc)` for the template. |

**Do not stack ceremonies.** If your tool runs its own eng-review gate (like `gstack`'s `/ship`), don't also set `--permission-mode plan`. The benchmark excludes `gstack` from plan-mode for exactly this reason.

### 3. Run the cohort

```bash
for trial in 1 2 3 4 5; do
  TASK=feature  ./scripts/manual-bench.sh <yourtool> $trial
  TASK=bugfix   ./scripts/manual-bench.sh <yourtool> $trial
  TASK=refactor ./scripts/manual-bench.sh <yourtool> $trial
done
```

**Cohort symmetry:** if you re-run any trial for your tool, you must re-run it for all 8 tools in the same cohort. Judge-side artifacts must all come from the same trial SHA. `scripts/audit-cohort-symmetry.py` exits non-zero if this is violated. See [`../../CLAUDE.md`](../../CLAUDE.md#rerun-protocol-pre-registered) for the rerun protocol (valid triggers, archival procedure).

### 4. Judge

Judging needs no changes. `blind-eval-setup.sh` auto-discovers your runs from `results/<task>/<tool>/t<N>/commits.txt` and blind-labels them in the rotation.

```bash
TASK=feature ./scripts/blind-eval-setup.sh
TASK=feature ./scripts/judge-all.sh <label>     # 5-judge panel, single round
# Repeat for bugfix and refactor
TASK=feature ./scripts/aggregate-results.sh
```

### 5. Verify the cohort

```bash
python3 scripts/audit-cohort-symmetry.py
TASK=feature  ./scripts/aggregate-results.sh
TASK=bugfix   ./scripts/aggregate-results.sh
TASK=refactor ./scripts/aggregate-results.sh
```

Your tool now appears in `results/<task>/final-report.md` (per-tool weighted-mean ranking with σ decomposition) and the landing page bench-data block.

### 6. Write the tool profile

Add `docs/tools/<yourtool>.md` following the [template in this folder](../tools/). Sections: Upstream, Performance, Mechanism, How this benchmark invoked it, What actually happened in the transcripts (per task), Why it ranked where it did, Strengths & failure modes, References. Keep it transcript-grounded.

---

## Add a new judge

Judges are OpenCode CLI sessions (for `grok420`, `glm51`, `mimo25pro`), Claude Code sessions (for `opus`), or direct `/v1/responses` HTTP calls (for `gpt54pro`). They receive a fully-inlined prompt and return structured JSON scores. No tool access, no retrieval, no internet.

### 1. Copy the closest existing judge

```bash
cp scripts/judge-opus.sh scripts/judge-<yourjudge>.sh        # Claude-CLI shape
# or
cp scripts/judge-grok420.sh scripts/judge-<yourjudge>.sh     # OpenRouter shape
# or
cp scripts/judge-gpt54pro.sh scripts/judge-<yourjudge>.sh    # OpenAI /v1/responses shape
```

Pick the matching shape based on which API route your judge will use.

### 2. Edit the judge script

Update:
- **Model ID.** The exact string your CLI / API accepts.
- **Sampler settings.** Document where temperature/seed are pinned and where they aren't (most providers don't expose both). See `scripts/judge-opus.sh` header for the template.
- **Reasoning mode.** If your judge supports reasoning modes, pin it explicitly and document in the header.

### 3. Vet the judge on one round before committing it

```bash
TASK=refactor ROUND=sanitycheck ./scripts/judge-<yourjudge>.sh Alpha
cat results/refactor/_blind-eval/Alpha/roundsanitycheck/<yourjudge>-judge.json
```

Check: does the JSON validate against `scripts/judge-schema-v2.json`? Are the rubric items all scored 0-10? Does the reasoning block look coherent? If any judge returns malformed JSON more than once in five rounds, retire it.

### 4. Pre-register the weight

The panel is 5-judge with weights in `versions.lock.json` `judges.*.weight`. Decide:

- **Replace one existing judge.** Add your judge with the outgoing judge's weight; move the retired judge to `judges_retired`. Document the retirement reason in the lockfile's `_comment` block.
- **Extend to 6-judge.** Pick a pre-registered weight and document the rationale. `scripts/aggregate-results.sh` reads weights generically, so any 0..N-judge panel with declared weights works; just ensure every judge has judged every trial at least once.

The aggregator is forward-compatible with asymmetric per-judge `n` (missing judges drop out of both numerator and denominator).

### 5. Re-run the cohort aggregations

```bash
TASK=feature  ./scripts/aggregate-results.sh
TASK=bugfix   ./scripts/aggregate-results.sh
TASK=refactor ./scripts/aggregate-results.sh
```

### 6. Document the new judge

In `versions.lock.json` `judges.<name>` — model id, route, temperature setting, vendor, weight, and a brief justification in `_weight_comment`. In `docs/tools/README.md` (or a new `docs/tools/judges.md`) — cost and speed per round. A judge that costs 10× but only nudges the cohort mean by < 1 weighted point is a bad addition.

---

## Checklist before opening a PR

### New tool
- [ ] `add-tool.sh --dry-run` preview matches intent
- [ ] `scripts/env.sh` TOOLS array includes the new tool
- [ ] `versions.lock.json` `tools.<name>` pins version + SHA
- [ ] `config/<task>/<tool>-t<N>/` populated cleanly for N=1..5 across all 3 tasks
- [ ] All 15 runs (3 tasks × 5 trials) complete with `commits.txt`, `auto-metrics.json`, `sessions/*.meta.json`
- [ ] All 5 judges completed on every label across all 3 rounds (label root + `round1/` + `round2/` per artifact)
- [ ] `audit-cohort-symmetry.py` exits 0
- [ ] `aggregate-results.sh` re-runs without error on all 3 tasks; new tool appears in every `final-report.md`
- [ ] `docs/tools/<tool>.md` written — Upstream, Performance, Mechanism, Transcripts, Why-it-ranked, Strengths, Failure modes
- [ ] Landing page bench-data block (`docs/index.html`) updated with new tool's entries across all 3 tasks
- [ ] Previews re-rendered via `node tooling/render-md-previews.mjs`

### New judge
- [ ] `scripts/judge-<name>.sh` written, header documents model + sampler-limitation disclaimer
- [ ] Sanity round produces valid JSON with all 20 rubric items scored 0-10
- [ ] `versions.lock.json` `judges.<name>` entry with weight + retirement-or-extension rationale
- [ ] `aggregate-results.sh` re-runs cleanly with the new panel
- [ ] New judge's cost + speed characterized

---

See [`../../PAPER.md` §1](../../PAPER.md#1-methodology) for the canonical methodology reference and [`verification.md`](verification.md) for the "how do I independently verify a claim?" walkthrough.
