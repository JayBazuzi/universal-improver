#!/usr/bin/env bash
set -euo pipefail

item="$1"

for bad in ${FAIL_ITEMS:-}; do
  if [ "$item" = "$bad" ]; then
    echo "fixer failed on: $item" >&2
    exit 1
  fi
done

echo "fixed-$item" >> file.txt
echo ". t fix $item"
