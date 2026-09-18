#!/bin/bash
# UNIT TEST -- exercises resolve_foot_args() directly, in isolation, with
# a mocked detect_resolution(). This is deliberately one of the very few
# unit tests in this suite: the rest of the coverage runs real scripts
# through their real CLI entry points (see ../functional/) so that
# internal refactors don't force test rewrites. resolve_foot_args is
# unit-tested anyway because it's a small, pure, stable computation --
# "quarter of the screen" means half-width times half-height -- and
# faking a whole DRM connector just to exercise that arithmetic would be
# needless overhead for a functional test.
#
# No -e: each assert_eq below captures its own comparison into
# pass()/fail() and keeps going, so all four resolve_foot_args cases
# (quarter, full, literal WIDTHxHEIGHT, quarter-with-no-detection) run
# and get reported by summarize_and_exit even if an earlier one fails.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/testlib.sh

# Source the real script without running its main() (guarded by the
# BASH_SOURCE != $0 check at the bottom of the file).
export HOME="$SCRATCH"
# shellcheck source=/dev/null
source ../../files/wayfire-customize.sh

echo "test_resolve_foot_args:"

# Override detect_resolution for this test only -- this is the one place
# a mock is needed, since the real function reads /sys/class/drm.
detect_resolution() { echo "1920x864"; }

assert_eq "quarter halves both dimensions" \
  "$(resolve_foot_args quarter)" "--window-size-pixels=960x432"

assert_eq "full passes no size argument" \
  "$(resolve_foot_args full)" ""

assert_eq "a literal WIDTHxHEIGHT passes through unchanged" \
  "$(resolve_foot_args 800x600)" "--window-size-pixels=800x600"

detect_resolution() { echo ""; }
assert_eq "quarter falls back to a fixed size if resolution can't be detected" \
  "$(resolve_foot_args quarter)" "--window-size-pixels=960x540"

summarize_and_exit
