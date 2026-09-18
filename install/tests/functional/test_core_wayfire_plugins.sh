#!/bin/bash
# FUNCTIONAL TEST -- actually launches wayfire (headless backend, no
# sudo, no live session, nothing on screen) against the real shipped
# core template and checks its own log for plugin-load failures, rather
# than grepping the template text for an expected plugin name. This is
# what would have caught a typo in the plugins line, or a plugin that
# doesn't exist on some future wayfire version -- confirmed the signal
# is real by deliberately misspelling a plugin name first and observing
# wayfire's own "Failed to load plugin" error before writing this
# assertion around its absence.
#
# No -e: `timeout 4 ... wayfire` is expected to exit nonzero (timeout
# kills it once its 4s is up -- there's no clean shutdown path here),
# and assert_not_contains afterward is what actually judges the run,
# not the exit code -- -e would abort on the timeout kill itself,
# before that assertion and summarize_and_exit ever get to run.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/testlib.sh

echo "test_core_wayfire_plugins:"

RENDER_NODE=/dev/dri/renderD128
if [ ! -r "$RENDER_NODE" ] || ! command -v wayfire >/dev/null; then
  echo "  skip - no readable $RENDER_NODE or wayfire not installed"
  exit 0
fi

TEMPLATE="$(cd ../.. && pwd)/files/wayfire.ini.tmpl"
# XDG_RUNTIME_DIR must be a scratch directory, not inherited from the
# invoking user's real one: this spawns a genuine second wayfire
# process, and without its own runtime dir it shares the real one's
# Wayland socket directory and session D-Bus, disrupting any already-
# running compositor's own D-Bus-activated clients (e.g. wf-background)
# on the same account.
out="$(timeout 4 env WLR_BACKENDS=headless WLR_RENDERER=pixman \
  WLR_RENDER_DRM_DEVICE="$RENDER_NODE" WAYFIRE_CONFIG_FILE="$TEMPLATE" \
  XDG_RUNTIME_DIR="$SCRATCH" \
  wayfire 2>&1)"

assert_not_contains "the core template's plugin list loads cleanly under a real wayfire" \
  "$out" "Failed to load plugin"

summarize_and_exit
