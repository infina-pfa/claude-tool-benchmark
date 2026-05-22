#!/usr/bin/env python3
"""Extract per-trial session timelines from Claude Code JSONL session logs.

Reads results/<task>/<tool>/t<N>/session-logs/*.jsonl (and subagents/*.jsonl)
and writes a human-readable markdown timeline per (task, tool).

Output: docs/analysis/trial-timelines/<task>/<tool>.md
"""

from __future__ import annotations

import json
import os
import re
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Iterable

REPO = Path(__file__).resolve().parent.parent
RESULTS = REPO / "results"
OUT_BASE = REPO / "docs" / "analysis" / "trial-timelines"

TOOLS = ["bmad", "claudekit", "compound", "ecc", "gstack", "omc", "pure", "superpower"]
TASK_BASES = {
    "feature": RESULTS,
    "bugfix": RESULTS / "bugfix",
    "refactor": RESULTS / "refactor",
}

# Path fragments that signal a "plugin/skill/tool config" file read worth listing.
PLUGIN_SIGNALS = re.compile(
    r"(\.claude/(skills|plugins|agents|commands|hooks)/|"
    r"_bmad/|_compound/|_claudekit/|_gstack/|"
    r"\.opencode/|\.omc/|\.codex/|"
    r"superpowers?/|claudekit/|gstack/|ecc/|"
    r"plugins/[^/]+/skills/|skill\.md|SKILL\.md|workflow\.md|AGENTS?\.md|CLAUDE\.md)",
    re.IGNORECASE,
)


def shorten_path(p: str, run_root: str | None) -> str:
    if run_root and p.startswith(run_root):
        return p[len(run_root):].lstrip("/")
    # Try to strip up to runs/<tool>-tN/
    m = re.search(r"/runs/[^/]+/(.*)", p)
    if m:
        return m.group(1)
    return p


def iter_tool_uses(jsonl_path: Path) -> Iterable[dict]:
    """Yield (timestamp, tool_use_dict) for each tool_use event."""
    with jsonl_path.open() as f:
        for line in f:
            try:
                obj = json.loads(line)
            except Exception:
                continue
            ts = obj.get("timestamp")
            msg = obj.get("message", {})
            if not isinstance(msg, dict):
                continue
            content = msg.get("content", [])
            if not isinstance(content, list):
                continue
            for c in content:
                if isinstance(c, dict) and c.get("type") == "tool_use":
                    yield ts, c


def first_user_prompt(jsonl_path: Path) -> str:
    with jsonl_path.open() as f:
        for line in f:
            try:
                obj = json.loads(line)
            except Exception:
                continue
            if obj.get("type") != "user":
                continue
            msg = obj.get("message", {})
            content = msg.get("content")
            if isinstance(content, str) and content.strip():
                return content.strip()
            if isinstance(content, list):
                for c in content:
                    if isinstance(c, dict) and c.get("type") == "text":
                        t = c.get("text", "").strip()
                        if t:
                            return t
        return ""


def session_bounds(jsonl_path: Path) -> tuple[str | None, str | None]:
    first = last = None
    with jsonl_path.open() as f:
        for line in f:
            try:
                obj = json.loads(line)
            except Exception:
                continue
            ts = obj.get("timestamp")
            if not ts:
                continue
            if first is None:
                first = ts
            last = ts
    return first, last


def fmt_ts(ts: str | None) -> str:
    if not ts:
        return "?"
    # Trim to HH:MM
    return ts[11:16] if len(ts) >= 16 else ts


def summarise_subagent_prompt(prompt: str, max_len: int = 90) -> str:
    p = re.sub(r"\s+", " ", prompt).strip()
    if len(p) > max_len:
        p = p[:max_len].rstrip() + "…"
    return p


