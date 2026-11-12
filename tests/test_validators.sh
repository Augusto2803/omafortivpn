#!/usr/bin/env bash
# Boundaries of the input validators.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

for p in 1 80 443 10443 65535; do check "port $p valid" valid_port "$p"; done
for p in 0 00 01 0443 65536 99999 100000 -1 +80 4.3 " 80" "80 " 8a "" "443;x"; do
  refute "port '$p' invalid" valid_port "$p"
done

rep() { local s= i; for ((i = 0; i < $1; i++)); do s+=$2; done; printf '%s' "$s"; }

check "otp length 4" valid_otp 1234
check "otp length 128" valid_otp "$(rep 128 a)"
check "otp with hyphen" valid_otp ab-12-cd
check "otp mixed case" valid_otp AbC123
refute "otp length 3" valid_otp 123
refute "otp length 129" valid_otp "$(rep 129 a)"
refute "otp empty" valid_otp ""
for o in "12 34" "12;34" '12$34' $'12\n34' $'1234\n' "12_34" "12.34" $'12\t34' "ab/cd" "1234'" "é123"; do
  refute "otp $(printf %q "$o") invalid" valid_otp "$o"
done

summary
