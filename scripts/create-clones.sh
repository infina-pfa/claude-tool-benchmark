#!/bin/bash
# Creates independent trial clones from the pre-built task base repo
# (runs/base-feature, runs/base-bugfix, runs/base-refactor).
# Usage:
#   ./create-clones.sh             # All tools × trials 1 2 3
#   ./create-clones.sh 4           # All tools × trial 4 only
#   ./create-clones.sh 4 5         # All tools × trials 4 and 5
source "$(dirname "$0")/env.sh"

# BASE_REPO is set by env.sh based on $TASK (feature | bugfix | defer-deposit).
if [ ! -d "$BASE_REPO/.git" ]; then
  echo "ERROR: base repo not found at $BASE_REPO (TASK=$TASK)" >&2
  echo "Create it first (shallow clone with PRD, no remote, single commit)." >&2
  exit 1
fi
mkdir -p "$RUNS_DIR"

# Trial numbers: from args, or default 1 2 3
TRIALS=("${@:-1 2 3}")
if [ $# -eq 0 ]; then
  TRIALS=(1 2 3)
fi

CREATED=0
SKIPPED=0

for tool in "${TOOLS[@]}"; do
  for trial in "${TRIALS[@]}"; do
    CLONE_DIR="$RUNS_DIR/${tool}-t${trial}"
    if [ -d "$CLONE_DIR" ]; then
      echo "SKIP: $CLONE_DIR exists"
      SKIPPED=$((SKIPPED + 1))
    else
      echo "Creating ${tool}-t${trial}..."
      # Shallow clone (depth=1, single branch, no tags) — first-level snapshot
      # only, no parent history. file:// URL forces git to honor --depth on a
      # local source. Strip origin so trials have no upstream link.
      git clone --depth 1 --single-branch --no-tags --quiet \
        "file://$BASE_REPO" "$CLONE_DIR"
      git -C "$CLONE_DIR" remote remove origin 2>/dev/null
      # Gitignored runtime artifacts (node_modules, .nx, .yarn install-state).
      # Shallow clone only checks out tracked files; trials need installed deps
      # to run tests/lint. cp -c uses APFS clonefile (copy-on-write), so the
      # 1.9GB node_modules is effectively free per trial.
      while read -r status path; do
        [ "$status" = "!!" ] || continue
        [ -e "$BASE_REPO/$path" ] || continue
        rm -rf "$CLONE_DIR/$path"
        cp -c -R "$BASE_REPO/$path" "$CLONE_DIR/$path" 2>/dev/null \
          || cp -R "$BASE_REPO/$path" "$CLONE_DIR/$path"
      done < <(git -C "$BASE_REPO" status --ignored --porcelain 2>/dev/null)
      git -C "$CLONE_DIR" checkout -b "benchmark/${tool}-t${trial}" --quiet
      CREATED=$((CREATED + 1))
    fi

    # Ensure config + results dirs exist
    mkdir -p "$CONFIG_DIR/${tool}-t${trial}"
    mkdir -p "$RESULTS_DIR/${tool}/t${trial}/sessions"
  done
done

# Verify
echo ""
echo "=== Verification ==="
for tool in "${TOOLS[@]}"; do
  for trial in "${TRIALS[@]}"; do
    DIR="$RUNS_DIR/${tool}-t${trial}"
    COMMIT=$(git -C "$DIR" log --oneline -1 2>/dev/null || echo "MISSING")
    REMOTE=$(git -C "$DIR" remote -v 2>/dev/null | wc -l | tr -d ' ')
    echo "  ${tool}-t${trial}: $COMMIT (remotes: $REMOTE)"
  done
done

echo ""
echo "Done. Created $CREATED, skipped $SKIPPED."
