#!/bin/bash
# Usage: switch-desktop.sh <target-user>
#
# Run this as the host account (the one that owns the real display by
# default, e.g. "droid"), NOT via sudo -- sudo-ing the whole script strips
# the host's own systemd --user D-Bus session, which the weston.socket/
# weston.service stop/start below needs.
#
# Stops the host's weston.socket + weston.service (releasing DRM master
# and disarming socket-activation respawn), stops any *other* onboarded
# user's wayfire that might still be running (seatd only lets one client
# hold the seat at a time), and starts wayfire directly on real hardware
# as <target-user>, using that user's own ~/.config/wayfire.ini.
#
# wayfire is launched via `systemd-run -p PAMName=login`, not plain
# `sudo -u <user>`. A plain sudo'd process has no logind session at all
# (sd_pid_get_session() on it returns ENODATA), which breaks polkit:
# pkexec can't find the user's own lxpolkit registered as an agent for a
# session that doesn't exist, so it falls back to a textual auth prompt --
# and that prompt then tries to open the calling shell's leftover
# controlling terminal (whatever pty originally ran the `<user>-wayfire`
# alias), which it isn't the foreground process group of, so the kernel
# just parks it forever in stopped ("T") state. That's the "invalid
# session for pid" / apt-asks-which-user-to-authenticate-as failure mode.
# `-p PAMName=login` gives the whole session a real (if seatless)
# logind session id, which is enough for pkexec to route through the
# session's own lxpolkit GUI agent instead of ever reaching that fallback.
#
# WLR_BACKENDS is forced explicitly so wlroots can't be misled into an
# X11/nested-Wayland backend by a stale DISPLAY/WAYLAND_DISPLAY export in
# the target user's own shell startup files.
#
# No confirm-window timeout: once wayfire is up it stays up indefinitely.
# The only automatic rollback is if wayfire itself exits/crashes, so
# you're never stranded with zero compositor running.
#
# Detaches from its own stdio so it keeps running even if the invoking
# shell's controlling terminal goes away mid-run.

# No -e: the whole point of the monitor loop and rollback() at the
# bottom is to be the safety net that always gets this box back to a
# running weston if the switch to wayfire doesn't pan out. An
# unrelated step failing partway through (a sudo/systemctl call hitting
# some edge case) must still fall through to that loop and rollback
# instead of a global trap aborting the script early and leaving
# neither weston nor wayfire actually running.
set -uo pipefail

TARGET_USER="${1:?usage: switch-desktop.sh <target-user>}"
LOG="/tmp/switch-desktop-${TARGET_USER}.log"
WAYFIRE_LOG="/tmp/${TARGET_USER}-wayfire.log"
UNIT="wayfire-${TARGET_USER}.service"
GENERATION_FILE="/tmp/switch-desktop.current"

# These land in /tmp named after the target user, readable only by whoever
# creates them (the host account) thanks to the umask below -- other
# onboarded users share this box and shouldn't be able to read each
# other's switch logs. That cuts both ways: /tmp's sticky bit means even
# root aside, only the ORIGINAL owner can overwrite a leftover file here,
# so a stale log from a previous run under a different invoking user
# (e.g. this script accidentally run as the wrong account -- its own
# documented precondition) would otherwise silently block this run from
# ever writing its own log at all. sudo -n rm clears that unconditionally
# before it matters, rather than failing this run over a leftover file.
umask 077
sudo -n rm -f "$LOG" "$GENERATION_FILE"
exec >"$LOG" 2>&1 </dev/null
echo "=== switch-desktop start $(date) : target=${TARGET_USER} ==="

# Claim ourselves as the current switch attempt. If someone runs another
# *-wayfire alias before this one's monitor loop below even notices, that
# newer invocation's own "stop any other onboarded user's wayfire" step
# stops OUR unit too -- which would otherwise look indistinguishable from
# our own target crashing, and trigger a rollback to weston that races
# with the newer switch's own launch. Checking this file before rolling
# back lets a superseded instance recognize that and just step aside.
echo "$$" > "$GENERATION_FILE"

TARGET_UID="$(id -u "$TARGET_USER")" || { echo "no such user: $TARGET_USER"; exit 1; }
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

echo "stopping any other onboarded user's wayfire (seatd allows only one active seat client)"
sudo -n systemctl stop --quiet 'wayfire-*.service' 2>/dev/null
# Belt-and-suspenders: also reap any raw `wayfire` process not managed by
# one of our systemd units (e.g. one left over from before this script
# managed launches this way, or one that somehow escaped its unit). A
# stray one left holding the seat makes every subsequent switch -- and
# the weston rollback -- fail with "Device or resource busy", so it's
# worth being thorough here rather than assuming the unit-based stop
# above always covers it.
sudo -n pkill -9 -x wayfire 2>/dev/null
sleep 1

