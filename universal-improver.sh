#!/usr/bin/env bash
set -euo pipefail

COUNT=1
BUILD_AND_TEST="./build-and-test.sh"
RANDOM_SELECT=0
PARALLEL=1

# Parse: <finder-tool> <fixer-tool> [--count N] [--build-and-test TOOL] [--random] [--parallel N]
POSITIONAL=()
while [ $# -gt 0 ]; do
  case "$1" in
    --count)
      COUNT="$2"
      shift 2
      ;;
    --build-and-test)
      BUILD_AND_TEST="$2"
      shift 2
      ;;
    --random)
      RANDOM_SELECT=1
      shift
      ;;
    --parallel)
      PARALLEL="$2"
      shift 2
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

if [ "${#POSITIONAL[@]}" -lt 2 ]; then
  echo "Usage: universal-improver.cmd <finder-tool> <fixer-tool> --count <N> [--build-and-test <build-and-test-tool>] [--random] [--parallel <N>]" >&2
  exit 1
fi

FINDER_TOOL="${POSITIONAL[0]}"
FIXER_TOOL="${POSITIONAL[1]}"

# --- Preflight checks ---

if [ -n "$(git status --porcelain)" ]; then
  echo "Error: working tree is not clean. Commit or stash your changes before running universal-improver." >&2
  exit 1
fi

if ! "$BUILD_AND_TEST"; then
  echo "Error: build and test failed before any changes were made. Fix the build first." >&2
  exit 1
fi

discard_changes() {
  git checkout -- .
  git clean -fd
}

# --- Find issues ---

FINDER_OUTPUT="$("$FINDER_TOOL")"

ISSUES=()
if [ -n "$FINDER_OUTPUT" ]; then
  while IFS= read -r line; do
    ISSUES+=("$line")
  done <<< "$FINDER_OUTPUT"
fi

if [ "${#ISSUES[@]}" -eq 0 ]; then
  echo "No issues found."
  exit 0
fi

TOTAL_FOUND="${#ISSUES[@]}"

