#!/bin/bash
# Manual benchmark launcher — interactive claude session with auto-captured
# timing, token, and cost metrics. This is the ONLY supported benchmark
# launcher — the prior bench-auto.sh has been deprecated
# (see scripts/.bench-auto.sh.deprecated-20260419).
#
# Usage: ./manual-bench.sh <tool> <trial>
#
# Flow:
#   1. Verify clean state.
#   2. Record start timestamp + session metadata.
#   3. Print the tool's initial prompt (copy/paste target).
#   4. Launch `claude` interactively with the right env + CLAUDE_CONFIG_DIR.
#      For `pure` we pass --permission-mode plan.
#   5. When you exit claude (Ctrl-D, /exit, or /quit), record end timestamp.
#   6. Copy session JSONL logs from the config dir into results/<tool>/t<trial>/session-logs/.
#   7. Parse the session JSONL to extract tokens/cost/turns — writes phase1-metrics.json.
#   8. Print next-step reminders (capture SHA, collect metrics, etc.).

set -uo pipefail
source "$(dirname "$0")/env.sh"

TOOL=${1:-}
TRIAL=${2:-}
if [ -z "$TOOL" ] || [ -z "$TRIAL" ]; then
  echo "Usage: ./manual-bench.sh <tool> <trial>"
  echo "Tools: ${TOOLS[*]}"
  echo "Trials: 1 2 3"
  exit 1
fi

RESULT_DIR="$RESULTS_DIR/$TOOL/t${TRIAL}"
CLONE_DIR="$RUNS_DIR/${TOOL}-t${TRIAL}"
TOOL_CONFIG_DIR="$CONFIG_DIR/${TOOL}-t${TRIAL}"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

# Pinned-CLI gate: refuse trial if $BENCH_CLAUDE_BIN does not match the
# lockfile target. Override with BENCH_SKIP_CLI_PIN=1 (NOT recommended;
# breaks cohort homogeneity).
if [ -z "${BENCH_SKIP_CLI_PIN:-}" ]; then
  if [ ! -x "$BENCH_CLAUDE_BIN" ]; then
    echo "ERROR: BENCH_CLAUDE_BIN ($BENCH_CLAUDE_BIN) is not executable." >&2
    echo "Install with: npm i --prefix ~/.local/bench-claude @anthropic-ai/claude-code@<lockfile-version>" >&2
    exit 1
  fi
  EXPECTED_CLI=$(python3 -c "import json; print(json.load(open('$BENCH_HOME/versions.lock.json'))['claude_cli']['version'])" 2>/dev/null)
  ACTUAL_CLI=$("$BENCH_CLAUDE_BIN" --version 2>/dev/null | awk '{print $1}')
  if [ -z "$EXPECTED_CLI" ] || [ -z "$ACTUAL_CLI" ] || [ "$EXPECTED_CLI" != "$ACTUAL_CLI" ]; then
    echo "ERROR: claude CLI version mismatch — pinned binary $ACTUAL_CLI, lockfile expects $EXPECTED_CLI." >&2
    echo "  bin: $BENCH_CLAUDE_BIN" >&2
    echo "  override: BENCH_SKIP_CLI_PIN=1 (not recommended)" >&2
    exit 1
  fi
fi

mkdir -p "$RESULT_DIR/sessions" "$RESULT_DIR/session-logs"

# Wipe stale claude session state from a prior run of this trial. If we
# don't, /resume inside the bench session offers the previous trial's
# transcript and the operator can accidentally continue old work.
# Stateful artifacts: projects/ (session JSONLs), sessions/, shell-snapshots/,
# history.jsonl. Plugin state (plugins/, .omc/, _bmad/, .claude/) is preserved.
if [ -d "$TOOL_CONFIG_DIR" ]; then
  rm -rf "$TOOL_CONFIG_DIR"/projects \
         "$TOOL_CONFIG_DIR"/sessions \
         "$TOOL_CONFIG_DIR"/shell-snapshots \
         "$TOOL_CONFIG_DIR"/history.jsonl
fi

# Pre-run verification
"$SCRIPTS_DIR/verify-clean.sh" "$TOOL" "$TRIAL"
if [ $? -ne 0 ]; then
  echo "Pre-run verification failed. Fix issues before starting." >&2
  exit 1
fi

# Decide whether to enable plan mode (for tools without their own planning workflow)
# Note: gstack deliberately excluded — its /ship workflow already runs an eng review
# gate; we evaluate gstack on its native surface without forcing Claude's plan mode.
PLAN_MODE_FLAG=""
case "$TOOL" in
  pure)
    PLAN_MODE_FLAG="--permission-mode plan"
    ;;
