#!/usr/bin/env python3
"""Mine Claude Code session JSONL logs for per-trial behavioral metrics.

Walks results/<tool>/t<N>/session-logs/*.jsonl for `feature` and
results/{bugfix,refactor}/<tool>/t<N>/session-logs/*.jsonl for the other tasks,
plus subagents/*.jsonl underneath. Emits one session-audit.json per trial and
a summary at results/_audits/session-audit.{json,md}.

The intent is to replace impression-grounded narrative in docs/tools/*.md with
counts taken from the actual transcripts: which skills fired, which slash
commands ran, how many subagents dispatched, what the Read/Edit/Bash mix looked
like, and how much of the agent's file-read budget went into tool scaffolding
vs the target repo.

Pure stdlib. Run from repo root: `python3 scripts/audit-sessions.py`.
"""

from __future__ import annotations

import json
import os
import re
import statistics
import sys
from collections import Counter
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parent.parent
RESULTS = ROOT / "results"
AUDIT_DIR = RESULTS / "_audits"

TOOLS = ["bmad", "claudekit", "compound", "ecc", "gstack", "omc", "pure", "superpower"]
TASKS = ["feature", "bugfix", "refactor"]
TRIALS = ["t1", "t2", "t3"]

# Hardcoded prefix list for "tool's own scaffolding / config" classification.
# A file-path containing any of these substrings is treated as tool-owned;
# everything else is treated as target-repo (the codebase under test).
TOOL_CONFIG_MARKERS = (
    "/.claude/",
    "/.claudekit/",
    "/.omc/",
    "/_bmad/",
    "/_bmad-output/",
    "/_compound/",
    "/.compound/",
    "/.everything-claude-code/",
    "/superpowers/",
    "/.superpowers/",
    "/.claude/plugins/",
    "/.claude/skills/",
    "/CLAUDE.md",
    "/AGENTS.md",
)

# Slash-command shape inside user message content blocks. Claude Code wraps
# typed slash commands as `<command-name>/foo</command-name>` with the args in
# a sibling `<command-args>` tag; we only need the name.
SLASH_RE = re.compile(r"<command-name>([^<]+)</command-name>")


@dataclass
class TrialMetrics:
    tool: str
    task: str
    trial: str
    paths: list[str] = field(default_factory=list)
    main_turns: int = 0
    sidechain_turns: int = 0
    wall_clock_min: float = 0.0
    first_ts: str | None = None
    last_ts: str | None = None
    input_tokens: int = 0
    output_tokens: int = 0
    cache_read_tokens: int = 0
    cache_creation_tokens: int = 0
    web_search_requests: int = 0
    web_fetch_requests: int = 0
    skills_invoked: dict[str, int] = field(default_factory=dict)
    slash_commands: list[str] = field(default_factory=list)
    tools: dict[str, int] = field(default_factory=dict)
    bash_commands_top: list[tuple[str, int]] = field(default_factory=list)
    subagent_dispatches: int = 0
    subagent_types: dict[str, int] = field(default_factory=dict)
    files_read: int = 0
    files_edited: int = 0
    files_written: int = 0
    distinct_files_read: int = 0
    distinct_files_edited: int = 0
    tool_config_reads: int = 0
    target_repo_reads: int = 0
    tool_config_edits: int = 0
    target_repo_edits: int = 0
    lines_added: int = 0
    lines_removed: int = 0
    # Per-skill token cost: skill_name → {turns, input, output, cache_read, cache_creation}.
    # Joined from each assistant record's `attributionSkill` and same-record `message.usage`.
    skill_token_cost: dict[str, dict[str, int]] = field(default_factory=dict)


def is_tool_config(path: str | None) -> bool:
    if not path:
        return False
    p = path if path.startswith("/") else "/" + path
    return any(marker in p for marker in TOOL_CONFIG_MARKERS)


def iter_jsonl(path: Path) -> Iterable[dict]:
    with path.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue


