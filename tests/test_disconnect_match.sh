#!/usr/bin/env bash
# VPN_MATCH decides which processes `fortivpn down` signals as root and which
# count as a live tunnel. Pure regex checks; no process is spawned.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

matches() { [[ $1 =~ $VPN_MATCH ]]; }
# pgrep -f uses extended regex on the same strings; keep both engines honest.
matches_grep() { grep -qE -- "$VPN_MATCH" <<<"$1"; }

yes=(
  "/usr/bin/openfortivpn -c /run/fortivpn/x.conf --pppd-ifname=fortivpn0"
  "/usr/bin/openfortivpn -c /run/fortivpn/x.conf --pppd-ifname fortivpn0"
  "/usr/bin/openfortivpn --pppd-ifname=fortivpn0"
  "/usr/bin/openfortivpn -c /run/fortivpn/x.conf --pppd-ifname=fortivpn0 -v"
  "openfortivpn -c /run/fortivpn/x.conf --pppd-ifname=fortivpn0"
)
no=(
  "sudo openfortivpn -c /run/fortivpn/x.conf --pppd-ifname=fortivpn0"
  "sudo /usr/bin/openfortivpn -c /run/fortivpn/x.conf --pppd-ifname=fortivpn0"
  "/usr/bin/openfortivpn -c /run/fortivpn/x.conf --pppd-ifname=fortivpn1"
  "/usr/bin/openfortivpn -c /run/fortivpn/x.conf --pppd-ifname=ppp0"
  "/usr/bin/openfortivpn -c /run/fortivpn/x.conf --pppd-ifname=fortivpn00"
  "/usr/bin/openfortivpn -c /run/fortivpn/x.conf --pppd-ifname=fortivpn0x"
  "/usr/bin/openfortivpn -c /run/fortivpn/x.conf"
  "vim notes --pppd-ifname=fortivpn0"
  "grep -- --pppd-ifname=fortivpn0 /usr/bin/openfortivpn"
  "echo /usr/bin/openfortivpn --pppd-ifname=fortivpn0"
  "/bin/sh -c /usr/bin/openfortivpn --pppd-ifname=fortivpn0"
  "/usr/bin/notopenfortivpn -c x --pppd-ifname=fortivpn0"
  "/usr/bin/openfortivpn-wrapper -c x --pppd-ifname=fortivpn0"
  "/usr/bin/openfortivpn-x --pppd-ifname=fortivpn0"
)

for s in "${yes[@]}"; do
  check "matches: $s" matches "$s"
  check "matches (grep -E): $s" matches_grep "$s"
done
for s in "${no[@]}"; do
  refute "does not match: $s" matches "$s"
  refute "does not match (grep -E): $s" matches_grep "$s"
done

summary
