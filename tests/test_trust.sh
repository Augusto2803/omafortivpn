#!/usr/bin/env bash
# `fortivpn trust` against real TLS servers on 127.0.0.1, with throwaway
# certificates. SSL_CERT_FILE swaps the system trust store for a test CA, so
# chain_verifies and cmd_trust run unmodified.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command -v openssl >/dev/null || { echo "openssl missing; cannot run trust tests" >&2; exit 1; }

PKI=$TMP/pki; mkdir -p "$PKI"
cd "$PKI" || exit 1
SUBJ=/CN=fortivpn-test

# CA
openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.pem -days 2 -subj "$SUBJ-ca" \
  -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign >/dev/null 2>&1

# issue NAME SAN : leaf signed by the CA, valid for SAN (e.g. DNS:localhost,IP:127.0.0.1)
issue() {
  openssl req -newkey rsa:2048 -nodes -keyout "$1.key" -out "$1.csr" -subj "$SUBJ-$1" >/dev/null 2>&1
  printf 'subjectAltName=%s\nextendedKeyUsage=serverAuth\nbasicConstraints=CA:FALSE\n' "$2" >"$1.ext"
  openssl x509 -req -in "$1.csr" -CA ca.pem -CAkey ca.key -CAcreateserial -out "$1.pem" -days 2 \
    -extfile "$1.ext" >/dev/null 2>&1
}
issue both DNS:localhost,IP:127.0.0.1
issue dnsonly DNS:localhost
issue wrongname DNS:gateway.invalid,IP:10.255.255.1
openssl req -x509 -newkey rsa:2048 -nodes -keyout self.key -out self.pem -days 2 -subj "$SUBJ-self" \
  -addext subjectAltName=DNS:localhost,IP:127.0.0.1 >/dev/null 2>&1

export SSL_CERT_FILE=$PKI/ca.pem

der_sha() { openssl x509 -in "$1" -outform DER | sha256sum | awk '{print $1}'; }

# serve NAME : starts a TLS server on a free loopback port, sets PORT.
serve() {
  local try
  for try in 1 2 3 4 5 6 7 8; do
    PORT=$((20000 + RANDOM % 20000))
    openssl s_server -accept "127.0.0.1:$PORT" -cert "$PKI/$1.pem" -key "$PKI/$1.key" -www \
      </dev/null >/dev/null 2>&1 &
    local pid=$!
    on_exit "kill $pid"
    local i
    for i in $(seq 50); do
      kill -0 "$pid" 2>/dev/null || break
      (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null && return 0
      sleep 0.1
    done
    kill "$pid" 2>/dev/null
  done
  echo "could not start a test TLS server" >&2; exit 1
}

# trust NAME HOST PORT [flags] : new profile, run cmd_trust without a terminal.
# Leaves the exit status in RC and the profile path in CONF.
trust() {
  local name=$1 host=$2 port=$3; shift 3
  write_profile "$PROFILE_DIR/$name.conf" "$host" "$port" alice 1
  CONF=$PROFILE_DIR/$name.conf
  (cmd_trust "$name" "$@") </dev/null >/dev/null 2>"$TMP/err"
  RC=$?
}
mkdir -p "$PROFILE_DIR"

# --- chains to the store and matches the name: pinned without a prompt --------
serve both
want=$(der_sha "$PKI/both.pem")
trust v-dns localhost "$PORT"
check "verified (DNS name) is pinned" test $RC -eq 0 -a "$(get_key "$CONF" trusted-cert)" = "$want"
trust v-ip 127.0.0.1 "$PORT"
check "verified (IP SAN) is pinned" test $RC -eq 0 -a "$(get_key "$CONF" trusted-cert)" = "$want"

# --- chains to the store but not for this name: unverified ---------------------
serve dnsonly
want=$(der_sha "$PKI/dnsonly.pem")
trust m-ip 127.0.0.1 "$PORT"
refute "IP not in the certificate: refused without the flag" test $RC -eq 0
check "IP mismatch writes nothing" test -z "$(get_key "$CONF" trusted-cert)"
trust m-ip-flag 127.0.0.1 "$PORT" --accept-unverified
check "IP mismatch pinned only with the flag" test $RC -eq 0 -a "$(get_key "$CONF" trusted-cert)" = "$want"

serve wrongname
want=$(der_sha "$PKI/wrongname.pem")
trust m-name localhost "$PORT"
refute "name not in the certificate: refused without the flag" test $RC -eq 0
check "name mismatch writes nothing" test -z "$(get_key "$CONF" trusted-cert)"
trust m-name-flag localhost "$PORT" --accept-unverified
check "name mismatch pinned only with the flag" test $RC -eq 0 -a "$(get_key "$CONF" trusted-cert)" = "$want"

# --- self-signed ----------------------------------------------------------------
serve self
want=$(der_sha "$PKI/self.pem")
trust s-refuse localhost "$PORT"
refute "self-signed, no terminal, no flag: refused" test $RC -eq 0
check "refusal writes no trusted-cert" test -z "$(get_key "$CONF" trusted-cert)"
check "refusal says how to proceed" grep -q -- '--accept-unverified' "$TMP/err"

# An existing pin survives a refused re-pin.
old=$(printf old | sha256sum | awk '{print $1}')
set_key "$CONF" trusted-cert "$old"
(cmd_trust s-refuse) </dev/null >/dev/null 2>&1
check "refused re-pin keeps the old pin" test "$(get_key "$CONF" trusted-cert)" = "$old"

trust s-accept localhost "$PORT" --accept-unverified
check "self-signed + flag: pins the SHA256 of the DER leaf" test $RC -eq 0 -a "$(get_key "$CONF" trusted-cert)" = "$want"
profile_filter "$CONF" >/dev/null 2>&1
check "pinned profile still passes the filter" test $? -eq 0

# --- nothing listening: no pin, no write ---------------------------------------
dead=$((40000 + RANDOM % 10000))
trust s-dead 127.0.0.1 "$dead"
refute "unreachable gateway fails" test $RC -eq 0
check "unreachable gateway writes nothing" test -z "$(get_key "$CONF" trusted-cert)"

summary