def parse_iso(ts: str) -> float | None:
    if not ts:
        return None
    try:
        # Drop trailing 'Z' for fromisoformat compatibility on older Pythons.
        return _datetime_from_iso(ts)
    except Exception:
        return None


def _datetime_from_iso(ts: str) -> float:
    from datetime import datetime
    if ts.endswith("Z"):
        ts = ts[:-1] + "+00:00"
    return datetime.fromisoformat(ts).timestamp()


def trial_log_paths(task: str, tool: str, trial: str) -> list[Path]:
    if task == "feature":
        base = RESULTS / tool / trial / "session-logs"
    else:
        base = RESULTS / task / tool / trial / "session-logs"
    if not base.exists():
        return []
    paths: list[Path] = sorted(base.glob("*.jsonl"))
    sub = base / "subagents"
    if sub.exists():
        paths.extend(sorted(sub.glob("*.jsonl")))
    return paths


def aggregate_trial(tool: str, task: str, trial: str) -> TrialMetrics | None:
    paths = trial_log_paths(task, tool, trial)
    if not paths:
        return None

    m = TrialMetrics(tool=tool, task=task, trial=trial, paths=[str(p.relative_to(ROOT)) for p in paths])

    read_paths: set[str] = set()
    edit_paths: set[str] = set()
    bash_bins: Counter[str] = Counter()
    skills: Counter[str] = Counter()
    tools_counter: Counter[str] = Counter()
    subagent_types: Counter[str] = Counter()
    first_ts_f: float | None = None
    last_ts_f: float | None = None

    for path in paths:
        for rec in iter_jsonl(path):
            ts = rec.get("timestamp")
            ts_f = parse_iso(ts) if ts else None
            if ts_f is not None:
                if first_ts_f is None or ts_f < first_ts_f:
                    first_ts_f = ts_f
                    m.first_ts = ts
                if last_ts_f is None or ts_f > last_ts_f:
                    last_ts_f = ts_f
                    m.last_ts = ts

            rtype = rec.get("type")
            sidechain = bool(rec.get("isSidechain"))
            skill_attr: str | None = None
            if rtype == "assistant":
                if sidechain:
                    m.sidechain_turns += 1
                else:
                    m.main_turns += 1
                skill_attr = rec.get("attributionSkill")
                if skill_attr:
                    skills[skill_attr] += 1

            msg = rec.get("message") or {}
            if not isinstance(msg, dict):
                continue

            # Token usage on assistant messages.
            usage = msg.get("usage") or {}
            if isinstance(usage, dict):
                in_tok = int(usage.get("input_tokens") or 0)
                out_tok = int(usage.get("output_tokens") or 0)
                cr_tok = int(usage.get("cache_read_input_tokens") or 0)
                cc_tok = int(usage.get("cache_creation_input_tokens") or 0)
                m.input_tokens += in_tok
                m.output_tokens += out_tok
                m.cache_read_tokens += cr_tok
                m.cache_creation_tokens += cc_tok
                if skill_attr:
                    bucket = m.skill_token_cost.setdefault(
                        skill_attr,
                        {"turns": 0, "input": 0, "output": 0, "cache_read": 0, "cache_creation": 0},
                    )
                    bucket["turns"] += 1
                    bucket["input"] += in_tok
                    bucket["output"] += out_tok
                    bucket["cache_read"] += cr_tok
                    bucket["cache_creation"] += cc_tok
                stu = usage.get("server_tool_use") or {}
                if isinstance(stu, dict):
                    m.web_search_requests += int(stu.get("web_search_requests") or 0)
                    m.web_fetch_requests += int(stu.get("web_fetch_requests") or 0)

            content = msg.get("content")
            # Slash-command parsing on string content (user-typed prompts).
            if isinstance(content, str):
                for hit in SLASH_RE.findall(content):
                    m.slash_commands.append(hit.strip())

            if isinstance(content, list):
                for block in content:
                    if not isinstance(block, dict):
                        continue
                    if block.get("type") == "text":
                        txt = block.get("text") or ""
                        for hit in SLASH_RE.findall(txt):
                            m.slash_commands.append(hit.strip())
                    if block.get("type") != "tool_use":
                        continue
                    name = block.get("name") or "?"
                    tools_counter[name] += 1
                    inp = block.get("input") or {}
                    if not isinstance(inp, dict):
                        continue
                    if name == "Read":
                        fp = inp.get("file_path")
                        m.files_read += 1
                        if fp:
                            read_paths.add(fp)
                            if is_tool_config(fp):
                                m.tool_config_reads += 1
                            else:
                                m.target_repo_reads += 1
                    elif name == "Edit":
                        fp = inp.get("file_path")
                        m.files_edited += 1
                        if fp:
                            edit_paths.add(fp)
                            if is_tool_config(fp):
                                m.tool_config_edits += 1
                            else:
                                m.target_repo_edits += 1
                    elif name == "Write":
                        fp = inp.get("file_path")
                        m.files_written += 1
                        if fp:
                            edit_paths.add(fp)
                            if is_tool_config(fp):
                                m.tool_config_edits += 1
                            else:
                                m.target_repo_edits += 1
                    elif name == "Bash":
                        cmd = (inp.get("command") or "").strip()
                        if cmd:
                            head = cmd.split()[0]
                            # Strip a leading path so `/usr/local/bin/npm` reads as `npm`.
                            head = head.rsplit("/", 1)[-1]
                            bash_bins[head] += 1
                    elif name == "Agent":
                        m.subagent_dispatches += 1
                        sa = inp.get("subagent_type") or "?"
                        subagent_types[sa] += 1
                    elif name == "Skill":
                        sk = inp.get("skill") or inp.get("name") or "?"
                        skills[f"Skill:{sk}"] += 1

            # Attachment events surface added/removed line counts when present.
            if rtype == "attachment":
                att = rec.get("attachment") or {}
                if isinstance(att, dict):
                    added = att.get("addedLines")
                    removed = att.get("removedLines")
                    if isinstance(added, int):
                        m.lines_added += added
                    if isinstance(removed, int):
                        m.lines_removed += removed

    m.distinct_files_read = len(read_paths)
    m.distinct_files_edited = len(edit_paths)
    m.skills_invoked = dict(skills.most_common())
    m.tools = dict(tools_counter.most_common())
    m.subagent_types = dict(subagent_types.most_common())
    m.bash_commands_top = bash_bins.most_common(10)
    if first_ts_f is not None and last_ts_f is not None:
        m.wall_clock_min = round((last_ts_f - first_ts_f) / 60.0, 2)
    return m