def collect_subagent_summaries(sub_dir: Path) -> list[dict]:
    out = []
    if not sub_dir.is_dir():
        return out
    for f in sorted(sub_dir.iterdir()):
        if not f.name.endswith(".jsonl"):
            continue
        prompt = ""
        tool_counts: Counter[str] = Counter()
        edits: list[str] = []
        reads: list[str] = []
        with f.open() as fh:
            for line in fh:
                try:
                    obj = json.loads(line)
                except Exception:
                    continue
                if not prompt and obj.get("type") == "user":
                    msg = obj.get("message", {})
                    content = msg.get("content")
                    if isinstance(content, str):
                        prompt = content
                    elif isinstance(content, list):
                        for c in content:
                            if isinstance(c, dict) and c.get("type") == "text":
                                prompt = c.get("text", "")
                                break
                msg = obj.get("message", {})
                if not isinstance(msg, dict):
                    continue
                content = msg.get("content", [])
                if not isinstance(content, list):
                    continue
                for c in content:
                    if isinstance(c, dict) and c.get("type") == "tool_use":
                        name = c.get("name", "?")
                        tool_counts[name] += 1
                        inp = c.get("input", {})
                        fp = inp.get("file_path") if isinstance(inp, dict) else None
                        if fp:
                            if name in ("Edit", "Write"):
                                edits.append(fp)
                            elif name == "Read":
                                reads.append(fp)
        out.append({
            "id": f.stem,
            "prompt": prompt,
            "tool_counts": tool_counts,
            "edits": edits,
            "reads": reads,
        })
    return out


def build_trial_timeline(task: str, tool: str, trial: str, trial_dir: Path) -> str:
    data = extract_trial(task, tool, trial, trial_dir)
    if data is None:
        return f"### {trial}\n\n_No session logs._\n"
    return render_trial_markdown(data)


