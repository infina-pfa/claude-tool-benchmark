#!/bin/bash
# Sets up tool-specific config for a trial
# Usage: ./setup-tool-config.sh <tool> <trial>
source "$(dirname "$0")/env.sh"

TOOL=$1; TRIAL=$2
if [ -z "$TOOL" ] || [ -z "$TRIAL" ]; then
  echo "Usage: ./setup-tool-config.sh <tool> <trial>"
  echo "Tools: ${TOOLS[*]}"
  exit 1
fi

TOOL_CONFIG="$CONFIG_DIR/${TOOL}-t${TRIAL}"
CLONE_DIR="$RUNS_DIR/${TOOL}-t${TRIAL}"
mkdir -p "$TOOL_CONFIG"

echo "=== Setting up $TOOL t$TRIAL ==="

case "$TOOL" in
  x-skills)
    echo "Installing x-skills + x-omo + superpowers + OMC plugin..."
    REAL_HOME="/Users/randytran"

    # Copy user-level skills (x-do, x-research, etc.) into CLAUDE_CONFIG_DIR/skills
    mkdir -p "$TOOL_CONFIG/skills"
    for skill in x-do x-research x-bugfix x-review x-shared x-omo; do
      if [ -d "$REAL_HOME/.claude/skills/$skill" ]; then
        cp -r "$REAL_HOME/.claude/skills/$skill" "$TOOL_CONFIG/skills/"
        echo "  Copied $skill"
      else
        echo "  WARNING: $skill not found at ~/.claude/skills/$skill"
      fi
    done

    # Install OMC + superpowers plugins properly via `claude plugin`.
    # x-do references oh-my-claudecode:code-reviewer (Agent tool) and
    # superpowers:requesting-code-review (Skill tool). These require the
    # plugins to be formally installed (not just cached) so Claude Code
    # discovers the agents/skills at session start.
    rm -rf "$TOOL_CONFIG/plugins"
    echo "  Adding OMC marketplace..."
    CLAUDE_CONFIG_DIR="$TOOL_CONFIG" claude plugin marketplace add \
      https://github.com/Yeachan-Heo/oh-my-claudecode.git 2>&1 | tail -2
    echo "  Installing OMC plugin..."
    CLAUDE_CONFIG_DIR="$TOOL_CONFIG" claude plugin install oh-my-claudecode@omc 2>&1 | tail -2
    echo "  Adding superpowers marketplace..."
    CLAUDE_CONFIG_DIR="$TOOL_CONFIG" claude plugin marketplace add \
      obra/superpowers-marketplace 2>&1 | tail -2
    echo "  Installing superpowers plugin..."
    CLAUDE_CONFIG_DIR="$TOOL_CONFIG" claude plugin install \
      superpowers@superpowers-marketplace 2>&1 | tail -2

    # x-do/x-review reference ~/.claude/skills/x-omo/omo-agent as a literal bash path.
    # In bench env, ~ = $BENCH_HOME, so we need that path to resolve.
    # Also: omo-agent calls `opencode`, which reads auth from ~/.local/share/opencode
    # and config from ~/.config/opencode. Symlink these from the real user dirs so
    # cross-model review works while keeping Claude Code isolated via CLAUDE_CONFIG_DIR.
    mkdir -p "$BENCH_HOME/.claude/skills"
    ln -sfn "$REAL_HOME/.claude/skills/x-omo" "$BENCH_HOME/.claude/skills/x-omo"
    echo "  Symlinked $BENCH_HOME/.claude/skills/x-omo → $REAL_HOME/.claude/skills/x-omo"
    mkdir -p "$BENCH_HOME/.local/share" "$BENCH_HOME/.config"
    ln -sfn "$REAL_HOME/.local/share/opencode" "$BENCH_HOME/.local/share/opencode"
    ln -sfn "$REAL_HOME/.config/opencode" "$BENCH_HOME/.config/opencode"
    echo "  Symlinked opencode data + config dirs (auth passthrough)"
    ;;

  superpower)
    echo "Installing superpowers plugin..."
    # Authoritative check: grep for the installed-plugin form `superpowers@`.
    # Bare `grep -q "superpowers"` matched the marketplace dir name on disk
    # even when the plugin itself was never registered → silent-failed trials.
    if CLAUDE_CONFIG_DIR="$TOOL_CONFIG" claude plugin list 2>/dev/null | grep -q "superpowers@"; then
      echo "  Superpowers plugin already installed, skipping"
    else
      # Scrub any stale partial install: dirs + settings.json + known_marketplaces.
      rm -rf "$TOOL_CONFIG/plugins/marketplaces/superpowers-marketplace" \
             "$TOOL_CONFIG/plugins/data/superpowers-superpowers-marketplace" \
             "$TOOL_CONFIG/plugins/cache/superpowers-marketplace"
      for f in "$TOOL_CONFIG/settings.json" "$TOOL_CONFIG/plugins/known_marketplaces.json"; do
        [ -f "$f" ] && python3 -c "
