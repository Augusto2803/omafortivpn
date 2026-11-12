#!/usr/bin/env bash
# Run every tests/test_*.sh, each in its own process. Offline, no sudo.
# FORTIVPN_BIN=/path/to/copy tests/run.sh runs the suite against another copy.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

status=0
for t in test_*.sh; do
  bash "$t" || status=1
done
if ((status)); then echo "FAILED" >&2; else echo "all tests passed"; fi
exit "$status"