esac

# Shared task block — task-aware, same for every tool within a task
case "$TASK" in
  feature)
    read -r -d '' SHARED_TASK <<'TASK_EOF' || true
Implement Mode 2 CD Batch for TD-CD per $PRD_PATH.
Follow existing Mode 1 patterns.
TASK_EOF
    ;;
  bugfix)
    read -r -d '' SHARED_TASK <<'TASK_EOF' || true
Fix the bug described in docs/benchmark/TASK.md.
TASK_EOF
    ;;
  refactor)
    read -r -d '' SHARED_TASK <<'TASK_EOF' || true
Do the refactor described in docs/benchmark/TASK.md.
TASK_EOF
    ;;
  *)
    echo "ERROR: manual-bench.sh has no prompt template for TASK=$TASK" >&2
    exit 1
    ;;
esac

# The heredocs above use a quoted delimiter ('TASK_EOF') so $PRD_PATH is
# captured as a literal. Expand it here — we want the prompt pasted into
# claude to carry the real PRD path (matching historical trials), not the
# literal string "$PRD_PATH".
SHARED_TASK="${SHARED_TASK//\$PRD_PATH/$PRD_PATH}"

# Per-tool prompt (prefix is tool-specific; shared task block appended)
case "$TOOL" in
  pure)
    PROMPT="$SHARED_TASK"
    ;;
  claudekit)
    # Canonical plan→cook flow with leading-slash dispatch.
    #
    # Earlier prose form ("Use /ck:plan to scope...") matched the archived
    # t1 operator verbatim but relies on the model autonomously invoking the
    # Skill tool. Apr 23 canary showed zero Skill calls (vs. 1 in Apr 15
    # archive) — either model variance or Claude Code version drift made
    # that form unreliable. Leading-slash form forces the command handler
    # to dispatch the skill directly, matching the pattern used for OMC
    # (/oh-my-claudecode:autopilot).
    #
    # Scope note: original t1 used plan→cook chained (fidelity restore);
    # original t2/t3/t4, bugfix t1/t2, refactor t1/t2 used /ck:cook --auto
    # alone. The 2026-04-23 canonical-activation rerun fires only /ck-plan
    # as the explicit entry point — the operator manually types
    # /ck:cook --auto at the interactive prompt once the plan file(s) land.
    # Rationale: autonomous model re-dispatch of the second slash command
    # was unreliable (prior session-log audits showed /ck:cook was treated
    # as prose and never re-fired). Keep the operator in the loop for the
    # plan→cook transition; leave the rest of the run on --auto.
    PROMPT="/ck-plan \"$SHARED_TASK\""
    ;;
  superpower)
    # Single skill trigger across all tasks: /superpowers:brainstorming is the
    # plugin's documented entry gate for "creative work" (build, fix, refactor).
    # The plugin chains internally to writing-plans / executing-plans /
    # systematic-debugging / verification as needed — we don't pre-select a
    # downstream skill (per 2026-04-25 user decision; supersedes the prior
    # bugfix-specific systematic-debugging + verification suffix).
    PROMPT="/superpowers:brainstorming

$SHARED_TASK"
    ;;
  bmad)
    PROMPT="/bmad-quick-dev \"$SHARED_TASK\""
    ;;
  omc)
    OMC_TWO_MSG=1
    PROMPT="/oh-my-claudecode:omc-setup"
    ;;
  gstack)
    case "$TASK" in
      bugfix)
        PROMPT="/investigate \"$SHARED_TASK\""
        ;;
      *)
        # /autoplan auto-discovers the PRD from the repo — no task arg needed.
        PROMPT="/autoplan"
        ;;
    esac
    ;;
  compound)
    PROMPT="/compound-engineering:lfg \"$SHARED_TASK\""
    ;;
  ecc)
    PROMPT="/everything-claude-code:plan \"$SHARED_TASK\""
    ;;
  *)
    PROMPT="$SHARED_TASK"
    ;;
esac

# Print copy/paste block + launch reminder
cat <<HEADER

========================================
  Manual Benchmark: $TOOL trial $TRIAL
  Config: $TOOL_CONFIG_DIR
  Clone:  $CLONE_DIR
  Plan mode: ${PLAN_MODE_FLAG:-(off — tool has its own planning)}
  Effort:    ${BENCH_EFFORT:-medium} (forced via CLAUDE_CODE_EFFORT_LEVEL)