def extract_trial(task: str, tool: str, trial: str, trial_dir: Path) -> dict | None:
    """Extract structured data for a single trial from session-logs.

    Returns a dict with the same information shown in the markdown timeline, plus
    absolute timestamps and duration. Returns None if logs are missing.
    """
    sl_dir = trial_dir / "session-logs"
    if not sl_dir.is_dir():
        return None

    primary_logs = sorted(
        [p for p in sl_dir.iterdir() if p.is_file() and p.suffix == ".jsonl"]
    )
    if not primary_logs:
        return None

    run_root = f"/Users/randytran/Codes/ai-tool-benchmark/runs/{tool}-{trial}"

    skill_calls: list[tuple[str, str, dict]] = []
    plugin_reads: list[tuple[str, str]] = []
    edits: list[tuple[str, str]] = []
    writes: list[tuple[str, str]] = []
    bash_count = 0
    bash_descriptions: list[str] = []
    agent_calls: list[tuple[str, dict]] = []
    task_calls: list[tuple[str, str]] = []
    tool_counts: Counter[str] = Counter()

    initial_prompt = first_user_prompt(primary_logs[0])
    first_ts, _ = session_bounds(primary_logs[0])
    last_ts: str | None = None

    for log in primary_logs:
        _, lt = session_bounds(log)
        if lt and (last_ts is None or lt > last_ts):
            last_ts = lt
        for ts, c in iter_tool_uses(log):
            name = c.get("name", "?")
            inp = c.get("input", {}) or {}
            tool_counts[name] += 1

            if name == "Skill":
                skill_calls.append((ts, log.stem, inp))
            elif name == "Read":
                fp = inp.get("file_path", "")
                if PLUGIN_SIGNALS.search(fp):
                    plugin_reads.append((ts, fp))
            elif name == "Edit":
                edits.append((ts, inp.get("file_path", "")))
            elif name == "Write":
                writes.append((ts, inp.get("file_path", "")))
            elif name == "Bash":
                bash_count += 1
                desc = inp.get("description", "") or inp.get("command", "")[:60]
                if desc:
                    bash_descriptions.append(desc)
            elif name in ("Agent", "Task"):
                agent_calls.append((ts, inp))
            elif name == "TaskCreate":
                content = inp.get("content") or inp.get("activeForm") or ""
                task_calls.append((ts, content))

    sub_summaries = collect_subagent_summaries(sl_dir / "subagents")

    # Opening prompt snippet (same truncation as markdown had)
    opening_prompt_snippet = ""
    if initial_prompt:
        snip = re.sub(r"\s+", " ", initial_prompt).strip()
        if len(snip) > 220:
            snip = snip[:220].rstrip() + "…"
        opening_prompt_snippet = snip

    # Skill activations (deduped by skill + args prefix)
    seen_sk: set[tuple[str, str]] = set()
    skill_unique: list[dict] = []
    for ts, _sid, inp in skill_calls:
        sk = inp.get("skill", "?")
        args = (inp.get("args") or "").strip()
        key = (sk, args[:80])
        if key in seen_sk:
            continue
        seen_sk.add(key)
        skill_unique.append({
            "skill": sk,
            "args": args[:400],
            "first_at": fmt_ts(ts),
        })

    # Plugin/skill file reads (deduped, shortened)
    seen_paths: list[str] = []
    seen_set: set[str] = set()
    for _ts, fp in plugin_reads:
        short = shorten_path(fp, run_root)
        if short in seen_set:
            continue
        seen_set.add(short)
        seen_paths.append(short)

    # Subagent dispatches
    subagent_list = []
    for ts, inp in agent_calls:
        sa = inp.get("subagent_type") or inp.get("name") or inp.get("description") or "?"
        desc = inp.get("description", "") or summarise_subagent_prompt(inp.get("prompt", ""), 80)
        subagent_list.append({"type": sa, "description": desc, "at": fmt_ts(ts)})

    subagent_transcripts = [
        {
            "id": s["id"],
            "prompt_snippet": summarise_subagent_prompt(s["prompt"] or "", 100),
            "tool_counts": dict(s["tool_counts"]),
            "edits": s["edits"],
            "reads": s["reads"],
        }
        for s in sub_summaries
    ]

    # Planning todos
    planning_items: list[str] = []
    for _ts, content in task_calls:
        snip = re.sub(r"\s+", " ", content)[:80]
        if snip:
            planning_items.append(snip)

    # Mutations grouped by top-2 path components
    write_paths = [shorten_path(fp, run_root) for _ts, fp in writes if fp]
    edit_paths = [shorten_path(fp, run_root) for _ts, fp in edits if fp]
    all_paths = write_paths + edit_paths
    unique_files = sorted(set(all_paths))
    grouped: Counter[str] = Counter()
    for p in unique_files:
        parts = p.split("/", 2)
        key = "/".join(parts[:2]) if len(parts) >= 2 else p
        grouped[key] += 1
    mutations = {
        "new_files": len(writes),
        "edits": len(edits),
        "unique_files": len(unique_files),
        "by_top_dir": [{"dir": k, "count": n} for k, n in grouped.most_common(8)],
        "new_file_paths": sorted(set(write_paths)),
    }

    # Bash breakdown
    bash_kinds: Counter[str] = Counter()
    for d in bash_descriptions:
        d_low = d.lower()
        if any(k in d_low for k in ("test", "jest", "vitest", "spec")):
            bash_kinds["tests"] += 1
        elif any(k in d_low for k in ("tsc", "typecheck", "type check", "type-check")):
            bash_kinds["typecheck"] += 1
        elif any(k in d_low for k in ("eslint", "lint", "prettier")):
            bash_kinds["lint/format"] += 1
        elif any(k in d_low for k in ("git ", "commit", "stash", "branch", "diff")):
            bash_kinds["git ops"] += 1
        elif any(k in d_low for k in ("ls", "find", "tree", "cat ", "grep", "rg ")):
            bash_kinds["inspection"] += 1
        elif any(k in d_low for k in ("install", "yarn", "npm ", "pnpm")):
            bash_kinds["install/build"] += 1
        else:
            bash_kinds["other"] += 1

    # Final state (commits + diff)
    commits_n: int | None = None
    commits_file = trial_dir / "commits.txt"
    if commits_file.is_file():
        commits = [l for l in commits_file.read_text().splitlines() if l.strip()]
        commits_n = len(commits)
    diff_summary = ""
    diff_file = trial_dir / "diff-stats.txt"
    if diff_file.is_file():
        for ln in diff_file.read_text().splitlines():
            if ln.strip():
                diff_summary = ln.strip()

    # Duration in minutes
    duration_minutes: int | None = None
    try:
        if first_ts and last_ts:
            s = datetime.fromisoformat(first_ts.replace("Z", "+00:00"))
            e = datetime.fromisoformat(last_ts.replace("Z", "+00:00"))
            duration_minutes = max(0, int((e - s).total_seconds() // 60))
    except Exception:
        pass

    return {
        "trial": trial,
        "sessions": len(primary_logs),
        "start_ts": first_ts,
        "end_ts": last_ts,
        "start_hm": fmt_ts(first_ts),
        "end_hm": fmt_ts(last_ts),
        "duration_minutes": duration_minutes,
        "opening_prompt": initial_prompt,
        "opening_prompt_snippet": opening_prompt_snippet,
        "skill_activations": {
            "total": len(skill_calls),
            "unique": skill_unique,
        },
        "plugin_skill_files": {
            "total_unique": len(seen_paths),
            "paths": seen_paths,
        },
        "subagents": {
            "count": len(agent_calls),
            "calls": subagent_list,
        },
        "subagent_transcripts": subagent_transcripts,
        "planning_todos": {
            "count": len(task_calls),
            "items": planning_items,
        },
        "mutations": mutations,
        "tool_counts": dict(tool_counts),
        "bash": {
            "total": bash_count,
            "by_kind": [{"kind": k, "count": v} for k, v in bash_kinds.most_common()],
        },
        "final": {
            "commits": commits_n,
            "diff_summary": diff_summary,
        },
    }


def render_trial_markdown(data: dict) -> str:
    """Render a trial data dict as the canonical markdown timeline block.

    Keeps the exact textual shape that `_write_aggregate` parses back out — so
    the aggregate regexes (Subagents dispatched, Plugin/skill files read,
    Skill activations, Code mutations, Bash commands, tests×N) stay valid.
    """
    lines: list[str] = []
    trial = data["trial"]
    lines.append(f"### {trial}")
    lines.append("")

    duration = ""
    if data.get("start_hm") and data.get("end_hm") and data["start_hm"] != "?":
        duration = f" ({data['start_hm']} → {data['end_hm']} UTC)"
    lines.append(f"- **Sessions**: {data['sessions']} log file(s){duration}")

    if data.get("opening_prompt_snippet"):
        lines.append(f"- **Opening prompt**: \"{data['opening_prompt_snippet']}\"")

    skill_act = data["skill_activations"]
    if skill_act["total"]:
        lines.append(f"- **Skill activations** ({skill_act['total']} total):")
        for sk in skill_act["unique"]:
            args = sk["args"].strip()
            arg_snip = re.sub(r"\s+", " ", args)[:80]
            trunc = "…" if len(args) > 80 else ""
            suffix = f" — {arg_snip}{trunc}" if arg_snip else ""
            lines.append(f"  - `{sk['skill']}`{suffix} (at {sk['first_at']})")

    psf = data["plugin_skill_files"]
    if psf["total_unique"]:
        capped = psf["paths"][:12]
        more = psf["total_unique"] - len(capped)
        lines.append(f"- **Plugin/skill files read** ({psf['total_unique']} unique):")
        for p in capped:
            lines.append(f"  - `{p}`")
        if more > 0:
            lines.append(f"  - …and {more} more")

    sa = data["subagents"]
    if sa["count"]:
        lines.append(f"- **Subagents dispatched (Agent tool)**: {sa['count']}")
        for c in sa["calls"][:6]:
            lines.append(f"  - `{c['type']}` — {c['description']} (at {c['at']})")
        if sa["count"] > 6:
            lines.append(f"  - …and {sa['count'] - 6} more")

    st = data["subagent_transcripts"]
    if st:
        lines.append(f"- **Subagent transcripts captured**: {len(st)}")
        for s in st[:6]:
            tc = Counter(s["tool_counts"])
            tc_str = ", ".join(f"{k}×{v}" for k, v in tc.most_common(4)) or "no tools"
            lines.append(f"  - `{s['id'][:18]}…` — {s['prompt_snippet']} [{tc_str}]")
        if len(st) > 6:
            lines.append(f"  - …and {len(st) - 6} more")

    pt = data["planning_todos"]
    if pt["count"]:
        lines.append(f"- **Planning todos (TaskCreate)**: {pt['count']}")
        for item in pt["items"][:4]:
            lines.append(f"  - {item}")
        if pt["count"] > 4:
            lines.append(f"  - …and {pt['count'] - 4} more")

    m = data["mutations"]
    if m["new_files"] or m["edits"]:
        lines.append(
            f"- **Code mutations**: {m['new_files']} new file(s), {m['edits']} edit(s) "
            f"→ {m['unique_files']} unique files"
        )
        for entry in m["by_top_dir"]:
            lines.append(f"  - `{entry['dir']}/` — {entry['count']} file(s)")
        if m["new_file_paths"]:
            lines.append(f"- **New files created** ({len(m['new_file_paths'])}):")
            for nf in m["new_file_paths"][:8]:
                lines.append(f"  - `{nf}`")
            if len(m["new_file_paths"]) > 8:
                lines.append(f"  - …and {len(m['new_file_paths']) - 8} more")

    bash = data["bash"]
    if bash["total"]:
        kinds_str = ", ".join(f"{k['kind']}×{k['count']}" for k in bash["by_kind"])
        lines.append(f"- **Bash commands**: {bash['total']} total ({kinds_str})")

    final = data["final"]
    if final.get("commits") is not None:
        lines.append(f"- **Final state**: {final['commits']} commit(s) on the trial branch")
    if final.get("diff_summary"):
        lines.append(f"  - Diff summary: `{final['diff_summary']}`")

    lines.append("")
    return "\n".join(lines)


def build_tool_data(task: str, tool: str) -> list[dict]:
    base = TASK_BASES[task]
    tool_dir = base / tool
    if not tool_dir.is_dir():
        return []
    trials = sorted(
        d.name for d in tool_dir.iterdir()
        if d.is_dir() and re.fullmatch(r"t\d+", d.name)
    )
    out: list[dict] = []
    for trial in trials:
        d = extract_trial(task, tool, trial, tool_dir / trial)
        if d is not None:
            out.append(d)
    return out


def build_tool_doc(task: str, tool: str, data: list[dict] | None = None) -> str | None:
    if data is None:
        data = build_tool_data(task, tool)
    if not data:
        return None

    out_lines: list[str] = []
    out_lines.append(f"# Trial timelines — `{tool}` ({task})")
    out_lines.append("")
    out_lines.append(
        "Auto-extracted from each trial's `session-logs/*.jsonl`. "
        "Shows skill activations, plugin/skill files read, subagents dispatched, "
        "code mutations, and Bash usage at a glance."
    )
    out_lines.append("")

    for d in data:
        out_lines.append(render_trial_markdown(d))
        out_lines.append("")

    return "\n".join(out_lines).rstrip() + "\n"


def _write_aggregate(out_base: Path) -> None:
    """Re-parse the written timeline docs to produce a defensible per-(tool,task) table."""
    rows: list[dict] = []
    for task in TASK_BASES:
        for tool in TOOLS:
            p = out_base / task / f"{tool}.md"
            if not p.exists():
                continue
            text = p.read_text()
            trials = re.split(r"\n### t(\d+)\n", text)[1:]
            metrics: dict[str, list[int]] = {
                "subagents": [], "skill_files": [], "skill_acts": [],
                "new_files": [], "edits": [], "bash_total": [], "tests": [],
            }
            for i in range(0, len(trials), 2):
                body = trials[i + 1]
                def _g(pat: str) -> int:
                    m = re.search(pat, body)
                    return int(m.group(1)) if m else 0
                metrics["subagents"].append(_g(r"\*\*Subagents dispatched.*?\*\*: (\d+)"))
                metrics["skill_files"].append(_g(r"\*\*Plugin/skill files read\*\* \((\d+) unique\)"))
                metrics["skill_acts"].append(_g(r"\*\*Skill activations\*\* \((\d+)"))
                metrics["new_files"].append(_g(r"\*\*Code mutations\*\*: (\d+) new"))
                metrics["edits"].append(_g(r"new file\(s\), (\d+) edit"))
                metrics["bash_total"].append(_g(r"\*\*Bash commands\*\*: (\d+) total"))
                metrics["tests"].append(_g(r"tests×(\d+)"))
            n = len(metrics["subagents"]) or 1
            row = {"task": task, "tool": tool, "n": n}
            for k, vals in metrics.items():
                row[f"{k}_mean"] = round(sum(vals) / n, 1) if vals else 0
                row[f"{k}_min"] = min(vals) if vals else 0
                row[f"{k}_max"] = max(vals) if vals else 0
            rows.append(row)

    (out_base / "aggregate.json").write_text(json.dumps(rows, indent=2))
    print(f"wrote {(out_base / 'aggregate.json').relative_to(REPO)}")

    # Markdown aggregate
    lines = ["# Trial-timeline aggregate",
             "",
             "Per-(tool,task) summary derived by re-parsing every doc in this directory. "
             "Regenerated automatically from `scripts/extract-trial-timeline.py`. The numbers "
             "here are the canonical source for any cross-tool claim that cites a count.",
             ""]
    for task in TASK_BASES:
        lines.append(f"## {task}")
        lines.append("")
        lines.append("| tool | n | subagents (mean, min–max) | skill activations | skill files read | new files | edits | bash | tests |")
        lines.append("|---|---:|---|---:|---|---:|---:|---:|---:|")
        for r in [x for x in rows if x["task"] == task]:
            lines.append(
                f"| `{r['tool']}` | {r['n']} | "
                f"{r['subagents_mean']} ({r['subagents_min']}–{r['subagents_max']}) | "
                f"{r['skill_acts_mean']} | "
                f"{r['skill_files_mean']} ({r['skill_files_min']}–{r['skill_files_max']}) | "
                f"{r['new_files_mean']} | "
                f"{r['edits_mean']} | "
                f"{r['bash_total_mean']} | "
                f"{r['tests_mean']} |"
            )
        lines.append("")
    lines.extend([
        "## Notes on metrics",
        "",
        "- **subagents**: count of `Agent`/`Task` tool calls in the primary session(s). Not the count of subagent transcript files (those are the *captured* subset).",
        "- **skill activations**: count of `Skill` tool calls (a skill being explicitly invoked).",
        "- **skill files read**: count of unique file paths read that match plugin/skill heuristics (e.g. `.claude/skills/`, `_bmad/`, `SKILL.md`). Most tools register skills via slash command and never `Read` skill files — only `bmad` shows skill content as a stream of `Read` events.",
        "- **bash**: total `Bash` tool calls (any subcategory).",
        "- **tests**: bash calls categorised as test runs (matched on `test|jest|vitest|spec` in the description).",
        "- All means are arithmetic over the trials available for that (tool, task) cell. n varies (feature: 4, bugfix/refactor: 2).",
    ])
    (out_base / "aggregate.md").write_text("\n".join(lines))
    print(f"wrote {(out_base / 'aggregate.md').relative_to(REPO)}")


def main(argv: list[str]) -> int:
    only_task = argv[1] if len(argv) > 1 else None
    only_tool = argv[2] if len(argv) > 2 else None

    written = 0
    for task, _base in TASK_BASES.items():
        if only_task and task != only_task:
            continue
        out_dir = OUT_BASE / task
        out_dir.mkdir(parents=True, exist_ok=True)
        for tool in TOOLS:
            if only_tool and tool != only_tool:
                continue
            data = build_tool_data(task, tool)
            if not data:
                continue
            # JSON (structured, machine-readable)
            json_path = out_dir / f"{tool}.json"
            json_path.write_text(json.dumps(data, indent=2))
            print(f"wrote {json_path.relative_to(REPO)}")
            # Markdown (human-readable)
            doc = build_tool_doc(task, tool, data=data)
            if doc is None:
                continue
            out_path = out_dir / f"{tool}.md"
            out_path.write_text(doc)
            written += 1
            print(f"wrote {out_path.relative_to(REPO)}")

    # Aggregate table (re-parses written docs to keep one source of truth)
    if not only_task and not only_tool:
        _write_aggregate(OUT_BASE)

    # Index
    if not only_task and not only_tool:
        idx_lines = ["# Trial Timelines", "",
                     "Per-trial session timelines extracted from raw `session-logs/*.jsonl` for every "
                     "(task, tool, trial) cell in the benchmark. Each tool page lists its trials with "
                     "skill activations, plugin/skill file reads, subagents, code mutations, and Bash usage.",
                     ""]
        for task in TASK_BASES:
            idx_lines.append(f"## {task}")
            idx_lines.append("")
            for tool in TOOLS:
                p = OUT_BASE / task / f"{tool}.md"
                if p.exists():
                    idx_lines.append(f"- [`{tool}`]({task}/{tool}.md)")
            idx_lines.append("")
        (OUT_BASE / "README.md").write_text("\n".join(idx_lines))
        print(f"wrote {(OUT_BASE / 'README.md').relative_to(REPO)}")

    print(f"\nDone. Wrote {written} tool docs.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
