#!/usr/bin/env python3
# Aggregate Phase-1 OneShot trial metrics from Claude Code session JSONLs.
# Reads main + subagent jsonl, writes phase1-metrics.json.
# Usage: aggregate-phase1.py <logs_dir> <out_path> <tool> <trial> <wall_secs> <exit_code>
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
