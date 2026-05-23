#!/bin/bash
# add-tool.sh — onboard a new tool to the benchmark.
#
# Interactive prompt that wires a new tool into:
#   - scripts/env.sh                       (TOOLS array)
#   - scripts/setup-tool-config.sh         (per-tool install case)
#   - scripts/manual-bench.sh              (per-tool prompt case + plan-mode guard)
#   - scripts/create-clones.sh             (gitignore safety patterns)
#   - docs/plans/one-shot-prompts.md       (playbook section)
#   - docs/methodology/pipeline.md         (tools list)
#
# Use --dry-run to see what would change without writing.
# Usage: ./scripts/add-tool.sh [--dry-run]

set -euo pipefail
source "$(dirname "$0")/env.sh"

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

echo "=== Add tool to benchmark ==="
echo "Current tools: ${TOOLS[*]}"
[ "$DRY_RUN" = "1" ] && echo "(DRY-RUN mode: no files will be modified)"
echo ""

ask() {
  local prompt=$1 default=${2:-} reply
  if [ -n "$default" ]; then
    read -r -p "$prompt [$default]: " reply
    echo "${reply:-$default}"
  else
    read -r -p "$prompt: " reply
    echo "$reply"
  fi
}

NAME=$(ask "Tool short name (lowercase, e.g. 'gstack')")
if [ -z "$NAME" ]; then echo "FAIL: name required" >&2; exit 1; fi
if ! [[ "$NAME" =~ ^[a-z][a-z0-9_-]*$ ]]; then
  echo "FAIL: name must be lowercase alnum + dash/underscore, start with letter" >&2; exit 1
fi
for t in "${TOOLS[@]}"; do
  if [ "$t" = "$NAME" ]; then
    echo "FAIL: tool '$NAME' already exists in TOOLS" >&2; exit 1
  fi
done

DESC=$(ask "One-line description (for docs)")
echo ""
echo "Install type:"
echo "  1) plugin — Claude Code plugin from a marketplace (most common)"
echo "  2) clone  — files copied into the run clone (bmad/claudekit style)"
echo "  3) npm    — npx-based installer into the clone (bmad-method style)"
echo "  4) none   — no install (pure Claude Code)"
INSTALL_CHOICE=$(ask "Choice [1-4]" "1")
case "$INSTALL_CHOICE" in
  1) INSTALL_TYPE=plugin ;;
  2) INSTALL_TYPE=clone ;;
  3) INSTALL_TYPE=npm ;;
  4) INSTALL_TYPE=none ;;
  *) echo "FAIL: invalid choice" >&2; exit 1 ;;
esac

MARKETPLACE=""
PLUGIN_ID=""
CLONE_SRC=""
CLONE_COPY=""
NPM_PKG=""
NPM_ARGS=""
case "$INSTALL_TYPE" in
  plugin)
    MARKETPLACE=$(ask "Marketplace (e.g. 'obra/superpowers-marketplace' or full git URL)")
    PLUGIN_ID=$(ask "Plugin id (e.g. 'superpowers@superpowers-marketplace')")
    ;;
  clone)
    CLONE_SRC=$(ask "Source repo (GitHub URL or local path)")
    CLONE_COPY=$(ask "Subpath to copy into clone (e.g. '.claude' or '.')" ".")
    ;;
  npm)
    NPM_PKG=$(ask "npm package spec (e.g. 'bmad-method@6.3.0')")
    NPM_ARGS=$(ask "Install command args (after 'install ')" "--yes")
    ;;
esac

echo ""
PLAN_MODE_YN=$(ask "Needs native plan mode? (y/n)" "n")
PLAN_MODE=no
[[ "$PLAN_MODE_YN" =~ ^[Yy] ]] && PLAN_MODE=yes

echo ""
echo "Prompt prefix — text prepended to the shared task block."
echo "Examples:"
echo "  'Use /${NAME}:plan to scope this task, then execute it with /${NAME}:run.'"
echo "  'Run /${NAME}:bootstrap first. Then work through this task.'"
echo "  (leave empty for no prefix — bare task like 'pure'/'superpower')"
PROMPT_PREFIX=$(ask "Prefix (single line)")

