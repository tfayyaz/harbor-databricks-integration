#!/bin/sh
# The expected count comes from samples.tpch, which is the same in every workspace:
#   SELECT COUNT(*) FROM samples.tpch.orders o JOIN samples.tpch.customer c ON o.o_custkey = c.c_custkey
#   WHERE c.c_mktsegment = 'BUILDING' AND YEAR(o.o_orderdate) = 1995 AND o.o_orderstatus = 'F'
set -u

expected=47911
mkdir -p /logs/verifier
printf '0\n' > /logs/verifier/reward.txt

answer=$(tr -d ' \r\n' < /app/answer.txt 2>/dev/null || true)
if test "$answer" = "$expected"; then
  printf '1\n' > /logs/verifier/reward.txt
  printf 'PASS: answer is %s.\n' "$expected"
else
  printf 'FAIL: expected %s, got "%s".\n' "$expected" "$answer"
fi
