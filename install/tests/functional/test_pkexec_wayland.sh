#!/bin/bash
# FUNCTIONAL TEST (needs sudo). Proves the actual mechanism
# pkexec-wayland-helper depends on: given a caller's XDG_RUNTIME_DIR and
# WAYLAND_DISPLAY passed as arguments (not inherited environment -- that
# part is what plain pkexec strips), a process running as root can
# actually connect to the caller's live compositor and not just start.
# Uses a real, short-lived `foot` against WHICHEVER compositor actually
# owns the display right now -- droid's weston if nobody's switched away
# from it, or an onboarded user's live wayfire-*.service otherwise. Not
# hardcoded to weston: only one compositor is ever live at a time on this
# box by design, and it's entirely legitimate for that to be someone's
# desktop mid-session rather than the idle host -- this doesn't disrupt
# whichever one it finds, it only launches a short-lived foot into it.
# foot reports a distinct, unambiguous error to stderr when it can't
# reach a compositor at all, which is what actually distinguishes "the
# env got through" from "it didn't", not just whether the process
# happened to exit 0.
#
# Stops short of the interactive polkit password dialog itself, which
# can't be scripted without hardcoding a password.
#
# No -e: `[ -n "$new_pids" ] && sudo -n kill -9 $new_pids` below is a
# bare && with no || fallback, and it's entirely normal for it to have
# found no new foot pid to clean up (e.g. the helper never got that
# far) -- -e would abort on that alone, before either
# assert_not_contains/assert_contains call or summarize_and_exit ever
# runs.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/testlib.sh

echo "test_pkexec_wayland:"

if [ ! -x /usr/local/bin/pkexec-wayland-helper ]; then
  echo "  skip - pkexec-wayland-helper isn't installed on this system yet"
  exit 0
fi

find_live_compositor_user() {
  local host_user host_uid
  host_user="$(loginctl list-sessions --no-legend 2>/dev/null | awk '$4=="seat0"{print $3; exit}')"
  if [ -n "$host_user" ]; then
    host_uid="$(id -u "$host_user")"
    sudo -n -u "$host_user" env "XDG_RUNTIME_DIR=/run/user/$host_uid" \
      systemctl --user is-active --quiet weston.service 2>/dev/null && { echo "$host_user"; return; }
  fi
  local unit target_user
  unit="$(sudo -n systemctl list-units 'wayfire-*.service' --no-legend 2>/dev/null | awk '{print $1; exit}')"
  [ -n "$unit" ] || return 1
  target_user="${unit#wayfire-}"
  target_user="${target_user%.service}"
  echo "$target_user"
}

HOST_USER="$(find_live_compositor_user)"
if [ -z "$HOST_USER" ]; then
  echo "  skip - no live compositor found (neither droid's weston nor any onboarded user's wayfire is active)"
  exit 0
fi
HOST_UID="$(id -u "$HOST_USER")"
SOCKET="$(sudo -n ls "/run/user/$HOST_UID" 2>/dev/null | grep -E '^wayland-[0-9]+$' | head -1)"
if [ -z "$SOCKET" ]; then
  echo "  skip - no live Wayland socket found for $HOST_USER"
  exit 0
fi

NO_COMPOSITOR='failed to connect to wayland'

# --- with the env correctly re-exported, foot should actually connect ---
#
# Cleanup targets only the foot instance this test itself just spawned
# (a before/after pgrep diff), never a blanket `pkill -x foot` -- the
# live compositor this test deliberately targets may belong to a real,
# already-running session with its own real foot window, and killing
# every foot process system-wide would take that down too.
before_pids="$(pgrep -x foot || true)"
out="$(sudo -n timeout 3 /usr/local/bin/pkexec-wayland-helper "/run/user/$HOST_UID" "$SOCKET" foot 2>&1)"
after_pids="$(pgrep -x foot || true)"
new_pids="$(comm -13 <(sort <<<"$before_pids") <(sort <<<"$after_pids"))"
[ -n "$new_pids" ] && sudo -n kill -9 $new_pids 2>/dev/null
assert_not_contains "given the caller's real Wayland env, foot actually connects" \
  "$out" "$NO_COMPOSITOR"

# --- sanity check: the same command with an empty display should fail the same way plain pkexec does ---
out="$(sudo -n timeout 3 /usr/local/bin/pkexec-wayland-helper "/run/user/$HOST_UID" "" foot 2>&1)"
assert_contains "without a display at all, foot fails the same way plain pkexec would" \
  "$out" "$NO_COMPOSITOR"

summarize_and_exit
