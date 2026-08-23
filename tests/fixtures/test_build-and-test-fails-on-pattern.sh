#!/usr/bin/env bash
# Test build-and-test tool that fails if file.txt matches the extended
# regex given in FAIL_PATTERN; otherwise succeeds.
set -euo pipefail

if grep -qE "${FAIL_PATTERN:?FAIL_PATTERN must be set}" file.txt 2>/dev/null; then
  echo "build-and-test failed" >&2
  exit 1
fi
exit 0