import json, sys
p = sys.argv[1]
d = json.load(open(p))
changed = False
if 'extraKnownMarketplaces' in d and 'superpowers-marketplace' in d['extraKnownMarketplaces']:
    del d['extraKnownMarketplaces']['superpowers-marketplace']; changed = True
if 'enabledPlugins' in d:
    for plug_key in list(d['enabledPlugins'].keys()):
        if 'superpowers' in plug_key:
            del d['enabledPlugins'][plug_key]; changed = True
if 'superpowers-marketplace' in d:
    del d['superpowers-marketplace']; changed = True
if changed:
    json.dump(d, open(p, 'w'), indent=2)
" "$f" 2>/dev/null
      done
      CLAUDE_CONFIG_DIR="$TOOL_CONFIG" claude plugin marketplace add \
        obra/superpowers-marketplace 2>&1 | tail -2
      CLAUDE_CONFIG_DIR="$TOOL_CONFIG" claude plugin install \
        superpowers@superpowers-marketplace 2>&1 | tail -2
      if ! CLAUDE_CONFIG_DIR="$TOOL_CONFIG" claude plugin list 2>/dev/null | grep -q "superpowers@"; then
        echo "  FAIL: superpowers plugin install did not register"
        exit 1
      fi
    fi
    ;;

  claudekit)
    echo "Installing claudekit into clone..."
    CLAUDEKIT_REPO="/tmp/internal-claudekit"
    # Pinned to a private Infina fork of claudekit master @ <pinned>
    # (full SHA in versions.lock.json). Override the source by exporting
    # CLAUDEKIT_CLONE_SOURCE / CLAUDEKIT_CLONE_SHA before invoking this script.
    CLAUDEKIT_CLONE_SOURCE="${CLAUDEKIT_CLONE_SOURCE:-a private Infina fork of claudekit}"
    CLAUDEKIT_CLONE_SHA="${CLAUDEKIT_CLONE_SHA:-<pinned>}"
    if [ ! -d "$CLAUDEKIT_REPO" ]; then
      echo "  Cloning $CLAUDEKIT_CLONE_SOURCE..."
      gh repo clone "$CLAUDEKIT_CLONE_SOURCE" "$CLAUDEKIT_REPO" 2>/dev/null
    fi
    if [ -d "$CLAUDEKIT_REPO/.git" ]; then
      # Refresh + checkout to pinned SHA so reruns match the lockfile
      git -C "$CLAUDEKIT_REPO" fetch origin --quiet 2>/dev/null
      git -C "$CLAUDEKIT_REPO" checkout "$CLAUDEKIT_CLONE_SHA" --quiet 2>/dev/null \
        || echo "  WARNING: checkout $CLAUDEKIT_CLONE_SHA failed; using whatever HEAD is"
    fi
    if [ -d "$CLAUDEKIT_REPO/.claude" ]; then
      # Back up original CLAUDE.md
      cp "$CLONE_DIR/CLAUDE.md" "$CLONE_DIR/CLAUDE.md.original" 2>/dev/null
      # Replace .claude dir with latest claudekit content
      rm -rf "$CLONE_DIR/.claude"
      cp -r "$CLAUDEKIT_REPO/.claude" "$CLONE_DIR/.claude"
      # Copy claudekit CLAUDE.md
      cp "$CLAUDEKIT_REPO/CLAUDE.md" "$CLONE_DIR/CLAUDE.md"
      # Create plans/ dir (claudekit writes plans here)
      mkdir -p "$CLONE_DIR/plans"
      # Append project context to CLAUDE.md
      cat >> "$CLONE_DIR/CLAUDE.md" << 'CTXEOF'

## Project Context

This is an internal NX monorepo for financial services. The original project conventions are preserved in `./CLAUDE.md.original` — read it for architecture, commands, path aliases, and testing patterns.