========================================

HEADER

if [ "${OMC_TWO_MSG:-}" = "1" ]; then
  echo "----- MESSAGE 1: PASTE THIS FIRST -----"
  echo "/oh-my-claudecode:omc-setup"
  echo "----- END MESSAGE 1 -----"
  echo ""
  echo "Wait for setup to complete, then paste:"
  echo ""
  echo "----- MESSAGE 2: PASTE AFTER SETUP -----"
  printf '%s\n' "/oh-my-claudecode:ralplan \"$SHARED_TASK\""
  echo "----- END MESSAGE 2 -----"
  echo ""
  echo "After ralplan finishes the consensus plan, manually trigger execution"
  echo "by typing: /oh-my-claudecode:team"
  echo "(team auto-decomposes the plan and spawns workers — no extra args needed)"
else
  echo "----- COPY THIS PROMPT INTO CLAUDE -----"
  printf '%s\n' "$PROMPT"
  echo "----- END PROMPT -----"
fi

cat <<FOOTER

Exit claude (Ctrl-D or /exit) when the tool finishes and has committed the final code.

Press ENTER to launch claude...
FOOTER
read -r _

# Save the prompt alongside results so we have a record per trial
mkdir -p "$RESULT_DIR"
if [ "${OMC_TWO_MSG:-}" = "1" ]; then
  printf 'MSG1: /oh-my-claudecode:omc-setup\nMSG2: /oh-my-claudecode:ralplan "%s"\nMSG3 (operator-typed): /oh-my-claudecode:team\n' "$SHARED_TASK" > "$RESULT_DIR/phase1-prompt.txt"
else
  printf '%s\n' "$PROMPT" > "$RESULT_DIR/phase1-prompt.txt"
fi

# Start metadata
START_EPOCH=$(date +%s)
START_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
cat > "$RESULT_DIR/sessions/session-$TIMESTAMP.meta.json" <<EOF
{
  "tool": "$TOOL",
  "trial": $TRIAL,
  "mode": "manual-oneshot",
  "plan_mode": $( [ -n "$PLAN_MODE_FLAG" ] && echo 'true' || echo 'false' ),
  "started_at": "$START_ISO",
  "clone_dir": "$CLONE_DIR",
  "base_commit": "$(git -C "$CLONE_DIR" log --oneline -1)",
  "os": "$(uname -srm)",
  "node_version": "$(node -v 2>/dev/null || echo 'N/A')",
  "claude_code_version": "$("$BENCH_CLAUDE_BIN" --version 2>/dev/null || echo 'unknown')",
  "model": "claude-opus-4-7"
}
EOF

# Initialize exit state; the EXIT trap below guarantees capture even if the
# interactive session or this script is killed mid-flight.
EXIT_CODE=0
CAPTURE_DONE=0

