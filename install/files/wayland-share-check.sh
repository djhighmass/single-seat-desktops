#!/bin/bash
# wayland-share-check.sh -- waits for the calling account's own Wayland
# socket to appear, then loosens its permissions so other onboarded
# users can reach it directly. Meant to run from a host account's
# .bashrc on every new interactive shell.
#
# Blocking on this synchronously can add up to ~27s before a prompt
# appears (up to 15s waiting for the runtime dir to exist, up to 10s
# waiting via inotifywait for the socket itself, up to 2.5s of
# permission-fix retries) -- MODE=background runs the whole thing off
# the shell's critical path instead, so the prompt appears immediately.
#
# Options (env vars, all optional):
#   MODE=background|foreground   default: background
#   REPORT=console|log           background only. console prints the
#                                 result on this invocation's own
#                                 stdout (inherited from whatever
#                                 called this script -- normally the
#                                 terminal that started this shell) the
#                                 moment the check finishes -- true to
#                                 "report when done", but if you're
#                                 mid-command at that moment it'll
#                                 visually interrupt what you're typing
#                                 (doesn't corrupt your input, just
#                                 looks jarring). log writes only to
#                                 ~/.cache/wayland-share.log and never
#                                 touches the terminal.
#                                 default: console
#
# SOCK_PATH and the *_ATTEMPTS/*_INTERVAL timing knobs below can be
# overridden by the environment before running this -- that's for
# install/tests/ to point at a scratch socket with fast, deterministic
# timing instead of a real runtime dir and real multi-second waits;
# production never sets them.
#
# No -e: run_check()'s own control flow routinely produces a nonzero
# status on a perfectly normal path -- inotifywait timing out, or its
# piped grep -qm1 not matching yet, both just mean "socket still isn't
# there," which the very next `if [ ! -S "$SOCK_PATH" ]` already turns
# into a clean WARNING and return. -e would abort the whole script on
# that first nonzero status instead of ever reaching that check.
set -uo pipefail

MODE="${MODE:-background}"
REPORT="${REPORT:-console}"
SOCK_PATH="${SOCK_PATH:-/var/run/user/$(id -u)/wayland-0}"
RUNDIR_WAIT_ATTEMPTS="${RUNDIR_WAIT_ATTEMPTS:-150}"
RUNDIR_WAIT_INTERVAL="${RUNDIR_WAIT_INTERVAL:-0.1}"
INOTIFY_TIMEOUT="${INOTIFY_TIMEOUT:-10}"
PERM_FIX_ATTEMPTS="${PERM_FIX_ATTEMPTS:-5}"
PERM_FIX_INTERVAL="${PERM_FIX_INTERVAL:-0.5}"

run_check() {
    local rundir ok attempt dir_mode sock_mode dir_grp sock_grp
    rundir="$(dirname "$SOCK_PATH")"

    for _ in $(seq 1 "$RUNDIR_WAIT_ATTEMPTS"); do
        [ -d "$rundir" ] && break
        sleep "$RUNDIR_WAIT_INTERVAL"
    done

    if [ -d "$rundir" ] && [ ! -S "$SOCK_PATH" ]; then
        inotifywait -q -m -t "$INOTIFY_TIMEOUT" -e create,moved_to "$rundir" --format '%f' 2>/dev/null \
          | grep -qm1 "^$(basename "$SOCK_PATH")\$"
    fi

    if [ ! -S "$SOCK_PATH" ]; then
        echo "[wayland-share] WARNING - $SOCK_PATH never appeared (compositor not running yet?) - other users cannot launch GUI apps"
        return
    fi

    ok=0
    for attempt in $(seq 1 "$PERM_FIX_ATTEMPTS"); do
        sudo chmod g+wrx "$rundir"
        sudo chmod g+wr "$SOCK_PATH"
        dir_mode="$(stat -c '%a' "$rundir" 2>/dev/null)"
        sock_mode="$(stat -c '%a' "$SOCK_PATH" 2>/dev/null)"
        dir_grp="${dir_mode: -2:1}"
        sock_grp="${sock_mode: -2:1}"
        if [ -n "$dir_grp" ] && [ $(( dir_grp & 7 )) -eq 7 ] && [ -n "$sock_grp" ] && [ $(( sock_grp & 6 )) -eq 6 ]; then
            ok=1
            break
        fi
        sleep "$PERM_FIX_INTERVAL"
    done

    if [ "$ok" -eq 1 ]; then
        echo "[wayland-share] OK - other users can reach $SOCK_PATH (dir=$dir_mode sock=$sock_mode, attempt $attempt/$PERM_FIX_ATTEMPTS)"
    else
        echo "[wayland-share] WARNING - permissions not as expected after $attempt attempts (dir=$dir_mode sock=$sock_mode) - other users may NOT be able to launch GUI apps"
    fi
}

if [ "$MODE" = foreground ]; then
    run_check
    exit 0
fi

(
    # disown (below) only stops *this shell* from signaling the job when
    # the shell itself exits -- it does nothing about a SIGHUP the
    # kernel delivers to the whole session. su/sudo su -/login commonly
    # call vhangup(2) on the controlling terminal when starting a new
    # session, which delivers SIGHUP to everything still attached to
    # it, so a login on this same tty right after can otherwise kill
    # this job mid-flight.
    trap '' HUP
    msg="$(run_check)"
    mkdir -p "$HOME/.cache" 2>/dev/null
    echo "$msg" >> "$HOME/.cache/wayland-share.log" 2>/dev/null
    if [ "$REPORT" = console ]; then
        # Deliberately the inherited stdout, not a fresh `> $(tty)`
        # reopen of the controlling terminal by path. Permissions are
        # only checked when a file is *opened* -- an interactive shell's
        # own stdout fd stays writable to it no matter what the tty's
        # current mode/owner is, because that fd was opened once at
        # login and simply inherited since, whereas a brand-new open()
        # of that same path re-checks permissions from scratch and can
        # fail on a tty not chowned to this user.
        printf '\n%s\n' "$msg"
    fi
) &
disown
