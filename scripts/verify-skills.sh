#!/bin/bash
# Verifies each trial used the correct tools/skills by analyzing session JSONL logs.
# Usage:
#   ./verify-skills.sh              # Check all completed trials
#   ./verify-skills.sh pure 1       # Check specific tool + trial
set -uo pipefail
source "$(dirname "$0")/env.sh"

TOOL=${1:-}
TRIAL=${2:-}

if [ -n "$TOOL" ] && [ -n "$TRIAL" ]; then
  CHECKS=("$TOOL:$TRIAL")
else
  CHECKS=()
  for tool in "${TOOLS[@]}"; do
    for t in 1 2 3; do
      LOG_DIR="$RESULTS_DIR/$tool/t${t}/session-logs"
      [ -d "$LOG_DIR" ] && CHECKS+=("$tool:$t")
    done
  done
fi

python3 - "$RESULTS_DIR" "${CHECKS[@]}" <<'PY'
import json, os, sys, re
from collections import defaultdict

results_dir = sys.argv[1]
checks = sys.argv[2:]

# Expected skill patterns per tool
EXPECTED = {
    'pure': {
        'skills': [],
        'forbidden_skills': ['superpowers', 'oh-my-claudecode', 'bmad', 'ck:'],
        'description': 'No external skills — pure Claude Code only'
    },
    'superpower': {
        'skills': ['writing-plans', 'subagent-driven-development'],
        'forbidden_skills': ['oh-my-claudecode', 'bmad', 'ck:'],
        'description': 'Superpowers skills (writing-plans, subagent-driven-development)'
    },
    'bmad': {
        'skills': ['bmad-quick-dev', 'bmad-dev-story'],
        'forbidden_skills': ['superpowers', 'oh-my-claudecode', 'ck:'],
        'description': 'BMad skills (bmad-quick-dev, bmad-dev-story)'
    },
    'omc': {
        'skills': ['ralplan', 'autopilot'],
        'forbidden_skills': ['superpowers', 'bmad', 'ck:'],
        'description': 'OMC skills (ralplan, autopilot)'
    },
    'claudekit': {
        'skills': ['plan', 'cook'],
        'forbidden_skills': ['superpowers', 'oh-my-claudecode', 'bmad'],
        'description': 'Claudekit skills (ck:plan, ck:cook:auto)'
    },
}

