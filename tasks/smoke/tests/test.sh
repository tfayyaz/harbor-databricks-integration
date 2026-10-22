#!/bin/sh
set -u

mkdir -p /logs/verifier
printf '0\n' > /logs/verifier/reward.txt

if test -f /app/answer.txt \
  && test "$(cat /app/answer.txt)" = "ok" \
  && test "$(wc -c < /app/answer.txt | tr -d ' ')" = "3"; then
  printf '1\n' > /logs/verifier/reward.txt
  printf 'PASS: answer.txt contains the expected bytes.\n'
else
  printf 'FAIL: answer.txt is missing or has unexpected bytes.\n'
fi