if [ "$RANDOM_SELECT" -eq 1 ]; then
  for ((i = ${#ISSUES[@]} - 1; i > 0; i--)); do
    j=$((RANDOM % (i + 1)))
    tmp="${ISSUES[$i]}"
    ISSUES[i]="${ISSUES[$j]}"
    ISSUES[j]="$tmp"
  done
fi

ATTEMPTED=0
COMMITTED=0
SKIPPED=0

print_summary() {
  echo ""
  echo "=== Summary ==="
  echo "Issues found: $TOTAL_FOUND"
  echo "Issues attempted: $ATTEMPTED"
  echo "Issues committed: $COMMITTED"
  echo "Issues skipped/reverted: $SKIPPED"
}

if [ "$PARALLEL" -le 1 ]; then
  for ((i = 0; i < COUNT && i < ${#ISSUES[@]}; i++)); do
    ISSUE="${ISSUES[$i]}"
    ATTEMPTED=$((ATTEMPTED + 1))

    echo "=== [$ATTEMPTED/$COUNT] Issue: $ISSUE ==="

    if COMMIT_MSG="$("$FIXER_TOOL" "$ISSUE")"; then
      FIXER_EXIT=0
    else
      FIXER_EXIT=$?
    fi

    if [ "$FIXER_EXIT" -ne 0 ] || [ -z "$COMMIT_MSG" ]; then
      echo "Fixer failed or produced no commit message; reverting and continuing."
      discard_changes
      SKIPPED=$((SKIPPED + 1))
      continue
    fi

    if [ -z "$(git status --porcelain)" ]; then
      echo "Fixer made no changes; skipping."
      SKIPPED=$((SKIPPED + 1))
      continue
    fi

    if ! "$BUILD_AND_TEST"; then
      echo "Build failed after fix; reverting and continuing."
      discard_changes
      SKIPPED=$((SKIPPED + 1))
      continue
    fi

    git add -A
    git commit -m "$COMMIT_MSG"
    COMMITTED=$((COMMITTED + 1))
  done

  print_summary
  exit 0
fi

# --- Parallel mode: run each issue in its own git worktree/branch, then merge ---

BASE_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$BASE_BRANCH" = "HEAD" ]; then
  echo "Error: cannot run --parallel in detached HEAD state." >&2
  exit 1
fi
BASE_COMMIT="$(git rev-parse HEAD)"

WORK_BASE="$(mktemp -d)"
mkdir -p "$WORK_BASE/logs" "$WORK_BASE/results"
RUN_ID="$$"

# shellcheck disable=SC2329 # invoked via trap on EXIT below
cleanup_parallel() {
  for ((i = 0; i < COUNT && i < ${#ISSUES[@]}; i++)); do
    git worktree remove --force "$WORK_BASE/wt/$i" >/dev/null 2>&1 || true
  done
  git worktree prune >/dev/null 2>&1 || true
  rm -rf "$WORK_BASE"
}
trap cleanup_parallel EXIT

run_issue_in_worktree() {
  local i="$1"
  local issue="$2"
  local branch="universal-improver/$RUN_ID-$i"
  local wt="$WORK_BASE/wt/$i"
  local log="$WORK_BASE/logs/$i.log"
  local result="$WORK_BASE/results/$i"

  {
    if ! git worktree add -q -b "$branch" "$wt" "$BASE_COMMIT"; then
      echo "Failed to create worktree/branch."
      echo "SKIPPED failed_worktree" > "$result"
      return
    fi

    (
      cd "$wt" || exit 1

      if COMMIT_MSG="$("$FIXER_TOOL" "$issue")"; then
        FIXER_EXIT=0
      else
        FIXER_EXIT=$?
      fi

      if [ "$FIXER_EXIT" -ne 0 ] || [ -z "$COMMIT_MSG" ]; then
        echo "Fixer failed or produced no commit message; skipping."
        echo "SKIPPED fixer_failed" > "$result"
        exit 0
      fi

      if [ -z "$(git status --porcelain)" ]; then
        echo "Fixer made no changes; skipping."
        echo "SKIPPED no_changes" > "$result"
        exit 0
      fi

      if ! "$BUILD_AND_TEST"; then
        echo "Build failed after fix; skipping."
        echo "SKIPPED build_failed" > "$result"
        exit 0
      fi

      git add -A
      git commit -q -m "$COMMIT_MSG"
      echo "COMMITTED $branch" > "$result"
    )
  } > "$log" 2>&1
}

# Launch up to PARALLEL issues concurrently.
for ((i = 0; i < COUNT && i < ${#ISSUES[@]}; i++)); do
  ISSUE="${ISSUES[$i]}"
  echo "=== Issue [$i]: $ISSUE ==="

  while [ "$(jobs -rp | wc -l)" -ge "$PARALLEL" ]; do
    sleep 0.2
  done

  run_issue_in_worktree "$i" "$ISSUE" &
done
wait || true

# Print each issue's log, then merge its branch (if committed), in issue order.
for ((i = 0; i < COUNT && i < ${#ISSUES[@]}; i++)); do
  ATTEMPTED=$((ATTEMPTED + 1))
  echo "=== [$ATTEMPTED/$COUNT] ==="
  if [ -f "$WORK_BASE/logs/$i.log" ]; then
    cat "$WORK_BASE/logs/$i.log"
  fi

  git worktree remove --force "$WORK_BASE/wt/$i" >/dev/null 2>&1 || true

  RESULT_FILE="$WORK_BASE/results/$i"
  read -r STATUS DETAIL < "$RESULT_FILE" 2>/dev/null || true
  if [ "$STATUS" != "COMMITTED" ]; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  BRANCH="$DETAIL"
  if git cherry-pick "$BRANCH" >/dev/null 2>&1; then
    git branch -q -D "$BRANCH" >/dev/null 2>&1 || true
    COMMITTED=$((COMMITTED + 1))
    continue
  fi

  git cherry-pick --abort >/dev/null 2>&1 || true

  echo "Merge conflict for $BRANCH; discarding fix."
  discard_changes
  git branch -q -D "$BRANCH" >/dev/null 2>&1 || true
  SKIPPED=$((SKIPPED + 1))
done

print_summary

exit 0