for check in checks:
    tool, trial = check.split(':')
    trial = int(trial)
    log_dir = os.path.join(results_dir, tool, f't{trial}', 'session-logs')

    if not os.path.isdir(log_dir):
        print(f'\n=== {tool} t{trial}: NO SESSION LOGS ===')
        continue

    # Collect all tool uses across all session files
    skill_invocations = []
    agent_invocations = []
    tool_counts = defaultdict(int)
    total_lines = 0

    for fname in sorted(os.listdir(log_dir)):
        if not fname.endswith('.jsonl'):
            continue
        fpath = os.path.join(log_dir, fname)
        with open(fpath) as fh:
            for line in fh:
                total_lines += 1
                try:
                    d = json.loads(line)
                    msg = d.get('message', {})
                    content = msg.get('content', '')
                    if not isinstance(content, list):
                        continue
                    for block in content:
                        if not isinstance(block, dict) or block.get('type') != 'tool_use':
                            continue
                        name = block.get('name', '')
                        inp = block.get('input', {})
                        tool_counts[name] += 1

                        if name == 'Skill':
                            skill_name = inp.get('skill', '')
                            skill_args = inp.get('args', '')
                            skill_invocations.append({
                                'skill': skill_name,
                                'args': skill_args,
                                'file': fname[:12]
                            })
                        elif name == 'Agent':
                            desc = inp.get('description', '')
                            subtype = inp.get('subagent_type', 'general')
                            agent_invocations.append({
                                'description': desc[:60],
                                'subagent_type': subtype,
                                'file': fname[:12]
                            })
                except Exception:
                    pass

    # Also check subagent logs
    subagent_dir = os.path.join(log_dir, 'subagents')
    if os.path.isdir(subagent_dir):
        for fname in sorted(os.listdir(subagent_dir)):
            if not fname.endswith('.jsonl'):
                continue
            fpath = os.path.join(subagent_dir, fname)
            with open(fpath) as fh:
                for line in fh:
                    try:
                        d = json.loads(line)
                        msg = d.get('message', {})
                        content = msg.get('content', '')
                        if not isinstance(content, list):
                            continue
                        for block in content:
                            if not isinstance(block, dict) or block.get('type') != 'tool_use':
                                continue
                            name = block.get('name', '')
                            inp = block.get('input', {})
                            if name == 'Skill':
                                skill_invocations.append({
                                    'skill': inp.get('skill', ''),
                                    'args': inp.get('args', ''),
                                    'file': f'sub/{fname[:12]}'
                                })
                    except Exception:
                        pass

    # Analyze
    expected = EXPECTED.get(tool, {})
    expected_skills = expected.get('skills', [])
    forbidden_skills = expected.get('forbidden_skills', [])
    description = expected.get('description', '?')

    print(f'\n{"="*60}')
    print(f'  {tool} t{trial}')
    print(f'  Expected: {description}')
    print(f'{"="*60}')

    # Skill invocations
    if skill_invocations:
        print(f'\n  Skill Tool Invocations ({len(skill_invocations)}):')
        for s in skill_invocations:
            args_str = f' args="{s["args"]}"' if s['args'] else ''
            print(f'    - {s["skill"]}{args_str}  [{s["file"]}]')
    else:
        print(f'\n  Skill Tool Invocations: NONE')

    # Agent invocations (non-Explore, non-Plan — these are built-in)
    custom_agents = [a for a in agent_invocations if a['subagent_type'] not in ('Explore', 'Plan', 'general-purpose')]
    builtin_agents = [a for a in agent_invocations if a['subagent_type'] in ('Explore', 'Plan', 'general-purpose')]
    if custom_agents:
        print(f'\n  Custom Agent Invocations ({len(custom_agents)}):')
        for a in custom_agents:
            print(f'    - [{a["subagent_type"]}] {a["description"]}  [{a["file"]}]')
    if builtin_agents:
        print(f'\n  Built-in Agents: {len(builtin_agents)} (Explore={sum(1 for a in builtin_agents if a["subagent_type"]=="Explore")}, Plan={sum(1 for a in builtin_agents if a["subagent_type"]=="Plan")}, General={sum(1 for a in builtin_agents if a["subagent_type"]=="general-purpose")})')

    # Core tool summary
    core_tools = ['Read', 'Edit', 'Write', 'Bash', 'Grep', 'Glob']
    core_str = ', '.join(f'{t}={tool_counts[t]}' for t in core_tools if tool_counts[t])
    print(f'\n  Core Tools: {core_str}')
    other = {k: v for k, v in tool_counts.items() if k not in core_tools + ['Skill', 'Agent']}
    if other:
        other_str = ', '.join(f'{k}={v}' for k, v in sorted(other.items(), key=lambda x: -x[1])[:10])
        print(f'  Other Tools: {other_str}')

    # Verification
    print(f'\n  Verification:')
    issues = []

    # Normalize skill name for matching (strip prefixes, normalize separators)
    def skill_matches(actual, pattern):
        """Flexible match: 'bmad-quick-dev' matches 'bmad-quick-dev', 'ck-plan' matches 'plan', etc."""
        actual_norm = actual.lower().replace(':', '-').replace('_', '-')
        pattern_norm = pattern.lower().replace(':', '-').replace('_', '-')
        return pattern_norm in actual_norm

    # Check expected skills were used
    if expected_skills:
        all_skill_names = [s['skill'] for s in skill_invocations]
        for exp in expected_skills:
            matched = any(skill_matches(sk, exp) for sk in all_skill_names)
            if matched:
                print(f'    ✓ Expected skill "{exp}" was invoked')
            else:
                issues.append(f'Expected skill "{exp}" was NOT invoked')
                print(f'    ✗ Expected skill "{exp}" was NOT invoked')

    # Check no forbidden skills were used (skip if skill matches an expected pattern)
    for s in skill_invocations:
        is_expected = any(skill_matches(s['skill'], exp) for exp in expected_skills)
        if is_expected:
            continue
        for forbidden in forbidden_skills:
            if skill_matches(s['skill'], forbidden):
                issues.append(f'Forbidden skill "{s["skill"]}" was invoked')
                print(f'    ✗ FORBIDDEN skill "{s["skill"]}" was invoked!')

    # Pure should have zero skills
    if tool == 'pure':
        if not skill_invocations:
            print(f'    ✓ No Skill invocations (correct for pure)')
        else:
            issues.append(f'Pure trial invoked {len(skill_invocations)} skills')
            print(f'    ✗ Pure trial invoked {len(skill_invocations)} skills!')

    if not issues:
        print(f'\n  Result: ✓ PASS')
    else:
        print(f'\n  Result: ✗ FAIL ({len(issues)} issues)')

print()
PY
