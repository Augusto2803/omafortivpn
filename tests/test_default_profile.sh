#!/usr/bin/env bash
# A profile name reached without being typed — the saved default, the listing —
# becomes root's config and log path, so it must be as constrained as argv.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

mkdir -p "$PROFILE_DIR" "$TMP/outside"
write_profile "$PROFILE_DIR/work.conf" vpn.example.com 443 alice 1
# A parseable profile reachable from PROFILE_DIR through a traversal.
write_profile "$TMP/outside/evil.conf" vpn.example.com 443 alice 1
evil="../../../../outside/evil"
check "traversal target exists" test -f "$(conf_path "$evil")"

echo "$evil" >"$DEFAULT_FILE"
check "traversal in default file falls back to a listed profile" \
  test "$(default_profile)" = work

echo "work" >"$DEFAULT_FILE"
check "valid saved default is honoured" test "$(default_profile)" = work

: >"$PROFILE_DIR/..conf"
: >"$PROFILE_DIR/-x.conf"
check "invalid file names are not listed" test "$(list_profiles)" = work

# cmd_run must refuse before anything else, sudo included.
sudo() { echo SUDO; }
out=$( (cmd_run "$evil") 2>&1 ); rc=$?
check "cmd_run rejects a traversal name" test "$rc" -ne 0
refute "cmd_run reaches no sudo on a traversal name" grep -q SUDO <<<"$out"
check "cmd_run names the reason" grep -q 'invalid profile name' <<<"$out"

summary