def trial_audit_path(task: str, tool: str, trial: str) -> Path:
    if task == "feature":
        return RESULTS / tool / trial / "session-audit.json"
    return RESULTS / task / tool / trial / "session-audit.json"


def summarize_cell(cells: list[TrialMetrics]) -> dict:
    """Mean/median of headline metrics across trials in one (tool, task) cell."""
    def collect(attr: str) -> list[float]:
        return [float(getattr(c, attr)) for c in cells]

    def m_and_med(xs: list[float]) -> dict:
        if not xs:
            return {"mean": 0.0, "median": 0.0}
        return {"mean": round(statistics.mean(xs), 2), "median": round(statistics.median(xs), 2)}

    skill_union: Counter[str] = Counter()
    tools_union: Counter[str] = Counter()
    subagent_union: Counter[str] = Counter()
    slash_union: Counter[str] = Counter()
    skill_cost: dict[str, dict[str, int]] = {}
    for c in cells:
        skill_union.update(c.skills_invoked)
        tools_union.update(c.tools)
        subagent_union.update(c.subagent_types)
        slash_union.update(Counter(c.slash_commands))
        for sk, bucket in c.skill_token_cost.items():
            agg = skill_cost.setdefault(
                sk, {"turns": 0, "input": 0, "output": 0, "cache_read": 0, "cache_creation": 0}
            )
            for k, v in bucket.items():
                agg[k] += v

    cache_ratios: list[float] = []
    for c in cells:
        denom = c.cache_read_tokens + c.cache_creation_tokens
        if denom > 0:
            cache_ratios.append(c.cache_read_tokens / denom)

    return {
        "trials": [c.trial for c in cells],
        "wall_clock_min": m_and_med(collect("wall_clock_min")),
        "main_turns": m_and_med(collect("main_turns")),
        "sidechain_turns": m_and_med(collect("sidechain_turns")),
        "subagent_dispatches": m_and_med(collect("subagent_dispatches")),
        "files_read": m_and_med(collect("files_read")),
        "distinct_files_read": m_and_med(collect("distinct_files_read")),
        "files_edited": m_and_med(collect("files_edited")),
        "distinct_files_edited": m_and_med(collect("distinct_files_edited")),
        "tool_config_reads": m_and_med(collect("tool_config_reads")),
        "target_repo_reads": m_and_med(collect("target_repo_reads")),
        "input_tokens": m_and_med(collect("input_tokens")),
        "output_tokens": m_and_med(collect("output_tokens")),
        "cache_hit_ratio_mean": round(statistics.mean(cache_ratios), 3) if cache_ratios else 0.0,
        "skills_invoked": dict(skill_union.most_common(8)),
        "tools": dict(tools_union.most_common(12)),
        "subagent_types": dict(subagent_union.most_common(8)),
        "slash_commands": dict(slash_union.most_common(8)),
        "skill_token_cost": skill_cost,
    }