Key project details:
- **Framework**: NestJS 11.x + TypeORM + Temporal.io
- **Language**: TypeScript 5.8
- **Monorepo**: NX 21.x
- **Testing**: Jest 30.x (`yarn test <app>`)
- **Package Manager**: Yarn
- **Library hierarchy**: `libs/common > libs/utils > libs/domain > libs/api > libs/user - libs/core > apps`
CTXEOF
      # Fix hook node paths for isolated bench env (env -i strips NVM from PATH)
      NODE_BIN=$(which node)
      if [ -n "$NODE_BIN" ]; then
        sed -i.bak "s|\"command\": \"node |\"command\": \"$NODE_BIN |g" "$CLONE_DIR/.claude/settings.json"
        rm -f "$CLONE_DIR/.claude/settings.json.bak"
        echo "  Fixed hook node paths to $NODE_BIN"
      fi
      echo "  Installed claudekit into $CLONE_DIR"
      # Commit setup changes so verify-clean sees a clean working tree
      cd "$CLONE_DIR"
      git add -A && git commit -m "chore: install claudekit config" --quiet 2>/dev/null
      cd "$BENCH_HOME"
    else
      echo "  FAIL: claudekit .claude dir not found at $CLAUDEKIT_REPO"
      exit 1
    fi
    ;;

  omc)
    echo "Installing OMC plugin into config..."
    # Install OMC plugin so agents/skills are discoverable at session start.
    # User must still run /oh-my-claudecode:omc-setup as the FIRST prompt in
    # the bench session to bootstrap CLAUDE.md injection, hooks, and .omc/ state.
    if CLAUDE_CONFIG_DIR="$TOOL_CONFIG" claude plugin list 2>/dev/null | grep -q "oh-my-claudecode"; then
      echo "  OMC plugin already installed, skipping"
    else
      CLAUDE_CONFIG_DIR="$TOOL_CONFIG" claude plugin marketplace add \
        https://github.com/Yeachan-Heo/oh-my-claudecode.git 2>&1 | tail -2
      # Pin to v4.13.6 tag commit (8b24a29d). Marketplace clone is shallow —
      # unshallow first so checkout can find the historical SHA.
      git -C "$TOOL_CONFIG/plugins/marketplaces/omc" fetch --unshallow 2>&1 | tail -1 || true
      git -C "$TOOL_CONFIG/plugins/marketplaces/omc" checkout 8b24a29d 2>&1 | tail -1
      CLAUDE_CONFIG_DIR="$TOOL_CONFIG" claude plugin install oh-my-claudecode@omc 2>&1 | tail -2
    fi
    echo "  IMPORTANT: Run /oh-my-claudecode:omc-setup as first prompt in bench session"
    ;;

  bmad)
    echo "Installing BMad Method v6.6.0 into clone..."
    # BMad writes to .claude/skills/bmad-* and _bmad/ (both gitignored by the
    # benchmark safety gitignore), plus _bmad-output/ (tracked — phase artifacts
    # go here). Install pre-session so verify-clean passes when bench-run.sh runs.
    if [ -d "$CLONE_DIR/_bmad" ]; then
      echo "  BMad already installed at $CLONE_DIR/_bmad, skipping"
    else
      (cd "$CLONE_DIR" && npx bmad-method@6.6.0 install \
        --directory . --modules bmm --tools claude-code --yes) 2>&1 | tail -5
      echo "  Installed BMad into $CLONE_DIR"
    fi
    ;;

  pure)
    echo "Pure Claude Code — no external tools to install."
    echo "Config dir stays empty (no plugins, no MCP, no skills, no hooks)."
    ;;

  gstack)
    echo "Installing gstack into trial config..."
    # Per-trial isolation: clone gstack into $TOOL_CONFIG/skills/gstack and run
    # ./setup --no-prefix from there. setup detects its own location and
    # registers skill dirs into the parent ($TOOL_CONFIG/skills/), which
    # Claude Code reads when CLAUDE_CONFIG_DIR points at $TOOL_CONFIG.
    # HOME override keeps ~/.gstack/ and ~/.codex/ writes inside $TOOL_CONFIG.
    GSTACK_DIR="$TOOL_CONFIG/skills/gstack"
    if [ -f "$GSTACK_DIR/ship/SKILL.md" ]; then
      echo "  gstack already installed, skipping"
    else
      mkdir -p "$TOOL_CONFIG/skills"
      rm -rf "$GSTACK_DIR"
      git clone https://github.com/garrytan/gstack.git "$GSTACK_DIR" 2>&1 | tail -3
      git -C "$GSTACK_DIR" checkout 443bde05 2>&1 | tail -3
      (cd "$GSTACK_DIR" && HOME="$TOOL_CONFIG" ./setup --no-prefix) 2>&1 | tail -5
      echo "  Installed gstack into $TOOL_CONFIG/skills/"
    fi
    ;;
  compound)
    echo "Installing compound plugin..."
    # Pinned target: compound-engineering-v3.7.0 (released 2026-05-07).
    # `claude plugin install` does not support per-SHA pinning; lockfile in
    # versions.lock.json (Phase 1) records the expected tag, and a post-install
    # verify step in scripts/verify-versions.sh (Phase 1) will compare the
    # installed plugin.json version against this target.
    if CLAUDE_CONFIG_DIR="$TOOL_CONFIG" claude plugin list 2>/dev/null | grep -q "compound"; then
      echo "  compound plugin already installed, skipping"
    else
      CLAUDE_CONFIG_DIR="$TOOL_CONFIG" claude plugin marketplace add \
        EveryInc/compound-engineering-plugin 2>&1 | tail -2
      # Pin to compound-engineering-v3.7.0 tag commit (0bb53dfa). Marketplace
      # clone is shallow — unshallow first.
      git -C "$TOOL_CONFIG/plugins/marketplaces/compound-engineering-plugin" fetch --unshallow 2>&1 | tail -1 || true
      git -C "$TOOL_CONFIG/plugins/marketplaces/compound-engineering-plugin" checkout 0bb53dfa 2>&1 | tail -1
      CLAUDE_CONFIG_DIR="$TOOL_CONFIG" claude plugin install \
        compound-engineering@compound-engineering-plugin 2>&1 | tail -2
    fi
    ;;
  ecc)
    echo "Installing ecc plugin..."
    # Authoritative check: `claude plugin list` shows the plugin as enabled.
    # Grep on `everything-claude-code` (the plugin name from marketplace.json
    # at the pinned SHA), NOT on bare "ecc" — that previously matched the
    # marketplace alias dir and produced false-positive skips → silent trials.
    if CLAUDE_CONFIG_DIR="$TOOL_CONFIG" claude plugin list 2>/dev/null | grep -q "everything-claude-code@"; then
      echo "  ecc plugin already installed, skipping"
    else
      # Scrub any stale partial install before re-attempting. Three layers:
      #   1. marketplace dirs on disk (alias may be `ecc` since upstream renamed)
      #   2. settings.json (extraKnownMarketplaces entries)
      #   3. plugins/known_marketplaces.json (marketplace registry consulted
      #      before re-add — without scrubbing, CLI says "already on disk")
      rm -rf "$TOOL_CONFIG/plugins/marketplaces/ecc" \
             "$TOOL_CONFIG/plugins/marketplaces/everything-claude-code" \
             "$TOOL_CONFIG/plugins/data/everything-claude-code-everything-claude-code" \
             "$TOOL_CONFIG/plugins/data/everything-claude-code-ecc" \
             "$TOOL_CONFIG/plugins/cache/everything-claude-code" \
             "$TOOL_CONFIG/plugins/cache/ecc"
      for stale_key in ecc everything-claude-code; do
        for f in "$TOOL_CONFIG/settings.json" "$TOOL_CONFIG/plugins/known_marketplaces.json"; do
          [ -f "$f" ] && python3 -c "