capture_and_cleanup() {
  [ "$CAPTURE_DONE" = "1" ] && return
  CAPTURE_DONE=1

  local end_epoch end_iso wall_secs
  end_epoch=$(date +%s)
  end_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  wall_secs=$((end_epoch - START_EPOCH))

  cd "$BENCH_HOME" 2>/dev/null || true

  echo ""
  echo "=== Session ended after ${wall_secs}s (exit $EXIT_CODE) ==="

  # Derive claude-config project slug from the actual clone dir (task-aware).
  local proj_slug="${CLONE_DIR//\//-}"
  local proj_dir="$TOOL_CONFIG_DIR/projects/$proj_slug"
  if [ -d "$proj_dir" ]; then
    mkdir -p "$RESULT_DIR/session-logs/subagents"
    find "$proj_dir" -maxdepth 1 -name "*.jsonl" -newer "$RESULT_DIR/sessions/session-$TIMESTAMP.meta.json" \
      -exec cp {} "$RESULT_DIR/session-logs/" \; 2>/dev/null
    find "$proj_dir" -path "*/subagents/*.jsonl" -newer "$RESULT_DIR/sessions/session-$TIMESTAMP.meta.json" \
      -exec cp {} "$RESULT_DIR/session-logs/subagents/" \; 2>/dev/null
    local log_count
    log_count=$(find "$RESULT_DIR/session-logs" -name "*.jsonl" 2>/dev/null | wc -l | tr -d ' ')
    echo "Copied $log_count session log file(s) from $proj_dir"
  else
    echo "WARNING: No session logs found at $proj_dir"
  fi

  # Parse session JSONLs for token/cost/turn totals + session-based wall time.
  # NOTE: aggregator extracted to scripts/aggregate-phase1.py (single source of truth).
  # Inline heredoc retained below for legacy reference; the call below short-circuits it.
  python3 "$BENCH_HOME/scripts/aggregate-phase1.py" \
    "$RESULT_DIR/session-logs" "$RESULT_DIR/phase1-metrics.json" \
    "$TOOL" "$TRIAL" "$wall_secs" "$EXIT_CODE"
  : <<'PY'
import json, os, sys, glob
from datetime import datetime

logs_dir, out_path, tool, trial, wall_secs, exit_code = sys.argv[1:7]
trial = int(trial); wall_secs = int(wall_secs); exit_code = int(exit_code)

totals = {
    'input_tokens': 0,
    'output_tokens': 0,
    'cache_creation_tokens': 0,
    'cache_read_tokens': 0,
    'cost_usd': 0.0,
    'num_turns': 0,
    'session_ids': set(),
    'main_input_tokens': 0,
    'main_output_tokens': 0,
    'main_cache_creation_tokens': 0,
    'main_cache_read_tokens': 0,
    'subagent_input_tokens': 0,
    'subagent_output_tokens': 0,
    'subagent_cache_creation_tokens': 0,
    'subagent_cache_read_tokens': 0,
    'subagent_count': 0,
}

# Opus 4.7 pricing (USD per 1M tokens, Anthropic 2026 rates)
PRICE_OPUS_47 = {
    'input': 15.0,
    'output': 75.0,
    'cache_creation': 18.75,
    'cache_read': 1.50,
}

def parse_iso(ts):
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts.replace('Z', '+00:00'))
    except (ValueError, AttributeError):
        return None

# Load all events (timestamped) from top-level + subagents JSONLs.
# Subagents (Agent / team workers) bill independent context; including them
# is required for tools that fan out (omc team, autopilot, ralph, etc.).
all_events = []
main_files = sorted(glob.glob(os.path.join(logs_dir, '*.jsonl')))
sub_files = sorted(glob.glob(os.path.join(logs_dir, 'subagents', '*.jsonl')))
totals['subagent_count'] = len(sub_files)
for jf in main_files + sub_files:
    is_sub = jf in sub_files
    prefix = 'subagent_' if is_sub else 'main_'
    try:
        with open(jf) as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    ev = json.loads(line)
                except json.JSONDecodeError:
                    continue
                sid = ev.get('sessionId') or ev.get('session_id')
                if sid:
                    totals['session_ids'].add(sid)
                ts = parse_iso(ev.get('timestamp') or ev.get('time') or ev.get('createdAt'))
                if ts:
                    all_events.append((ts, ev))
                if ev.get('type') == 'assistant':
                    msg = ev.get('message', {}) or {}
                    usage = msg.get('usage', {}) or {}
                    inp = int(usage.get('input_tokens', 0) or 0)
                    out = int(usage.get('output_tokens', 0) or 0)
                    cc  = int(usage.get('cache_creation_input_tokens', 0) or 0)
                    cr  = int(usage.get('cache_read_input_tokens', 0) or 0)
                    totals['input_tokens']           += inp
                    totals['output_tokens']          += out
                    totals['cache_creation_tokens']  += cc
                    totals['cache_read_tokens']      += cr
                    totals[prefix + 'input_tokens']           += inp
                    totals[prefix + 'output_tokens']          += out
                    totals[prefix + 'cache_creation_tokens']  += cc
                    totals[prefix + 'cache_read_tokens']      += cr
                    if not is_sub:
                        totals['num_turns'] += 1
                cost = ev.get('costUSD') or ev.get('total_cost_usd') or ev.get('cost_usd')
                if cost:
                    try:
                        totals['cost_usd'] += float(cost)
                    except (TypeError, ValueError):
                        pass
    except Exception as e:
        print(f"  Warning: could not parse {jf}: {e}", file=sys.stderr)

# Derive cost from tokens when CLI did not emit costUSD (Pro plan path).
cost_emitted = totals['cost_usd']
cost_derived = (
    totals['input_tokens']           * PRICE_OPUS_47['input']          / 1_000_000
  + totals['output_tokens']          * PRICE_OPUS_47['output']         / 1_000_000
  + totals['cache_creation_tokens']  * PRICE_OPUS_47['cache_creation'] / 1_000_000
  + totals['cache_read_tokens']      * PRICE_OPUS_47['cache_read']     / 1_000_000
)
if cost_emitted > 0:
    totals['cost_source'] = 'emitted'