def render_md(summary: dict) -> str:
    lines: list[str] = []
    lines.append("# Session audit — per-tool behavioral metrics")
    lines.append("")
    lines.append("Mined from `results/<tool>/t<N>/session-logs/*.jsonl` (feature) and")
    lines.append("`results/{bugfix,refactor}/<tool>/t<N>/session-logs/*.jsonl` (other tasks),")
    lines.append("including `subagents/*.jsonl`. Numbers are the **mean across 3 trials per cell**.")
    lines.append("")
    lines.append("Generated by `scripts/audit-sessions.py`. Regenerate after any new trial.")
    lines.append("")

    for task in TASKS:
        lines.append(f"## {task}")
        lines.append("")
        lines.append("| Tool | wall-clock min | main turns | sidechain turns | sub-agent disp. | files read | distinct read | files edited | tool-config reads | target-repo reads | cache hit |")
        lines.append("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for tool in TOOLS:
            cell = summary.get(tool, {}).get(task)
            if not cell:
                lines.append(f"| {tool} | — | — | — | — | — | — | — | — | — | — |")
                continue
            lines.append(
                "| {tool} | {wc} | {mt} | {sc} | {sa} | {fr} | {dfr} | {fe} | {tcr} | {trr} | {ch} |".format(
                    tool=tool,
                    wc=cell["wall_clock_min"]["mean"],
                    mt=cell["main_turns"]["mean"],
                    sc=cell["sidechain_turns"]["mean"],
                    sa=cell["subagent_dispatches"]["mean"],
                    fr=cell["files_read"]["mean"],
                    dfr=cell["distinct_files_read"]["mean"],
                    fe=cell["files_edited"]["mean"],
                    tcr=cell["tool_config_reads"]["mean"],
                    trr=cell["target_repo_reads"]["mean"],
                    ch=cell["cache_hit_ratio_mean"],
                )
            )
        lines.append("")

    lines.append("## Skill activation by tool (union across trials, all tasks)")
    lines.append("")
    lines.append("| Tool | Skills observed (count) |")
    lines.append("|---|---|")
    for tool in TOOLS:
        union: Counter[str] = Counter()
        for task in TASKS:
            cell = summary.get(tool, {}).get(task) or {}
            for k, v in (cell.get("skills_invoked") or {}).items():
                union[k] += v
        if not union:
            lines.append(f"| {tool} | — |")
        else:
            joined = ", ".join(f"`{k}` ({v})" for k, v in union.most_common(8))
            lines.append(f"| {tool} | {joined} |")
    lines.append("")

    lines.append("## Sub-agent dispatch by tool (union across trials, all tasks)")
    lines.append("")
    lines.append("| Tool | sub-agent types observed |")
    lines.append("|---|---|")
    for tool in TOOLS:
        union: Counter[str] = Counter()
        for task in TASKS:
            cell = summary.get(tool, {}).get(task) or {}
            for k, v in (cell.get("subagent_types") or {}).items():
                union[k] += v
        if not union:
            lines.append(f"| {tool} | — |")
        else:
            joined = ", ".join(f"`{k}` ({v})" for k, v in union.most_common(8))
            lines.append(f"| {tool} | {joined} |")
    lines.append("")

    lines.append("## Skill token cost by tool (sum across trials, all tasks)")
    lines.append("")
    lines.append("Output tokens are the cost a skill *generated*; input + cache_read are the context it *consumed*. Both are summed across every assistant turn whose `attributionSkill` matched, joined with that turn's `message.usage`. Skills are ranked by output_tokens; only the top 5 per tool are shown.")
    lines.append("")
    lines.append("| Tool | Skill | turns | output tok | input tok | cache_read tok |")
    lines.append("|---|---|---:|---:|---:|---:|")
    for tool in TOOLS:
        merged: dict[str, dict[str, int]] = {}
        for task in TASKS:
            cell = summary.get(tool, {}).get(task) or {}
            for sk, bucket in (cell.get("skill_token_cost") or {}).items():
                agg = merged.setdefault(
                    sk, {"turns": 0, "input": 0, "output": 0, "cache_read": 0, "cache_creation": 0}
                )
                for k, v in bucket.items():
                    agg[k] += v
        if not merged:
            lines.append(f"| {tool} | — | — | — | — | — |")
            continue
        ranked = sorted(merged.items(), key=lambda kv: kv[1].get("output", 0), reverse=True)[:5]
        for i, (sk, bucket) in enumerate(ranked):
            label = tool if i == 0 else ""
            lines.append(
                f"| {label} | `{sk}` | {bucket['turns']} | {bucket['output']:,} | {bucket['input']:,} | {bucket['cache_read']:,} |"
            )
    lines.append("")

    lines.append("## Slash commands typed by tool (union across trials, all tasks)")
    lines.append("")
    lines.append("| Tool | slash commands observed |")
    lines.append("|---|---|")
    for tool in TOOLS:
        union: Counter[str] = Counter()
        for task in TASKS:
            cell = summary.get(tool, {}).get(task) or {}
            for k, v in (cell.get("slash_commands") or {}).items():
                union[k] += v
        if not union:
            lines.append(f"| {tool} | — |")
        else:
            joined = ", ".join(f"`{k}` ({v})" for k, v in union.most_common(8))
            lines.append(f"| {tool} | {joined} |")
    lines.append("")

    return "\n".join(lines) + "\n"


def main() -> int:
    AUDIT_DIR.mkdir(parents=True, exist_ok=True)
    summary: dict = {}
    audited = 0
    missing: list[tuple[str, str, str]] = []

    for tool in TOOLS:
        summary[tool] = {}
        for task in TASKS:
            cells: list[TrialMetrics] = []
            for trial in TRIALS:
                m = aggregate_trial(tool, task, trial)
                if m is None:
                    missing.append((tool, task, trial))
                    continue
                out = trial_audit_path(task, tool, trial)
                out.parent.mkdir(parents=True, exist_ok=True)
                out.write_text(json.dumps(asdict(m), indent=2) + "\n")
                cells.append(m)
                audited += 1
            if cells:
                summary[tool][task] = summarize_cell(cells)

    (AUDIT_DIR / "session-audit.json").write_text(json.dumps(summary, indent=2) + "\n")
    (AUDIT_DIR / "session-audit.md").write_text(render_md(summary))

    print(f"audited {audited} trial folders")
    if missing:
        print(f"missing session-logs for {len(missing)} (tool,task,trial) cells:")
        for t in missing[:20]:
            print(" ", t)
        if len(missing) > 20:
            print(f"  ... and {len(missing) - 20} more")
    return 0


if __name__ == "__main__":
    sys.exit(main())
