#!/usr/bin/env bash
# Test finder tool that always fails, to exercise the fatal-finder-error path.
set -euo pipefail

echo "finder exploded" >&2
exit 1
