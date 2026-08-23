#!/usr/bin/env bash
# Test fixer tool for --parallel conflict tests: every item writes to the
# same line of the same file, guaranteeing a merge conflict for whichever
# item's fix is merged second.
set -euo pipefail

item="$1"

echo "fixed-by-$item" > file.txt
git add file.txt
echo ". t fix $item"
