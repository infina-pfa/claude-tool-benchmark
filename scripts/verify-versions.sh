#!/bin/bash
# verify-versions.sh — compare installed plugin/tool versions across all trial
# config dirs against versions.lock.json. Exits non-zero if any (trial, tool)
# pair drifts from the locked SHA/version.
#
# Usage:
#   ./scripts/verify-versions.sh                # all tools
#   ./scripts/verify-versions.sh compound       # one tool
#
# The lockfile is the source of truth. Drift is reported as:
#   DRIFT  <trial>  <tool>  installed=<x>  expected=<y>
#
# A tool present in the lockfile but never installed in any trial is OK
# (e.g. pure has nothing to install). A tool installed in a trial but absent
# from the lockfile is reported as `UNTRACKED`.
set -uo pipefail
cd "$(dirname "$0")/.."

LOCKFILE="versions.lock.json"
[ -f "$LOCKFILE" ] || { echo "FATAL: $LOCKFILE not found" >&2; exit 2; }

FILTER="${1:-}"

python3 - "$LOCKFILE" "$FILTER" <<'PY'
import json, sys, glob, subprocess, os, re

lockfile_path, filter_tool = sys.argv[1], (sys.argv[2] or "").strip()
lock = json.load(open(lockfile_path))
tools = lock.get("tools") or {}

PLUGIN_ID_TO_TOOL = {}
for tool_name, spec in tools.items():
    pid = spec.get("plugin_id")
    if pid:
        marketplace = spec.get("marketplace", "")
        full_id = f"{pid}@{marketplace}" if marketplace else pid
        PLUGIN_ID_TO_TOOL[full_id] = tool_name

errors = 0
checked = 0

def sha_match(installed: str, expected: str) -> bool:
    """Prefix-match installed vs expected (either may be shorter than the other).
    git rev-parse --short defaults to 7 chars; lockfile may store 8 or 40."""
    if not installed or not expected:
        return False
    installed = installed.lower()
    expected = expected.lower()
    n = min(len(installed), len(expected))
    return n >= 7 and installed[:n] == expected[:n]

def report(level, *parts):
    global errors
    if level == "DRIFT":
        errors += 1
    print(f"{level:8} " + "  ".join(str(p) for p in parts))

# 1) Plugin-based tools (claude plugin install ...): check installed_plugins.json per trial
plugin_globs = (
    glob.glob("config/*/plugins/installed_plugins.json")
    + glob.glob("config/bugfix/*/plugins/installed_plugins.json")
    + glob.glob("config/refactor/*/plugins/installed_plugins.json")
)
for trial_pf in sorted(plugin_globs):
    parts = trial_pf.split("/")
    if parts[1] in ("bugfix", "refactor"):
        task, trial_name = parts[1], parts[2]
        trial = f"{task}/{trial_name}"
    else:
        task, trial_name = "feature", parts[1]
        trial = trial_name
    # Trial dir name pattern: <tool>-t<N>
    m = re.match(r"^([a-z]+)-t\d+$", trial_name)
    if not m:
        continue
    tool_name = m.group(1)
    if filter_tool and tool_name != filter_tool:
        continue
    spec = tools.get(tool_name)
    if not spec or spec.get("kind") != "claude-plugin":
        continue

    expected_v = spec.get("version", "")
    expected_sha = (spec.get("tag_sha") or spec.get("marketplace_sha") or "")[:8]
    target_pid = spec.get("plugin_id", "")
    target_marketplace = spec.get("marketplace", "")

    try:
        d = json.load(open(trial_pf))
    except Exception as e:
        report("ERROR", trial, tool_name, f"failed to parse {trial_pf}: {e}")
        continue

    installed = (d.get("plugins") or {}).get(f"{target_pid}@{target_marketplace}", [])
    if not installed:
        report("MISSING", trial, tool_name, f"no install of {target_pid}@{target_marketplace}")
        errors += 1
        continue

    e = installed[0]
    actual_v = e.get("version", "?")
    actual_sha = (e.get("gitCommitSha") or "")[:8]
    checked += 1

    sentinel = (expected_v == "install-resolved") or (str(spec.get("marketplace_sha", "")) == "install-resolved")
    drift = []
    if not sentinel:
        if expected_v and actual_v != expected_v:
            drift.append(f"version installed={actual_v} expected={expected_v}")
        if expected_sha and actual_sha and not sha_match(actual_sha, expected_sha):
            drift.append(f"sha installed={actual_sha} expected={expected_sha}")
    if drift:
        report("DRIFT", trial, tool_name, " | ".join(drift))
    else:
        suffix = " (install-resolved)" if sentinel else ""
        report("OK", trial, tool_name, f"v{actual_v} {actual_sha}{suffix}")

