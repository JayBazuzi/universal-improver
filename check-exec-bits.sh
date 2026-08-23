#!/usr/bin/env bash
set -euo pipefail

# Fail if any git-tracked file that starts with a shebang line isn't
# marked executable in the git index (catches "chmod +x" getting missed
# before a commit, e.g. tests/fixtures/test_independent-fixer.sh).

status=0

while IFS=$'\t' read -r info file; do
  mode="${info%% *}"
  case "$file" in
    *.bats) continue ;; # run via `bats <file>`, not executed directly
  esac
  first_line="$(git show ":$file" 2>/dev/null | head -n1 || true)"
  case "$first_line" in
    '#!'*)
      if [ "$mode" != "100755" ]; then
        echo "[error] $file has a shebang but is not executable (mode $mode). Run:" >&2
        echo "[error]    > git add --chmod=+x '$file'" >&2
        status=1
      fi
      ;;
  esac
done < <(git ls-files -s)

exit "$status"