import json, sys
p = sys.argv[1]; key = sys.argv[2]
d = json.load(open(p))
changed = False
if 'extraKnownMarketplaces' in d and key in d['extraKnownMarketplaces']:
    del d['extraKnownMarketplaces'][key]; changed = True
if 'enabledPlugins' in d:
    for plug_key in list(d['enabledPlugins'].keys()):
        if key in plug_key:
            del d['enabledPlugins'][plug_key]; changed = True
if key in d:
    del d[key]; changed = True
if changed:
    json.dump(d, open(p, 'w'), indent=2)
" "$f" "$stale_key" 2>/dev/null
        done
      done
      # Add marketplace (upstream's marketplace.json self-declares name `ecc`
      # on HEAD; the CLI now derives alias from that, not the URL slug).
      CLAUDE_CONFIG_DIR="$TOOL_CONFIG" claude plugin marketplace add \
        https://github.com/affaan-m/everything-claude-code 2>&1 | tail -2
      # Pin to v1.10.0 tag commit (846ffb75). At that SHA the upstream
      # marketplace.json declares plugin name `everything-claude-code`, so
      # the install command uses that plugin name combined with the CLI's
      # alias `ecc` for the marketplace.
      git -C "$TOOL_CONFIG/plugins/marketplaces/ecc" fetch --unshallow 2>&1 | tail -1 || true
      git -C "$TOOL_CONFIG/plugins/marketplaces/ecc" checkout 846ffb75 2>&1 | tail -1
      CLAUDE_CONFIG_DIR="$TOOL_CONFIG" claude plugin install \
        everything-claude-code@ecc 2>&1 | tail -2
      # Verify install actually registered the plugin; bail loudly if not.
      if ! CLAUDE_CONFIG_DIR="$TOOL_CONFIG" claude plugin list 2>/dev/null | grep -q "everything-claude-code@"; then
        echo "  FAIL: ecc plugin install did not register everything-claude-code"
        exit 1
      fi
    fi
    ;;
  *)
    echo "Unknown tool: $TOOL"
    exit 1
    ;;
esac

echo "=== Done ==="
