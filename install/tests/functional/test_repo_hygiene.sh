#!/bin/bash
# FUNCTIONAL TEST -- checks for personal identifiers before this repo (or
# a fork of it) goes public, and that every script still parses. Sweeps
# the actual publish surface -- git-tracked files, plus untracked files
# that aren't gitignored (since those could still get committed later) --
# from the repo root down, not just install/. Anything already
# gitignored (like .claude/) is deliberately excluded: it can't leak to
# a public clone regardless of what it contains.
#
# The identifier list itself is deliberately NOT in this file: whatever
# usernames/emails need scrubbing are personal to whoever is about to
# publish, and hardcoding them here would defeat the entire point the
# moment this file itself got committed. Put your own pattern in
# install/tests/.personal_pattern (gitignored, one grep -E pattern, e.g.
# 'alice|bob|alice@example\.com') and this test picks it up; with no
# such file, that half of the check is skipped rather than silently
# checking nothing.
#
# LICENSE is exempt from that scan: a copyright line naming the author
# is the intended, deliberate use of that identifier in a public repo,
# not the accidental leakage this check exists to catch.
#
# No -e: the grep -lniE/grep -niE calls below are expected to find
# nothing and exit nonzero on a clean repo -- that's the pass case,
# checked explicitly by the surrounding if -- and each bash -n check
# in the loop after it is meant to keep going through every file and
# tally fail_count, not abort the scan on the first syntax error found.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/testlib.sh

echo "test_repo_hygiene:"

REPO_ROOT="$(cd ../../.. && pwd)"
PATTERN_FILE="$(cd .. && pwd)/.personal_pattern"

cd "$REPO_ROOT"
mapfile -d '' PUBLISH_SURFACE < <(git ls-files --cached --others --exclude-standard -z)

if [ -f "$PATTERN_FILE" ]; then
  pattern="$(cat "$PATTERN_FILE")"
  SCAN_TARGETS=()
  for f in "${PUBLISH_SURFACE[@]}"; do
    [ "$f" = "LICENSE" ] || SCAN_TARGETS+=("$f")
  done
  if [ "${#SCAN_TARGETS[@]}" -gt 0 ] && printf '%s\0' "${SCAN_TARGETS[@]}" | xargs -0 grep -lniE "$pattern" >/dev/null 2>&1; then
    fail "no personal identifiers in any file this repo would actually publish"
    printf '%s\0' "${SCAN_TARGETS[@]}" | xargs -0 grep -niE "$pattern" >&2
  else
    pass "no personal identifiers in any file this repo would actually publish"
  fi
else
  echo "  skip - no install/tests/.personal_pattern present, nothing to check against"
fi

fail_count=0
for f in "${PUBLISH_SURFACE[@]}"; do
  case "$f" in
    *.sh)
      if ! bash -n "$f" 2>/dev/null; then
        fail "syntax check: $f"
        fail_count=$((fail_count + 1))
      fi
      ;;
  esac
done
[ "$fail_count" -eq 0 ] && pass "every published .sh file passes bash -n"

summarize_and_exit