echo ""
GITIGNORE=$(ask "Gitignore safety patterns (space-sep, e.g. '.${NAME}/ _${NAME}/')" "")

# Summary
cat <<SUMMARY

----- Summary -----
Name:          $NAME
Description:   $DESC
Install type:  $INSTALL_TYPE
  marketplace: ${MARKETPLACE:--}
  plugin id:   ${PLUGIN_ID:--}
  clone src:   ${CLONE_SRC:--}
  clone copy:  ${CLONE_COPY:--}
  npm pkg:     ${NPM_PKG:--}
  npm args:    ${NPM_ARGS:--}
Plan mode:     $PLAN_MODE
Prompt prefix: ${PROMPT_PREFIX:--}
Gitignore:     ${GITIGNORE:--}
-------------------

SUMMARY

CONFIRM=$(ask "Apply changes? (y/n)" "y")
[[ "$CONFIRM" =~ ^[Yy] ]] || { echo "aborted"; exit 0; }

# Structured edits via Python — reliable multi-line insertion.
python3 - "$BENCH_HOME" "$NAME" "$DESC" "$INSTALL_TYPE" \
  "$MARKETPLACE" "$PLUGIN_ID" "$CLONE_SRC" "$CLONE_COPY" \
  "$NPM_PKG" "$NPM_ARGS" "$PLAN_MODE" "$PROMPT_PREFIX" "$GITIGNORE" "$DRY_RUN" <<'PY'
import sys, re
from pathlib import Path

(bench_home, name, desc, install_type, marketplace, plugin_id,
 clone_src, clone_copy, npm_pkg, npm_args, plan_mode,
 prompt_prefix, gitignore, dry_run) = sys.argv[1:]

dry_run = dry_run == "1"
bench = Path(bench_home)

changes = []

def write(path, content):
    if dry_run:
        changes.append(f"[dry-run] would write {path}")
    else:
        path.write_text(content)
        changes.append(f"modified {path.relative_to(bench)}")

# -----------------------------------------------------------------------
# 1. env.sh — append name to TOOLS array
# -----------------------------------------------------------------------
env_sh = bench / "scripts/env.sh"
txt = env_sh.read_text()
# Match TOOLS=(a b c)
def add_to_tools(m):
    inner = m.group(1).rstrip()
    return f"TOOLS=({inner} {name})"
new = re.sub(r'TOOLS=\(([^)]*)\)', add_to_tools, txt)
if new == txt:
    print(f"WARN: TOOLS array not found in env.sh", file=sys.stderr)
else:
    write(env_sh, new)

# -----------------------------------------------------------------------
# 2. setup-tool-config.sh — insert new case block before *)
# -----------------------------------------------------------------------
setup_sh = bench / "scripts/setup-tool-config.sh"
txt = setup_sh.read_text()

if install_type == "plugin":
    block = f"""  {name})
    echo "Installing {name} plugin..."
    if CLAUDE_CONFIG_DIR="$TOOL_CONFIG" claude plugin list 2>/dev/null | grep -q "{name}"; then
      echo "  {name} plugin already installed, skipping"
    else
      CLAUDE_CONFIG_DIR="$TOOL_CONFIG" claude plugin marketplace add \\
        {marketplace} 2>&1 | tail -2
      CLAUDE_CONFIG_DIR="$TOOL_CONFIG" claude plugin install \\
        {plugin_id} 2>&1 | tail -2
    fi
    ;;
"""
elif install_type == "clone":
    block = f"""  {name})
    echo "Installing {name} into clone..."
    {name.upper()}_REPO="/tmp/{name}-src"
    if [ ! -d "${name.upper()}_REPO" ]; then
      echo "  Cloning {clone_src}..."
      gh repo clone {clone_src} "${name.upper()}_REPO" 2>/dev/null || \\
        git clone {clone_src} "${name.upper()}_REPO" 2>/dev/null
    fi
    if [ -d "${name.upper()}_REPO/{clone_copy}" ]; then
      cp -r "${name.upper()}_REPO/{clone_copy}" "$CLONE_DIR/" 2>/dev/null || true
      echo "  Installed {name} from ${name.upper()}_REPO/{clone_copy} → $CLONE_DIR"
    else
      echo "  FAIL: {clone_copy} not found in ${name.upper()}_REPO"
      exit 1
    fi
    ;;
"""
elif install_type == "npm":
    block = f"""  {name})
    echo "Installing {name} ({npm_pkg}) into clone..."
    (cd "$CLONE_DIR" && npx {npm_pkg} install {npm_args}) 2>&1 | tail -5
    echo "  Installed {name} into $CLONE_DIR"
    ;;
"""
else:  # none
    block = f"""  {name})
    echo "{name} — no external tools to install."
    ;;
"""

