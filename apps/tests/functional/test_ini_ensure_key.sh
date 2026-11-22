#!/bin/bash
# FUNCTIONAL TEST (no sudo) -- ini_ensure_key() from apps/lib/common.sh on
# scratch files: adds a missing key, raises a too-small number in "min" mode,
# keeps anything the user set, creates the file or section when absent, and
# a second run changes nothing.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/testlib.sh
source ../../lib/common.sh

echo "test_ini_ensure_key:"
F="$SCRATCH/x.conf"

# --- I.1: no file yet ---
out="$(ini_ensure_key "$F" general scrollback 10000 min)"
assert_eq "creates the file with section and key" "$(cat "$F")" $'[general]\nscrollback=10000'
assert_eq "reports the change" "$out" "changed"

# --- I.2: a smaller number is raised, everything else kept ---
printf '[general]\nfontname=Mono 10\nscrollback=1000\n[other]\nscrollback=5\n' > "$F"
ini_ensure_key "$F" general scrollback 10000 min >/dev/null
assert_eq "raised only in [general]" "$(cat "$F")" \
  $'[general]\nfontname=Mono 10\nscrollback=10000\n[other]\nscrollback=5'

# --- I.3: a larger number, or a non-number, is kept ---
printf '[general]\nscrollback=50000\n' > "$F"
out="$(ini_ensure_key "$F" general scrollback 10000 min)"
assert_eq "a larger value is kept" "$(cat "$F")" $'[general]\nscrollback=50000'
assert_eq "and nothing is reported" "$out" ""
printf '[general]\nmode=dark\n' > "$F"
ini_ensure_key "$F" general mode light >/dev/null
assert_eq "without min, any existing value is kept" "$(cat "$F")" $'[general]\nmode=dark'

# --- I.4: section exists without the key; no section at all ---
printf '[general]\nfontname=Mono 10\n' > "$F"
ini_ensure_key "$F" general scrollback 10000 min >/dev/null
assert_eq "key goes right under the section header" "$(cat "$F")" $'[general]\nscrollback=10000\nfontname=Mono 10'
printf '[other]\na=1\n' > "$F"
ini_ensure_key "$F" general scrollback 10000 min >/dev/null
assert_eq "missing section is appended" "$(cat "$F")" $'[other]\na=1\n[general]\nscrollback=10000'

# --- I.5: idempotent ---
before="$(cat "$F")"
out="$(ini_ensure_key "$F" general scrollback 10000 min)"
assert_eq "second run changes nothing" "$(cat "$F")" "$before"
assert_eq "second run reports nothing" "$out" ""

summarize_and_exit