else:
    totals['cost_usd'] = cost_derived
    totals['cost_source'] = 'derived'
totals['cost_derived_usd'] = round(cost_derived, 6)
totals['cost_emitted_usd'] = round(cost_emitted, 6)

all_events.sort(key=lambda x: x[0])
totals['session_ids'] = sorted(totals['session_ids'])

# Session span (first → last event)
span_secs = None
session_start = session_end = None
if all_events:
    first_ts = all_events[0][0]
    last_ts = all_events[-1][0]
    span_secs = int((last_ts - first_ts).total_seconds())
    session_start = first_ts.strftime('%Y-%m-%dT%H:%M:%SZ')
    session_end = last_ts.strftime('%Y-%m-%dT%H:%M:%SZ')

# Idle gaps to subtract from span:
#   (a) ExitPlanMode approval — gap between assistant tool_use(ExitPlanMode)
#       and the matching user tool_result. Claude Code blocks for user approval.
#   (b) User typing — gap preceding any real user text message. Excludes
#       skill-context injections (which arrive at gap≈0, so don't materially
#       affect the sum) and tool_result events (which are tool execution time,
#       not user idle).
approval_idle = 0
user_typing_idle = 0
pending_approval_uuids = set()

def is_real_user_text(ev):
    if ev.get('type') != 'user':
        return False
    # Tool results come in as user events but carry sourceToolAssistantUUID
    if 'sourceToolAssistantUUID' in ev:
        return False
    msg = ev.get('message', {}) or {}
    content = msg.get('content', [])
    if isinstance(content, str):
        return True
    if isinstance(content, list):
        for c in content:
            if isinstance(c, dict) and c.get('type') == 'tool_result':
                return False
        return True
    return False

for i, (ts, ev) in enumerate(all_events):
    if ev.get('type') == 'assistant':
        msg = ev.get('message', {}) or {}
        content = msg.get('content', [])
        if isinstance(content, list):
            for c in content:
                if isinstance(c, dict) and c.get('type') == 'tool_use' and c.get('name') == 'ExitPlanMode':
                    pending_approval_uuids.add((c.get('id'), ts))
    elif ev.get('type') == 'user':
        msg = ev.get('message', {}) or {}
        content = msg.get('content', [])
        if isinstance(content, list):
            for c in content:
                if isinstance(c, dict) and c.get('type') == 'tool_result':
                    tu_id = c.get('tool_use_id')
                    for pending in list(pending_approval_uuids):
                        if pending[0] == tu_id:
                            approval_idle += int((ts - pending[1]).total_seconds())
                            pending_approval_uuids.discard(pending)
        # User typing: gap between prev event and this real user message
        if is_real_user_text(ev) and i > 0:
            prev_ts = all_events[i-1][0]
            user_typing_idle += int((ts - prev_ts).total_seconds())

total_idle = approval_idle + user_typing_idle
active_secs = (span_secs - total_idle) if span_secs is not None else None

metrics = {
    'tool': tool,
    'trial': trial,
    'phase': 1,
    'phase_name': 'OneShot',
    'mode': 'manual-oneshot',
    # Primary wall time = active work time (matches Claude Code "Worked for" UI)
    'wall_seconds': active_secs if active_secs is not None else wall_secs,
    'wall_seconds_active': active_secs,        # span minus all idle (approval + user typing)
    'wall_seconds_span': span_secs,            # first → last event
    'wall_seconds_shell': wall_secs,           # ENTER → exit (includes user prep)
    'approval_idle_seconds': approval_idle,
    'user_typing_idle_seconds': user_typing_idle,
    'session_start': session_start,
    'session_end': session_end,
    'cost_usd': round(totals['cost_usd'], 6),
    'cost_source': totals['cost_source'],
    'cost_emitted_usd': totals['cost_emitted_usd'],
    'cost_derived_usd': totals['cost_derived_usd'],
    'input_tokens': totals['input_tokens'],
    'output_tokens': totals['output_tokens'],
    'cache_creation_tokens': totals['cache_creation_tokens'],
    'cache_read_tokens': totals['cache_read_tokens'],
    'main_input_tokens': totals['main_input_tokens'],
    'main_output_tokens': totals['main_output_tokens'],
    'main_cache_creation_tokens': totals['main_cache_creation_tokens'],
    'main_cache_read_tokens': totals['main_cache_read_tokens'],
    'subagent_input_tokens': totals['subagent_input_tokens'],
    'subagent_output_tokens': totals['subagent_output_tokens'],
    'subagent_cache_creation_tokens': totals['subagent_cache_creation_tokens'],
    'subagent_cache_read_tokens': totals['subagent_cache_read_tokens'],
    'subagent_count': totals['subagent_count'],
    'num_turns': totals['num_turns'],
    'session_ids': totals['session_ids'],
    'session_log_files': [os.path.basename(f) for f in main_files] +
                         ['subagents/' + os.path.basename(f) for f in sub_files],
    'exit_code': exit_code,
}
with open(out_path, 'w') as fh:
    json.dump(metrics, fh, indent=2)

