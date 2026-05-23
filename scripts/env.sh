#!/bin/bash
# Source this in all benchmark scripts: source "$(dirname "$0")/env.sh"
#
# Task selection: export TASK=<task-id> before sourcing, or pass as an arg.
# Supported tasks (all drawn from an internal TypeScript financial-services
# monorepo; referenced here as `$BENCH_REPO` — set this to a clone URL
# of your own target repo before running):
#   feature   — greenfield feature build from a PRD
#   bugfix    — fix an inventory-filter bug reported by QA
#   refactor  — aggregate-ownership + port-decoupling refactor
#
# Layout (feature uses the flat root layout for backward compat with the
# 36 pre-existing blind-eval labels; the other two are nested):
#   feature   runs/{tool}-t{trial}         results/...         config/...
#   bugfix    runs/bugfix/{tool}-t{T}      results/bugfix/*    config/bugfix/*
#   refactor  runs/refactor/{tool}-t{T}    results/refactor/*  config/refactor/*

export BENCH_HOME="${BENCH_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# Set this to the clone URL of the target repo. Kept as a placeholder so
# this script can be shared publicly without leaking the internal repo.
export BENCH_REPO="${BENCH_REPO:-<internal-sdk-repo>}"
export SCRIPTS_DIR=$BENCH_HOME/scripts
export TASK=${TASK:-feature}

# Legacy aliases: accept the pre-rename task IDs and normalize them.
case "$TASK" in
  mode2)    TASK=feature  ;;
  shp2376)  TASK=bugfix   ;;
  shp2317)  TASK=refactor ;;
esac
export TASK

case "$TASK" in
  feature)
    export BASE_REPO="$BENCH_HOME/runs/base-feature"
    export BENCH_COMMIT="<bench-feature-sha>"
    export PRD_PATH="docs/benchmark/TASK.md"
    export RUNS_DIR=$BENCH_HOME/runs
    export RESULTS_DIR=$BENCH_HOME/results
    export CONFIG_DIR=$BENCH_HOME/config
    ;;
  bugfix)
    export BASE_REPO="$BENCH_HOME/runs/base-bugfix"
    export BENCH_COMMIT="<bench-bugfix-sha>"
    export PRD_PATH="docs/benchmark/TASK.md"
    export RUNS_DIR=$BENCH_HOME/runs/bugfix
    export RESULTS_DIR=$BENCH_HOME/results/bugfix
    export CONFIG_DIR=$BENCH_HOME/config/bugfix
    ;;
  refactor)
    export BASE_REPO="$BENCH_HOME/runs/base-refactor"
    export BENCH_COMMIT="<bench-refactor-sha>"
    export PRD_PATH="docs/benchmark/TASK.md"
    export RUNS_DIR=$BENCH_HOME/runs/refactor
    export RESULTS_DIR=$BENCH_HOME/results/refactor
    export CONFIG_DIR=$BENCH_HOME/config/refactor
    ;;
  *)
    echo "ERROR: unknown TASK=$TASK (supported: feature, bugfix, refactor)" >&2
    exit 1
    ;;
esac

TOOLS=(pure superpower claudekit omc bmad gstack compound ecc)

# Pinned claude CLI for cohort homogeneity (lockfile target 2.1.119).
# Override with BENCH_CLAUDE_BIN=... to point elsewhere.
# Falls back to PATH lookup if pinned binary missing — manual-bench.sh
# enforces version match against versions.lock.json before each trial.
export BENCH_CLAUDE_BIN="${BENCH_CLAUDE_BIN:-$HOME/.local/bench-claude/node_modules/.bin/claude}"