# 2) gstack: per-trial clone in config/gstack-t*/skills/gstack
gstack_spec = tools.get("gstack")
if gstack_spec and (not filter_tool or filter_tool == "gstack"):
    expected_sha = (gstack_spec.get("sha") or "")[:8]
    expected_v = gstack_spec.get("version", "")
    gstack_globs = (
        glob.glob("config/gstack-t*/skills/gstack")
        + glob.glob("config/bugfix/gstack-t*/skills/gstack")
        + glob.glob("config/refactor/gstack-t*/skills/gstack")
    )
    for d in sorted(gstack_globs):
        parts = d.split("/")
        if parts[1] in ("bugfix", "refactor"):
            trial = f"{parts[1]}/{parts[2]}"
        else:
            trial = parts[1]
        try:
            actual_sha = subprocess.check_output(
                ["git", "-C", d, "rev-parse", "--short", "HEAD"],
                stderr=subprocess.DEVNULL).decode().strip()
        except Exception:
            actual_sha = "?"
        try:
            actual_v = open(os.path.join(d, "VERSION")).read().strip()
        except Exception:
            actual_v = "?"
        checked += 1
        drift = []
        if expected_v and actual_v != expected_v:
            drift.append(f"version installed={actual_v} expected={expected_v}")
        if expected_sha and not sha_match(actual_sha, expected_sha):
            drift.append(f"sha installed={actual_sha} expected={expected_sha}")
        if drift:
            report("DRIFT", trial, "gstack", " | ".join(drift))
        else:
            report("OK", trial, "gstack", f"{actual_v} {actual_sha}")

# 3) claudekit fork (cached at /tmp/internal-claudekit)
ck_spec = tools.get("claudekit")
if ck_spec and (not filter_tool or filter_tool == "claudekit"):
    p = "/tmp/internal-claudekit"
    if os.path.isdir(os.path.join(p, ".git")):
        try:
            actual_sha = subprocess.check_output(
                ["git", "-C", p, "rev-parse", "--short", "HEAD"],
                stderr=subprocess.DEVNULL).decode().strip()
        except Exception:
            actual_sha = "?"
        expected_sha = (ck_spec.get("sha") or "")[:8]
        checked += 1
        if expected_sha and not sha_match(actual_sha, expected_sha):
            report("DRIFT", "_global", "claudekit", f"sha installed={actual_sha} expected={expected_sha}")
        else:
            report("OK", "_global", "claudekit", f"fork {actual_sha}")
    else:
        report("MISSING", "_global", "claudekit", f"fork not cloned at {p}")
        errors += 1

# 4) bmad: npm package; can't introspect without running npm
bmad_spec = tools.get("bmad")
if bmad_spec and (not filter_tool or filter_tool == "bmad"):
    expected_v = bmad_spec.get("version", "")
    print(f"INFO     bmad expected v{expected_v} (npm; per-trial install runs `npx bmad-method@{expected_v}`)")

# 5) Claude CLI version
cli_spec = lock.get("claude_cli") or {}
if cli_spec and (not filter_tool or filter_tool == "claude-cli"):
    expected_v = cli_spec.get("version", "")
    cli_bin = os.environ.get("BENCH_CLAUDE_BIN") or "claude"
    try:
        actual_v = subprocess.check_output([cli_bin, "--version"], stderr=subprocess.DEVNULL).decode().strip().split()[0]
    except Exception:
        actual_v = "?"
    if expected_v and actual_v != expected_v:
        report("DRIFT", "_global", "claude-cli", f"installed={actual_v} expected={expected_v}")
    else:
        report("OK", "_global", "claude-cli", actual_v)

# 6) Base repos
br = lock.get("base_repos") or {}
for task, spec in br.items():
    if filter_tool and filter_tool != f"base-{task}":
        continue
    expected_full = spec.get("sha", "")
    short = spec.get("short", "")
    repo_path = os.environ.get("BASE_REPO") or ""
    if not repo_path:
        # fall back to env.sh
        try:
            for task_env in [task]:
                env = subprocess.check_output(
                    ["bash", "-c", f"TASK={task_env} source scripts/env.sh && echo $BASE_REPO"],
                    stderr=subprocess.DEVNULL).decode().strip()
                if env:
                    repo_path = env.splitlines()[-1]
        except Exception:
            pass
    if not repo_path or not os.path.isdir(repo_path):
        print(f"INFO     base-repo:{task} expected sha={short} (BASE_REPO unset; cannot verify)")
        continue
    try:
        actual_full = subprocess.check_output(
            ["git", "-C", repo_path, "rev-parse", short],
            stderr=subprocess.DEVNULL).decode().strip()
    except Exception:
        actual_full = "?"
    if expected_full and actual_full != expected_full:
        report("DRIFT", "_base", f"base-repo:{task}", f"installed={actual_full[:9]} expected={expected_full[:9]}")
    else:
        report("OK", "_base", f"base-repo:{task}", actual_full[:9])

print()
if errors == 0:
    print(f"PASS — {checked} (trial, tool) pairs match versions.lock.json")
    sys.exit(0)
else:
    print(f"FAIL — {errors} drift / missing / parse errors across {checked} checked entries")
    sys.exit(1)
PY