echo "clearing any stale wayland-* socket/lock files for ${TARGET_USER} so it always binds wayland-0"
sudo -n -u "$TARGET_USER" bash -c "rm -f /run/user/${TARGET_UID}/wayland-*"

echo "stopping weston.socket and weston.service (this session's own compositor)"
systemctl --user stop weston.socket weston.service
sleep 1

# `systemctl --user` always targets the CALLING user's own instance --
# if this script isn't actually running as the host account (its own
# documented precondition), this silently no-ops against some unrelated
# session instead of erroring, and weston never lets go of the seat.
# Every following step still runs, but wayfire is doomed before it
# starts: seatd correctly refuses the new client since weston still
# holds it, libseat falls back to its embedded seat backend (which needs
# root and can't get it as a regular user), and it hangs for a fixed 10s
# before segfaulting -- a confusing failure a couple of minutes away from
# its actual cause. Checking explicitly here turns that into an
# immediate, actionable error instead.
if systemctl --user is-active --quiet weston.service; then
  echo "FATAL: weston.service is still active after asking it to stop."
  echo "This almost always means this script isn't running as the host"
  echo "account directly (its own documented precondition) -- check who"
  echo "actually invoked it, not just who owns this terminal."
  exit 1
fi

echo "waiting for DRM connector state to stabilize (external-monitor/USB-C-hub settling)"
connector_snapshot() {
  cat /sys/class/drm/card0-*/status 2>/dev/null
}
prev="$(connector_snapshot)"
stable_secs=0
waited=0
while [ "$stable_secs" -lt 2 ] && [ "$waited" -lt 15 ]; do
  sleep 1
  waited=$((waited + 1))
  cur="$(connector_snapshot)"
  if [ "$cur" = "$prev" ]; then
    stable_secs=$((stable_secs + 1))
  else
    stable_secs=0
    prev="$cur"
  fi
done
echo "connector state stable=${stable_secs}s waited=${waited}s: $(connector_snapshot | tr '\n' ' ')"

TARGET_TZ="$(sudo -n -u "$TARGET_USER" cat "${TARGET_HOME}/.config/timezone" 2>/dev/null || echo UTC)"
echo "using timezone ${TARGET_TZ} for ${TARGET_USER} (from ${TARGET_HOME}/.config/timezone, defaults to UTC)"

echo "starting wayfire as ${TARGET_USER} (uid ${TARGET_UID}) directly on DRM, as systemd unit ${UNIT}"
sudo -n systemctl reset-failed "$UNIT" 2>/dev/null
# wayfire's own stdout/stderr are fully-buffered when not attached to a
# tty, so if it crashes, whatever it hadn't flushed yet is lost -- `stdbuf
# -oL -eL` forces line buffering so a crash's actual log lines make it out
# instead of vanishing. StandardOutput=file: (with StandardError=inherit,
# so both streams share the same fd/offset instead of two independent
# writers racing on the same file) puts wayfire's *own* output in
# $WAYFIRE_LOG -- redirecting systemd-run's own stdout, as before, only
# ever captured its "Running as unit: ..." message, not wayfire's.
sudo -n systemd-run \
  --uid="$TARGET_UID" --gid="$TARGET_UID" \
  -p PAMName=login \
  --unit="wayfire-${TARGET_USER}" \
  --collect \
  --property=StandardOutput=file:"${WAYFIRE_LOG}" \
  --property=StandardError=inherit \
  --setenv=XDG_RUNTIME_DIR="/run/user/${TARGET_UID}" \
  --setenv=HOME="$TARGET_HOME" \
  --setenv=WAYFIRE_CONFIG_FILE="${TARGET_HOME}/.config/wayfire.ini" \
  --setenv=WLR_BACKENDS=drm,libinput \
  --setenv=WLR_RENDERER=pixman \
  --setenv=WLR_NO_HARDWARE_CURSORS=1 \
  --setenv=WLR_DRM_NO_ATOMIC=1 \
  --setenv=TZ="$TARGET_TZ" \
  -- stdbuf -oL -eL bash -lc "cd '${TARGET_HOME}'; unset DISPLAY WAYLAND_DISPLAY; exec stdbuf -oL -eL wayfire"
echo "launched as ${UNIT} -- wayfire's own log is ${WAYFIRE_LOG} (or: journalctl -u ${UNIT})"

rollback() {
  echo "rolling back to weston: $1"
  sudo -n systemctl stop "$UNIT" 2>/dev/null
  sleep 1
  systemctl --user start weston.socket weston.service
  echo "=== rollback complete $(date) ==="
}

i=0
while sudo -n systemctl is-active --quiet "$UNIT" 2>/dev/null; do
  sleep 1
  i=$((i + 1))
done

if [ "$(cat "$GENERATION_FILE" 2>/dev/null)" != "$$" ]; then
  echo "a newer switch-desktop.sh invocation has taken over -- not rolling back"
  exit 0
fi

rollback "wayfire process exited on its own after ${i}s"
exit 1
