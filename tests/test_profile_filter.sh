#!/usr/bin/env bash
# What root's openfortivpn is allowed to read from a user-owned profile.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Independent of the script on purpose: widening the allowlist in the CLI
# should need a matching, deliberate change here.
ALLOWED=" host port username password trusted-cert set-dns use-resolvconf set-routes half-internet-routes pppd-use-peerdns pppd-accept-remote insecure-ssl seclevel-1 no-ftm-push realm cipher-list min-tls "
DIGEST=$(printf 'x' | sha256sum | awk '{print $1}')

# pf FILE : sets OUT (stdout) and RC.
pf() { OUT=$(profile_filter "$1" 2>/dev/null); RC=$?; }

# only_allowed : every line of OUT is `allowed-key = value`, nothing else.
only_allowed() {
  local line key
  while IFS= read -r line; do
    [[ $line =~ ^([A-Za-z0-9-]+)\ =\ [^[:cntrl:]]+$ ]] || return 1
    key=${BASH_REMATCH[1]}
    [[ $ALLOWED == *" $key "* ]] || return 1
  done <<<"$OUT"
}

accepts() { # DESC FILE
  pf "$2"
  if ((RC == 0)) && [[ -n $OUT ]] && only_allowed; then ok; else fail "$1 (rc=$RC)"; fi
}

# rejects DESC CONTENT [FORBIDDEN-SUBSTRING]
rejects() {
  local f=$TMP/p.conf
  printf '%b' "$2" >"$f"
  pf "$f"
  if ((RC == 0)); then fail "$1: accepted"; return; fi
  if [[ -n ${3:-} && $OUT == *"$3"* ]]; then fail "$1: offending text reached stdout"; return; fi
  ok
}

# --- profiles the CLI itself writes ------------------------------------------
write_profile "$TMP/plain.conf" vpn.example.com 443 alice 1
accepts "write_profile output" "$TMP/plain.conf"

write_profile "$TMP/dns.conf" vpn.example.com 10443 alice 0 corp.example.com internal.example.net
accepts "write_profile with DNS domains" "$TMP/dns.conf"
refute "dns routing domains are comments, not keys" grep -q dns-routing-domain <<<"$OUT"

set_key "$TMP/plain.conf" trusted-cert "$DIGEST"
accepts "profile after set_key trusted-cert" "$TMP/plain.conf"
check "pinned digest passes through" grep -qx "trusted-cert = $DIGEST" <<<"$OUT"

accepts "shipped example profile" "$ROOT/config/profile.conf.example"

# --- keys that would hand a root process something of the user's choosing ----
H='host = vpn.example.com\n'
for kv in 'pppd-plugin = /tmp/evil.so' 'pppd-log = /etc/cron.d/x' 'pppd-call = evil' \
  'pppd-ipparam = x' 'pppd-ifname = ppp9' 'ca-file = /tmp/ca.pem' 'user-key = /tmp/k' \
  'user-cert = /tmp/c' 'otp = 123456' 'persistent = 5' 'pinentry = /tmp/x' \
  'some-future-option = 1'; do
  rejects "refuses ${kv%% *}" "$H$kv\n" "${kv%% *}"
  rejects "refuses ${kv%% *} when it comes first" "$kv\n$H" "${kv%% *}"
  rejects "refuses ${kv%% *} without spaces" "$H${kv// = /=}\n" "${kv%% *}"
  rejects "refuses indented ${kv%% *}" "$H   $kv\n" "${kv%% *}"
done

# --- control characters and smuggling ----------------------------------------
rejects "carriage return after a value" "host = vpn.example.com\r\n"
rejects "carriage return smuggling a key" "host = a.example.com\rpppd-plugin = /tmp/evil.so\n" pppd-plugin
rejects "control char in username" "$H"'username = al\x01ice\n'
rejects "escape in password" "$H"'password = a\x1bb\n'
rejects "DEL in value" "$H"'username = a\x7fb\n'
rejects "key smuggled in host value" 'host = vpn.example.com pppd-plugin=/x\n' pppd-plugin
rejects "key smuggled in port value" "$H"'port = 443 pppd-plugin=/x\n' pppd-plugin
rejects "key smuggled in flag value" "$H"'set-dns = 1 pppd-plugin = /x\n' pppd-plugin
rejects "line without equals" "${H}pppd-plugin\n"

# A value may legitimately contain `key=`-looking text (a password); it must
# stay inside one output line and never become a second key.
printf 'host = vpn.example.com\npassword = hunter2 pppd-plugin = /x\n' >"$TMP/p.conf"
pf "$TMP/p.conf"
if ((RC == 0)); then
  check "embedded key= stays inside the value" test "$(wc -l <<<"$OUT")" -eq 2
  check "output keys are all allowlisted" only_allowed
else
  ok
fi

# --- value shapes --------------------------------------------------------------
rejects "trusted-cert too short" "${H}trusted-cert = abcd\n"
rejects "trusted-cert uppercase" "${H}trusted-cert = ${DIGEST^^}\n"
rejects "trusted-cert with 65 chars" "${H}trusted-cert = ${DIGEST}0\n"
rejects "trusted-cert not hex" "${H}trusted-cert = ${DIGEST/a/g}z\n"
rejects "port zero" "${H}port = 0\n"
rejects "port too large" "${H}port = 65536\n"
rejects "boolean other than 0/1" "${H}set-routes = 2\n"
rejects "host with a slash" 'host = vpn.example.com/x\n'
rejects "host with a space" 'host = vpn example.com\n'
rejects "no host" 'port = 443\nusername = a\n'
rejects "empty profile" ''
rejects "empty username" "${H}username =\n"

summary