# Insert before the *)  default case
new = re.sub(
    r'(  \*\))',
    block + r'\1',
    txt,
    count=1,
)
if new == txt:
    print(f"WARN: default *) case not found in setup-tool-config.sh", file=sys.stderr)
else:
    write(setup_sh, new)

# -----------------------------------------------------------------------
# 3. manual-bench.sh — insert per-tool prompt case + plan-mode guard
# -----------------------------------------------------------------------
mb_sh = bench / "scripts/manual-bench.sh"
txt = mb_sh.read_text()

# 3a. Per-tool PROMPT case block. Insert before the "*)" default.
if prompt_prefix.strip():
    escaped_prefix = prompt_prefix.replace('"', r'\"')
    prompt_block = f"""  {name})
    PROMPT="{escaped_prefix}

$SHARED_TASK"
    ;;
"""
else:
    prompt_block = f"""  {name})
    PROMPT="$SHARED_TASK"
    ;;
"""

# Find the per-tool case (the one that builds PROMPT). It's the case after SHARED_TASK.
# We match the specific "*)" line that sets PROMPT="$SHARED_TASK" as default.
new = re.sub(
    r'(  \*\)\n    PROMPT="\$SHARED_TASK")',
    prompt_block + r'\1',
    txt,
    count=1,
)
if new == txt:
    print(f"WARN: per-tool PROMPT case not found in manual-bench.sh", file=sys.stderr)
else:
    txt = new

# 3b. Plan-mode guard — if plan_mode=yes, extend the pure list.
if plan_mode == "yes":
    new = re.sub(
        r'(  pure(?:\|[a-z0-9_-]+)*)(\))',
        lambda m: f"{m.group(1)}|{name}{m.group(2)}",
        txt,
        count=1,
    )
    if new == txt:
        print(f"WARN: plan-mode guard (pure) not found in manual-bench.sh", file=sys.stderr)
    else:
        txt = new

write(mb_sh, txt)

# -----------------------------------------------------------------------
# 4. create-clones.sh — add gitignore safety patterns (if any)
# -----------------------------------------------------------------------
if gitignore.strip():
    cc_sh = bench / "scripts/create-clones.sh"
    txt = cc_sh.read_text()
    patterns = gitignore.split()
    existing = set()
    # Find the gitignore heredoc block
    m = re.search(r"(# Benchmark safety\n(?:.+\n)+?)GITIGNORE", txt)
    if m:
        existing_block = m.group(1)
        for p in existing_block.split('\n'):
            existing.add(p.strip())
        new_lines = [p for p in patterns if p not in existing]
        if new_lines:
            insertion = '\n'.join(new_lines) + '\n'
            new = txt.replace(existing_block, existing_block + insertion)
            write(cc_sh, new)

