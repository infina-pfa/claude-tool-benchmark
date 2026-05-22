#!/usr/bin/env python3
"""
Cohort-symmetry audit — validates the pre-registered rerun protocol in CLAUDE.md.

Policy (CLAUDE.md §"Cohort rerun rule"): if any trial T<N> is rerun, T<N>
must be rerun for all 8 tools before the trial column is used in comparison.

This script reads results/<tool>/t<N>/sessions/*.meta.json across all 8 tools,
groups by trial index, and reports:

- Per-trial min/max started_at — flags >24h spread as potentially non-cohort-
  symmetric (a real cohort run should complete within a single day).
- Missing trials per tool.
- Archive dirs (results/<tool>/archive-t<N>-YYYYMMDD/) — prior reruns.
- Base-commit mismatches within a trial (different base = different codebase).

Exit non-zero if any hard-symmetry violation is detected so CI can gate on it.
"""

import json, os, re, sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
RESULTS = REPO / 'results'
TASK_ROOTS = {
    'feature': RESULTS,
    'bugfix': RESULTS / 'bugfix',
    'refactor': RESULTS / 'refactor',
}
TOOLS = ('bmad', 'claudekit', 'compound', 'ecc', 'gstack',
         'omc', 'pure', 'superpower')
ARCHIVE_RE = re.compile(r'^archive-t(\d+)-(\d{8})$')


def iso_parse(s):
    try:
        return datetime.fromisoformat(s.replace('Z', '+00:00'))
    except Exception:
        return None


def collect_task(task):
    """Return {trial: {tool: [meta_dicts]}} for this task.

    `base_commit` here reflects the BASE actually used for the diff
    (commits.txt line 1) — not the legacy `meta.json.base_commit` field,
    which records the worktree HEAD at session launch and can disagree
    with the BASE fed to judges when a tool's setup commits config
    artifacts after the BENCH_COMMIT pin (e.g. claudekit).
    """
    root = TASK_ROOTS[task]
    by_trial = defaultdict(lambda: defaultdict(list))
    for tool in TOOLS:
        tool_root = root / tool
        if not tool_root.is_dir():
            continue
        for sub in tool_root.iterdir():
            m = re.match(r'^t(\d+)$', sub.name)
            if not m:
                continue
            trial = int(m.group(1))
            commits_txt = sub / 'commits.txt'
            base_sha = ''
            if commits_txt.is_file():
                try:
                    base_sha = commits_txt.read_text().splitlines()[0].strip()
                except Exception:
                    base_sha = ''
            meta_dir = sub / 'sessions'
            if not meta_dir.is_dir():
                continue
            for mf in meta_dir.glob('*.meta.json'):
                try:
                    with open(mf) as fh:
                        d = json.load(fh)
                except Exception:
                    continue
                if base_sha:
                    d['base_commit'] = base_sha
                by_trial[trial][tool].append(d)
    return by_trial


def archive_summary(task):
    root = TASK_ROOTS[task]
    out = []
    for tool in TOOLS:
        tool_root = root / tool
        if not tool_root.is_dir():
            continue
        for sub in tool_root.iterdir():
            m = ARCHIVE_RE.match(sub.name)
            if m:
                out.append((tool, int(m.group(1)), m.group(2)))
    return out


def main():
    hard_violations = 0
    for task in TASK_ROOTS:
        print(f'\n=== {task} ===')
        by_trial = collect_task(task)
        archives = archive_summary(task)
        if not by_trial:
            print('  (no trials found)')
            continue
        for trial in sorted(by_trial):
            tools_run = by_trial[trial]
            missing = [t for t in TOOLS if t not in tools_run]
            starts = []
            bases = set()
            for tool, metas in tools_run.items():
                for m in metas:
                    if m.get('started_at'):
                        s = iso_parse(m['started_at'])
                        if s:
                            starts.append(s)
                    if m.get('base_commit'):
                        bases.add(m['base_commit'].split()[0])
            if not starts:
                print(f'  t{trial}: no timestamps')
                continue
            span_hours = (max(starts) - min(starts)).total_seconds() / 3600
            flag = ''
            if missing:
                flag = f'  [MISSING: {", ".join(missing)}]'
                hard_violations += 1
            if span_hours > 24:
                flag += f'  [SPAN>{span_hours:.0f}h — cohort-symmetry warning]'
            if len(bases) > 1:
                flag += f'  [BASE DIVERGENCE: {len(bases)} different base commits]'
                hard_violations += 1
            print(f'  t{trial}: n_tools={len(tools_run)}/{len(TOOLS)}, '
                  f'span={span_hours:5.1f}h, '
                  f'first={min(starts).strftime("%Y-%m-%d")}, '
                  f'last={max(starts).strftime("%Y-%m-%d")}{flag}')
        if archives:
            print(f'  Archived reruns: {len(archives)}')
            for tool, trial, date in sorted(archives):
                print(f'    - {tool} t{trial} archived on {date}')

    print('\n--- Summary ---')
    if hard_violations:
        print(f'{hard_violations} hard-symmetry violations (missing-tool or base-divergence).')
        print('Cohort-symmetry not verified; rerun protocol may have been bypassed.')
        sys.exit(1)
    print('No hard-symmetry violations detected. Soft warnings (>24h span) may still apply.')


if __name__ == '__main__':
    main()
