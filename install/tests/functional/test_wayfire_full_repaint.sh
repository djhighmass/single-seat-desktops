#!/bin/bash
# FUNCTIONAL TEST -- switch-desktop.sh starts wayfire with the full-repaint flag
# by default and lets WAYFIRE_ARGS override it. The real script stops the
# running compositor, so this only checks the script text and syntax; the real
# launch is covered by disruptive/test_switch_desktop.sh.
#
# No -e: each numbered scenario asserts for itself and must still run when an
# earlier one fails.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/testlib.sh

echo "test_wayfire_full_repaint:"

SD="$(cd ../.. && pwd)/files/switch-desktop.sh"
body="$(cat "$SD")"

assert_success "switch-desktop.sh parses" bash -n "$SD"
assert_contains "WAYFIRE_ARGS defaults to -R (full repaint)" "$body" 'WAYFIRE_ARGS="${WAYFIRE_ARGS--R}"'
assert_contains "the launch line passes WAYFIRE_ARGS to wayfire" "$body" 'wayfire ${WAYFIRE_ARGS}"'
assert_not_contains "no bare 'exec stdbuf -oL -eL wayfire\"' launch left" "$body" 'eL wayfire"'

# An empty WAYFIRE_ARGS must stay empty (plain wayfire), not fall back to -R:
# ${VAR--R} substitutes only when VAR is unset, not when it is set but empty.
assert_eq "unset -> -R" "$(unset WAYFIRE_ARGS; echo "${WAYFIRE_ARGS--R}")" "-R"
assert_eq "set but empty stays empty" "$(WAYFIRE_ARGS= bash -c 'echo "${WAYFIRE_ARGS--R}"')" ""
assert_eq "explicit value is kept" "$(WAYFIRE_ARGS='-R -d' bash -c 'echo "${WAYFIRE_ARGS--R}"')" "-R -d"

summarize_and_exit
