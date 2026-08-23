#!/usr/bin/env bash
set -euo pipefail

for item in ${TEST_FINDER_ITEMS:?TEST_FINDER_ITEMS must be set}; do
  echo "$item"
done
