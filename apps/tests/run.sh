#!/bin/bash
# run.sh -- runs every apps/ test (functional/*.sh); each one that needs sudo
# skips itself cleanly without it.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
pass=0 fail=0
for f in functional/*.sh; do
  if bash "$f"; then pass=$((pass + 1)); else fail=$((fail + 1)); fi
  echo
done
echo "apps tests: $pass file(s) passed, $fail file(s) failed"
[ "$fail" -eq 0 ]