# -----------------------------------------------------------------------
# 5. docs/plans/one-shot-prompts.md — append playbook section
# -----------------------------------------------------------------------
doc = bench / "docs/plans/one-shot-prompts.md"
if doc.exists():
    dtxt = doc.read_text()
    section = f"""
## Tool: {name}

**Description:** {desc}

**Install type:** {install_type}"""
    if install_type == "plugin":
        section += f"\n- Marketplace: `{marketplace}`\n- Plugin: `{plugin_id}`"
    elif install_type == "clone":
        section += f"\n- Source: `{clone_src}`\n- Copies `{clone_copy}` into clone"
    elif install_type == "npm":
        section += f"\n- Package: `{npm_pkg}` (args: `{npm_args}`)"
    section += f"\n\n**Plan mode:** {'yes (paired with --permission-mode plan)' if plan_mode == 'yes' else 'no (tool uses its own planning workflow or none)'}\n"
    section += f"""
**Launch:**
```bash
cd "$BENCH_HOME/runs/{name}-t<trial>"
env CLAUDE_CONFIG_DIR="$BENCH_HOME/config/{name}-t<trial>" claude{' --permission-mode plan' if plan_mode == 'yes' else ''}
```

**Initial prompt:**
```
{prompt_prefix + chr(10) + chr(10) if prompt_prefix.strip() else ''}<SHARED TASK BLOCK>
```
"""
    # Insert before the final "## Running a Manual Trial" section.
    # Put it after the preceding "---" separator so we don't stack separators.
    marker = "---\n\n## Running a Manual Trial"
    if marker in dtxt:
        dtxt = dtxt.replace(marker, f"{section}\n---\n\n## Running a Manual Trial")
    elif "## Running a Manual Trial" in dtxt:
        dtxt = dtxt.replace("## Running a Manual Trial", f"{section}\n---\n\n## Running a Manual Trial")
    else:
        dtxt += section
    write(doc, dtxt)

# -----------------------------------------------------------------------
# 6. docs/methodology/pipeline.md — update tools count + list and total runs
# -----------------------------------------------------------------------
pipe = bench / "docs/methodology/pipeline.md"
if pipe.exists():
    ptxt = pipe.read_text()
    changed = False

    # Bump "Tools under test (N):" count and append the new tool before the trailing period.
    def bump_tools(m):
        prefix, count, sep, body = m.group(1), int(m.group(2)), m.group(3), m.group(4)
        body = body.rstrip()
        if body.endswith('.'):
            body = body[:-1].rstrip() + f", `{name}`."
        else:
            body = body + f", `{name}`"
        return f"{prefix}{count+1}{sep}{body}"

    new = re.sub(
        r'(\*\*Tools under test \()(\d+)(\):\*\* )([^\n]+)',
        bump_tools,
        ptxt,
        count=1,
    )
    if new != ptxt:
        ptxt = new
        changed = True

    # Bump "N trials → M runs total" (N tools × 3 trials)
    def bump_runs(m):
        old_total = int(m.group(1))
        return f"**{old_total + 3} runs total**"
    new = re.sub(r'\*\*(\d+) runs total\*\*', bump_runs, ptxt, count=1)
    if new != ptxt:
        ptxt = new
        changed = True

    if changed:
        write(pipe, ptxt)

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
print()
for c in changes:
    print("  " + c)
PY

echo ""
if [ "$DRY_RUN" = "1" ]; then
  echo "Dry-run complete. Rerun without --dry-run to apply."
  exit 0
fi

# Verify syntax of modified shell scripts
echo ""
echo "=== Syntax check ==="
for f in scripts/env.sh scripts/setup-tool-config.sh scripts/manual-bench.sh scripts/create-clones.sh; do
  if bash -n "$BENCH_HOME/$f" 2>&1; then
    echo "  ✓ $f"
  else
    echo "  ✗ $f — SYNTAX ERROR" >&2
    exit 1
  fi
done

echo ""
CREATE_NOW=$(ask "Create clones + config dirs for ${NAME} T1/T2/T3 now? (y/n)" "y")
if [[ "$CREATE_NOW" =~ ^[Yy] ]]; then
  echo ""
  echo "=== Creating clones ==="
  "$SCRIPTS_DIR/create-clones.sh"
fi

echo ""
echo "=== Done ==="
echo ""
echo "Next steps:"
echo "  1. Review the diff:"
echo "     git -C $BENCH_HOME diff scripts/ docs/"
echo ""
echo "  2. Install tool config for each trial:"
echo "     ./scripts/setup-tool-config.sh $NAME 1"
echo "     ./scripts/setup-tool-config.sh $NAME 2"
echo "     ./scripts/setup-tool-config.sh $NAME 3"
echo ""
echo "  3. Run a trial:"
echo "     ./scripts/manual-bench.sh $NAME 1"