print(f"Tokens:     in={totals['input_tokens']} out={totals['output_tokens']} "
      f"cache_create={totals['cache_creation_tokens']} cache_read={totals['cache_read_tokens']}")
print(f"  main:     in={totals['main_input_tokens']} out={totals['main_output_tokens']} "
      f"cache_create={totals['main_cache_creation_tokens']} cache_read={totals['main_cache_read_tokens']}")
print(f"  subagent: in={totals['subagent_input_tokens']} out={totals['subagent_output_tokens']} "
      f"cache_create={totals['subagent_cache_creation_tokens']} cache_read={totals['subagent_cache_read_tokens']} "
      f"({totals['subagent_count']} subagent files)")
print(f"Cost:       ${totals['cost_usd']:.4f} ({totals['cost_source']}; emitted=${totals['cost_emitted_usd']:.4f} derived=${totals['cost_derived_usd']:.4f})")
print(f"Turns:      {totals['num_turns']}")
print(f"Wall:       active={active_secs}s  span={span_secs}s  shell={wall_secs}s  (idle: approval={approval_idle}s, user_typing={user_typing_idle}s)")
print(f"Sessions:   {len(totals['session_ids'])} ({', '.join(totals['session_ids'][:3]) or 'none detected'})")
print(f"Wrote:      {out_path}")
PY

  # Update session metadata with end time.
  python3 - "$RESULT_DIR/sessions/session-$TIMESTAMP.meta.json" "$end_iso" "$EXIT_CODE" "$wall_secs" <<'PY'
import json, sys
path, end_iso, exit_code, wall = sys.argv[1:5]
with open(path) as f:
    d = json.load(f)
d['ended_at'] = end_iso
d['exit_code'] = int(exit_code)
d['wall_seconds'] = int(wall)
with open(path, 'w') as f:
    json.dump(d, f, indent=2)
PY

  echo ""
  echo "=== Manual benchmark complete: $TOOL trial $TRIAL ==="
  echo ""
  echo "Last commit in clone:"
  git -C "$CLONE_DIR" log --oneline -1 2>&1 | sed 's/^/  /'
  echo ""

  if [ -n "${SKIP_AUTO_COLLECT:-}" ]; then
    echo "(SKIP_AUTO_COLLECT set — run manually:"
    echo "   TASK=$TASK ./scripts/collect-metrics.sh $TOOL $TRIAL )"
  else
    echo "----- AUTO-RUNNING collect-metrics ($TOOL t$TRIAL) -----"
    cd "$BENCH_HOME" && TASK=$TASK ./scripts/collect-metrics.sh "$TOOL" "$TRIAL" \
      || echo "collect-metrics exited non-zero — re-run manually if needed."
    echo "----- collect-metrics done -----"
  fi
  echo ""
  echo "After all trials complete, run blind-eval setup + judging in batch:"
  echo "  ./scripts/blind-eval-setup.sh && ./scripts/judge-all.sh <label>"
}

trap 'capture_and_cleanup' EXIT

# Launch interactive claude with clean env.
cd "$CLONE_DIR"
env -i \
  HOME=$BENCH_HOME \
  PATH=/Users/randytran/.local/bin:/Users/randytran/.opencode/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$(dirname "$(which node)") \
  CLAUDE_CONFIG_DIR=$TOOL_CONFIG_DIR \
  CLAUDE_CODE_EFFORT_LEVEL=${BENCH_EFFORT:-medium} \
  TERM=${TERM:-xterm-256color} \
  USER=$USER \
  LANG=${LANG:-en_US.UTF-8} \
  "$BENCH_CLAUDE_BIN" --model claude-opus-4-7 --effort ${BENCH_EFFORT:-medium} --dangerously-skip-permissions $PLAN_MODE_FLAG
EXIT_CODE=$?
