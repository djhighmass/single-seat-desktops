#!/bin/bash
# FUNCTIONAL TEST (needs sudo -- this script's whole job is `sudo chmod`
# on a socket, so there's no meaningful way to exercise it without real
# sudo). Runs the real wayland-share-check.sh via its real env-var
# interface (SOCK_PATH and the timing knobs are the same override
# mechanism install/tests uses elsewhere -- production never sets
# them), against a real AF_UNIX socket file, not a mock of its
# internals. Exercises MODE=foreground blocking synchronously,
# MODE=background freeing the caller immediately, and REPORT=console
# vs REPORT=log actually landing the result in the right place.
#
# No -e: assert_* below (from testlib.sh) already captures each
# command's/comparison's own success or failure into pass()/fail() and
# keeps going, so every remaining assertion still runs and
# summarize_and_exit still prints a full tally even after an earlier
# one fails -- -e would abort the file at the first failing assertion.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/testlib.sh

echo "test_wayland_share_check:"

if [ "$(id -u)" -ne 0 ] && ! sudo -n true 2>/dev/null; then
  echo "  skip - needs passwordless sudo (this script's job is sudo chmod on a socket)"
  exit 0
fi

SCRIPT="$(cd ../.. && pwd)/files/wayland-share-check.sh"
FAST_TIMING=(RUNDIR_WAIT_ATTEMPTS=2 RUNDIR_WAIT_INTERVAL=0.01
             PERM_FIX_ATTEMPTS=1 PERM_FIX_INTERVAL=0.01)

make_fake_socket() {
  # A real AF_UNIX socket file -- `[ -S ... ]` (what the real script
  # checks) is only ever true for an actual bound socket, not a plain
  # file or FIFO standing in for one.
  python3 -c "
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(sys.argv[1])
" "$1"
}

# --- foreground: the socket never appears -----------------------------

out="$(env "${FAST_TIMING[@]}" MODE=foreground SOCK_PATH="$SCRATCH/never/wayland-0" \
  bash "$SCRIPT" 2>&1)"
assert_contains "foreground mode reports synchronously when the socket never appears" \
  "$out" "never appeared"

# --- background + log: result lands in the log, nothing printed -------

export HOME="$SCRATCH/home-log"
mkdir -p "$HOME"
mkdir -p "$SCRATCH/rundir-log"
make_fake_socket "$SCRATCH/rundir-log/wayland-0"

out="$(env "${FAST_TIMING[@]}" MODE=background REPORT=log \
  SOCK_PATH="$SCRATCH/rundir-log/wayland-0" bash "$SCRIPT" 2>&1)"
assert_eq "background mode returns immediately, before the check even runs" "$out" ""

for _ in $(seq 1 50); do [ -s "$HOME/.cache/wayland-share.log" ] && break; sleep 0.1; done
assert_contains "background+log mode's result landed in the log" \
  "$(cat "$HOME/.cache/wayland-share.log" 2>/dev/null)" "[wayland-share] OK"

# --- background + console: result is printed on the caller's stdout --
#
# Deliberately not a fresh `> $(tty)` reopen of the controlling
# terminal by path: permissions are only checked at open() time, not
# on writes through an already-open descriptor, so a tty whose
# ownership/mode doesn't grant this user a fresh open can still be
# written to via the inherited stdout it was opened with at login.

export HOME="$SCRATCH/home-console"
mkdir -p "$HOME"
mkdir -p "$SCRATCH/rundir-console"
make_fake_socket "$SCRATCH/rundir-console/wayland-0"

out="$(env "${FAST_TIMING[@]}" MODE=background REPORT=console \
  SOCK_PATH="$SCRATCH/rundir-console/wayland-0" bash "$SCRIPT" 2>&1)"
assert_contains "background+console mode's result is printed on the caller's own stdout" \
  "$out" "[wayland-share] OK"
assert_contains "the console report also still landed in the log" \
  "$(cat "$HOME/.cache/wayland-share.log" 2>/dev/null)" "[wayland-share] OK"

# --- background job survives a SIGHUP to its session -------------------
#
# e.g. a login on the same tty right after: su/sudo su -/login commonly
# call vhangup(2) on the controlling terminal when starting a new
# session, which delivers SIGHUP to everything still attached to it.
# Plain `disown` doesn't protect against that -- it only stops the
# shell itself from signaling its own jobs when *it* exits, not a
# session-wide SIGHUP from the kernel.

export HOME="$SCRATCH/home-hup"
mkdir -p "$HOME"
mkdir -p "$SCRATCH/rundir-hup"
make_fake_socket "$SCRATCH/rundir-hup/wayland-0"

setsid env "${FAST_TIMING[@]}" MODE=background REPORT=log \
  SOCK_PATH="$SCRATCH/rundir-hup/wayland-0" bash "$SCRIPT" >/dev/null 2>&1 &
script_pid=$!
sleep 0.2
kill -HUP -- "-$script_pid" 2>/dev/null
wait "$script_pid" 2>/dev/null

for _ in $(seq 1 50); do [ -s "$HOME/.cache/wayland-share.log" ] && break; sleep 0.1; done
assert_contains "background job survives a SIGHUP to its session (e.g. a login on the same tty)" \
  "$(cat "$HOME/.cache/wayland-share.log" 2>/dev/null)" "[wayland-share] OK"

summarize_and_exit
