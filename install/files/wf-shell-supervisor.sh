#!/bin/bash
# wf-shell-supervisor.sh -- keeps wf-panel and wf-background running for
# the current wayfire session. Started from wayfire.ini [autostart]
# (shell = ...) with autostart_wf_shell = false.
#
# The display here is virtio-gpu output mirroring an Android window; every
# resize/rotate/dock reconnects it, which kills both clients, and wf-panel
# can also abort in GTK/cairo. wayfire's autostart never restarts them.
#
# It also publishes the session's display variables to the user's
# systemd/D-Bus activation environment first. wayfire runs under
# systemd-run, so that environment otherwise lacks them, and
# xdg-desktop-portal-gtk fails -- making GTK apps wait out a 25s D-Bus
# timeout at startup.
#
# CAPS settings below are overridable for install/tests/ only.
#
# No -e: a supervised command exiting nonzero is the expected event.
set -uo pipefail

LOG="${LOG:-$HOME/.cache/wf-shell-supervisor.log}"
PANEL_CMD="${PANEL_CMD:-wf-panel}"
BACKGROUND_CMD="${BACKGROUND_CMD:-wf-background}"
FIX_OUTPUT_CMD="${FIX_OUTPUT_CMD:-/usr/local/bin/fix-output-mode.sh}"
ENV_PUBLISH_CMD="${ENV_PUBLISH_CMD:-dbus-update-activation-environment --systemd}"
PORTAL_RESET_CMD="${PORTAL_RESET_CMD:-systemctl --user reset-failed xdg-desktop-portal.service xdg-desktop-portal-gtk.service}"
RESTART_DELAY="${RESTART_DELAY:-1}"
# Exiting within FAST_EXIT_SECS of starting, MAX_FAST_EXITS times in a
# row, is a crash loop rather than a reconnect: stop restarting.
FAST_EXIT_SECS="${FAST_EXIT_SECS:-10}"
MAX_FAST_EXITS="${MAX_FAST_EXITS:-5}"

mkdir -p "$(dirname "$LOG")"
# Truncated per session; also captures the clients' own output.
exec >"$LOG" 2>&1 </dev/null

log() { echo "$(date '+%F %T') [wf-shell-supervisor] $*"; }

# The compositor's pid+name distinguish "a client died" (restart) from
# "the session ended" (stop). wayfire's autostart detaches its children
# (re-parented to init), so it is looked up in this session's cgroup
# (cgroup v2 unified hierarchy), not among this script's ancestors.
COMPOSITOR_NAME="${COMPOSITOR_NAME:-wayfire}"
find_compositor() {
  local cg pid
  cg="$(sed -n 's/^0:://p' /proc/self/cgroup 2>/dev/null)"
  if [ -n "$cg" ]; then
    while read -r pid; do
      [ "$(cat "/proc/$pid/comm" 2>/dev/null)" = "$COMPOSITOR_NAME" ] && { echo "$pid"; return; }
    done < "/sys/fs/cgroup$cg/cgroup.procs"
  fi
  echo "$PPID"
}
COMPOSITOR_PID="${COMPOSITOR_PID:-$(find_compositor)}"
COMPOSITOR_COMM="$(cat "/proc/$COMPOSITOR_PID/comm" 2>/dev/null)"
compositor_alive() {
  [ -n "$COMPOSITOR_COMM" ] && [ "$(cat "/proc/$COMPOSITOR_PID/comm" 2>/dev/null)" = "$COMPOSITOR_COMM" ]
}

publish_env() {
  local v names=()
  for v in WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE; do
    [ -n "${!v:-}" ] && names+=("$v")
  done
  [ "${#names[@]}" -gt 0 ] || { log "no display variables set -- nothing to publish"; return; }
  if $ENV_PUBLISH_CMD "${names[@]}"; then
    log "published ${names[*]} to the user's activation environment"
  else
    log "WARNING: couldn't publish ${names[*]} -- portal-backed GTK apps may stall ~25s at startup"
  fi
  # A portal activated before this point has already failed; let it retry.
  $PORTAL_RESET_CMD >/dev/null 2>&1 || true
}

# supervise <name> <command> [command to run after each restart]
supervise() {
  local name="$1" cmd="$2" after="${3:-}" fast=0 started rc child=""
  trap '[ -n "$child" ] && kill "$child" 2>/dev/null; exit 0' TERM INT
  while compositor_alive; do
    started=$SECONDS
    log "starting $name"
    $cmd &
    child=$!
    wait "$child"
    rc=$?
    child=""
    compositor_alive || { log "$name exited (status $rc) with the compositor gone -- stopping"; break; }
    if [ $((SECONDS - started)) -lt "$FAST_EXIT_SECS" ]; then fast=$((fast + 1)); else fast=0; fi
    log "$name exited (status $rc) -- restarting"
    if [ "$fast" -ge "$MAX_FAST_EXITS" ]; then
      log "$name exited $fast times within ${FAST_EXIT_SECS}s of starting -- giving up on it"
      return 1
    fi
    # A reconnect also resets the output to Android's "preferred" mode.
    [ -n "$after" ] && $after
    sleep "$RESTART_DELAY"
  done
}

log "session compositor: pid $COMPOSITOR_PID (${COMPOSITOR_COMM:-unknown})"
publish_env

supervise wf-background "$BACKGROUND_CMD" &
bg_pid=$!
supervise wf-panel "$PANEL_CMD" "$FIX_OUTPUT_CMD" &
panel_pid=$!
trap 'kill "$bg_pid" "$panel_pid" 2>/dev/null' EXIT TERM INT
wait
log "stopped"
