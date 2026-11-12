# Shared helpers for the test files. Sourced, never executed.
#
# Each test file runs in its own bash process (see run.sh), sources the CLI
# without running it, and reports through ok/fail/check. FORTIVPN_BIN points
# the suite at another copy of the script, which is how a deliberately broken
# copy is used to prove a check can fail.

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FORTIVPN_BIN=${FORTIVPN_BIN:-$ROOT/bin/fortivpn}

FAILURES=0
CHECKS=0

# A private HOME so nothing here can read or touch real profiles.
TMP=$(mktemp -d)
export HOME=$TMP/home XDG_CONFIG_HOME=$TMP/home/.config
mkdir -p "$HOME"

_cleanups=()
on_exit() { _cleanups+=("$1"); }
_finish() {
  local c
  for c in "${_cleanups[@]}"; do eval "$c" 2>/dev/null; done
  rm -rf "$TMP"
}
trap _finish EXIT

ok() { CHECKS=$((CHECKS + 1)); }
fail() {
  CHECKS=$((CHECKS + 1)); FAILURES=$((FAILURES + 1))
  printf '  FAIL: %s\n' "$*" >&2
}
# check DESCRIPTION CMD... : passes when the command succeeds.
check() { local d=$1; shift; if "$@"; then ok; else fail "$d"; fi; }
# refute DESCRIPTION CMD... : passes when the command fails.
refute() { local d=$1; shift; if "$@"; then fail "$d"; else ok; fi; }

summary() {
  printf '%s: %d checks, %d failed\n' "$(basename "$0")" "$CHECKS" "$FAILURES"
  ((FAILURES == 0))
}

# shellcheck source=/dev/null
source "$FORTIVPN_BIN"
# The CLI sets -u and pipefail; the harness must keep running after a failed
# command, so turn off anything that would abort on one.
set +e
