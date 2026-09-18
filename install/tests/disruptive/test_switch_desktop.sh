#!/bin/bash
# DISRUPTIVE TEST -- DO NOT RUN THIS FROM WITHIN A CLAUDE CODE SESSION,
# OR FROM WITHIN ANY WAYFIRE SESSION AT ALL.
#
# This actually calls switch-desktop.sh, which stops whatever compositor
# currently owns the real display and starts another. If the shell
# running this test is itself a descendant of a live wayfire session
# (e.g. a terminal opened inside one), stopping that session's own unit
# kills this test's own process tree mid-run -- exactly what happened
# earlier in this project's history. Run this from the HOST account's own
# terminal (the one that normally owns weston), directly, not sudo'd into
# anything, not from inside any *-wayfire session.
#
#   TESTUSER=wftest ./test_switch_desktop.sh
#
# Prerequisite: TESTUSER must already be onboarded (has a
# ~/.config/wayfire.ini) -- run the core installer against it first.
#
# No -e: assert_failure calls below (e.g. "another unprivileged user
# can't read this user's switch log") deliberately run a command that
# is *expected* to fail and checks that -- and every assert_* keeps
# going and tallies into pass()/fail() so this whole live-hardware
# sequence (switch, double-switch, forced crash, rollback) still runs
# to completion and reports via summarize_and_exit even if one earlier
# check didn't come out as expected.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/testlib.sh

TESTUSER="${TESTUSER:?set TESTUSER to an already-onboarded account, e.g. TESTUSER=wftest $0}"
# Matches the real installer's own default -- logname/$SUDO_USER aren't
# reliable in every session type (e.g. no utmp record over ttyd).
HOST_USER="${WF_TEST_HOST_USER:-droid}"
id "$HOST_USER" &>/dev/null || { echo "no such host account: $HOST_USER (set WF_TEST_HOST_USER)" >&2; exit 1; }
HOST_UID="$(id -u "$HOST_USER")"
host_systemctl() { sudo -n -u "$HOST_USER" env "XDG_RUNTIME_DIR=/run/user/$HOST_UID" systemctl --user "$@"; }

echo "test_switch_desktop (TESTUSER=$TESTUSER, HOST_USER=$HOST_USER):"
echo "  this will visibly take over the real display -- ctrl-C now to abort."
sleep 3

wait_for_unit_active() {
  local unit="$1" tries="$2"
  for _ in $(seq 1 "$tries"); do
    sudo -n systemctl is-active --quiet "$unit" && return 0
    sleep 1
  done
  return 1
}

# --- basic switch: does it come up at all, with a real logind session? ---
# Backgrounded, matching the real <user>-wayfire alias -- switch-desktop.sh
# itself blocks in its own monitor loop until the target compositor exits,
# so calling it in the foreground here would hang this test for as long
# as wayfire stays up (or forever, if it never crashes on its own).
/usr/local/bin/switch-desktop.sh "$TESTUSER" &
wait_for_unit_active "wayfire-${TESTUSER}.service" 20
assert_success "wayfire-$TESTUSER.service is active" -- \
  sudo -n systemctl is-active --quiet "wayfire-${TESTUSER}.service"

wf_pid="$(sudo -n systemctl show "wayfire-${TESTUSER}.service" -p MainPID --value)"
sess="$(python3 -c "
import ctypes
lib = ctypes.CDLL('libsystemd.so.0')
buf = ctypes.c_char_p()
r = lib.sd_pid_get_session($wf_pid, ctypes.byref(buf))
print('ok' if r == 0 else 'fail')
" 2>/dev/null)"
assert_eq "wayfire has a real logind session (the pkexec/lxpolkit fix)" "$sess" "ok"

# --- log file isolation: another onboarded user must not be able to read it ---
assert_failure "another unprivileged user can't read this user's switch log" -- \
  sudo -n -u nobody cat "/tmp/switch-desktop-${TESTUSER}.log"

# --- rapid double-switch: superseded instance must not race the new one ---
# The first switch above is still running (its own monitor loop blocks
# until wayfire exits, which nothing forces yet) -- start a second one on
# top of it, the actual regression case for the generation-token fix (see
# switch-desktop.sh). Deliberately not `wait`-ing on either: both only
# return once their target wayfire exits, which doesn't happen until the
# forced-crash step below -- waiting here would just hang.
/usr/local/bin/switch-desktop.sh "$TESTUSER" &
sleep 5
assert_failure "weston did not get spuriously started by the superseded instance" -- \
  host_systemctl is-active --quiet weston.service
assert_success "the target user's wayfire is still the one actually active" -- \
  sudo -n systemctl is-active --quiet "wayfire-${TESTUSER}.service"

# --- forced crash: rollback to weston must actually happen ---
sudo -n pkill -9 -x wayfire
for _ in $(seq 1 15); do
  host_systemctl is-active --quiet weston.service && break
  sleep 1
done
assert_success "weston restarts after the target's wayfire is killed" -- \
  host_systemctl is-active --quiet weston.service

wait 2>/dev/null
summarize_and_exit
