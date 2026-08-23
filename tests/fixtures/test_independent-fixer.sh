#!/usr/bin/env bash
# Test fixer tool for --parallel tests: each item writes its own file, so
# concurrent fixes never touch the same location and always merge cleanly.
set -euo pipefail

item="$1"

echo "fixed-$item" > "file-$item.txt"
git add "file-$item.txt"
echo ". t fix $item"
