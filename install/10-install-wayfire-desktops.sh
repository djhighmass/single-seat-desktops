#!/bin/bash
# 10-install-wayfire-desktops.sh -- turn already-existing Linux accounts
# into switchable, real-DRM wayfire desktops on an Android Linux Terminal
# (Debian/crosvm) box. Run 00-create-users.sh first for any account that
# doesn't exist yet -- this script only wires up accounts that already
# exist, it never creates one.
#
#   sudo ./10-install-wayfire-desktops.sh [--force-new-user-customizations]
#
# Model: one "host" account (default droid) stays on weston permanently as
# the stable base. Every other selected account gets its own wayfire
# compositor, switched to one at a time via a "<user>-wayfire" alias in
# the host's .bash_aliases, which stops weston and starts that user's
# wayfire directly on real hardware. Only one compositor owns the display
# at a time -- this is convenience isolation between trusted accounts on
# one physical device, not a security boundary.
#
# This script only sets up the CORE desktop: enough for a working,
# switchable session with a panel, background, policy agent, and app
# menu. It does not ask about a terminal, weather, clocks, or the
# Synaptic launcher -- those are personal taste, not core plumbing, so
# every onboarded user gets a "Customize Desktop" entry in their own app
# menu (backed by wayfire-customize.sh, which needs no root) to opt into
# whichever of those they personally want, whenever they want. Their
# choices are remembered so they can reapply them later, e.g. after
# --force-new-user-customizations resets their base config.
#
# Safe to re-run: shared steps (packages, seatd, polkit rule, the shared
# tools below, switch-desktop.sh, aliases) and per-user group/linger
# membership are always reapplied -- all idempotent no-ops if already
# done. But a user's core desktop files (wayfire.ini, wf-shell.ini,
# timezone) are only *generated* the first time -- if a user already has
# a ~/.config/wayfire.ini, a re-run leaves it alone rather than
# re-prompting and overwriting it (their wayfire-customize.sh choices
# live in a separate file and are untouched either way).
# Pass --force-new-user-customizations to regenerate a user's core files
# anyway (each is backed up with a timestamp before being overwritten) --
# they'll need to re-run wayfire-customize.sh afterwards to reapply their
# personal extras on top of the fresh base.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=lib/common.sh
source lib/common.sh

FORCE_CUSTOMIZATIONS=n
for arg in "$@"; do
  case "$arg" in
    --force-new-user-customizations) FORCE_CUSTOMIZATIONS=y ;;
    -h|--help)
      grep '^#' "${BASH_SOURCE[0]}" | sed '1d;s/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "unknown argument: $arg (see --help)" >&2; exit 1 ;;
  esac
done

require_root

DEFAULT_TZ="$(cat /etc/timezone 2>/dev/null || echo UTC)"

# ---------------------------------------------------------------- prereqs --

# The full superset for both the core desktop and everything
# wayfire-customize.sh / the shared app-menu tools can possibly do --
# installed unconditionally so those never need root at run time.
#
# polkitd + pkexec, not policykit-1: the latter no longer exists as an
# installable package as of Debian 13 "trixie" (observed on 13.6, still
# true as of the 13.7 point release) -- it's been split into these two.
# Deliberately not building general cross-version package-name fallback
# logic for this (narrow fix for a known case, not broad tolerance) --
# if this specific split ever gets reverted or renamed again, that's the
# next thing to check here.
log "installing shared prerequisites"
pkg_ensure wayfire wf-shell foot seatd grim jq curl yad synaptic lxpolkit polkitd pkexec wlr-randr

command -v curl >/dev/null || die "curl failed to install -- check apt/network and re-run"

systemctl enable --now seatd >/dev/null 2>&1 || true

SEATD_GROUP="video"
if systemctl cat seatd.service &>/dev/null; then
  g="$(systemctl cat seatd.service 2>/dev/null | grep -oP '(?<=-g )\S+' | head -1)"
  [ -n "$g" ] && SEATD_GROUP="$g"
fi
log "seatd runs as -g ${SEATD_GROUP} -- selected users will be added to that group"

log "installing polkit rule: every user authenticates as themselves, not a menu of admins"
install -o root -g root -m 644 files/49-self-auth.rules /etc/polkit-1/rules.d/49-self-auth.rules
systemctl try-restart polkit >/dev/null 2>&1 || true

# xdg-desktop-portal's document-portal backend can't FUSE-mount in this
# environment and fails almost instantly, but the top-level dispatcher
# still burns its full default TimeoutStartSec waiting before reporting
# that failure -- stalling wf-panel/wf-background's own startup by
# 15-25s in the process, since GTK probes the portal on init regardless
# of whether an app actually uses one. This drop-in only shortens how
# long a *failing* start can block things; it doesn't disable portals,
# so anywhere they actually work, nothing changes.
log "shortening the desktop-portal services' start timeout (doesn't disable them)"
for unit in xdg-desktop-portal.service xdg-desktop-portal-gtk.service xdg-document-portal.service; do
  install -d -o root -g root -m 755 "/etc/systemd/user/${unit}.d"
  install -o root -g root -m 644 files/portal-timeout.conf "/etc/systemd/user/${unit}.d/override.conf"
done

# ------------------------------------------------------- shared app tools --

# Installed once, system-wide -- every onboarded user's app menu picks
# these up automatically (wf-panel's menu widget scans the standard XDG
# application directories), and neither tool needs root to run.
log "installing shared app-menu tools (background picker, desktop customizer)"
install -d -o root -g root -m 755 /usr/local/share/applications
install -o root -g root -m 755 files/set-background.sh /usr/local/bin/set-background.sh
install -o root -g root -m 755 files/fix-output-mode.sh /usr/local/bin/fix-output-mode.sh
install -o root -g root -m 755 files/wayland-share-check.sh /usr/local/bin/wayland-share-check.sh
install -o root -g root -m 644 files/set-background.desktop /usr/local/share/applications/set-background.desktop
install -o root -g root -m 755 files/wayfire-customize.sh /usr/local/bin/wayfire-customize.sh
install -o root -g root -m 644 files/wayfire-customize.desktop /usr/local/share/applications/wayfire-customize.desktop

# CLI-only (no app-menu entry) -- an occasional operation, not something
# that needs a click-through icon. Neither needs root: they only ever
# touch the calling user's own $HOME.
install -o root -g root -m 755 files/backup-user.sh /usr/local/bin/backup-user.sh
install -o root -g root -m 755 files/restore-user.sh /usr/local/bin/restore-user.sh

# pkexec strips WAYLAND_DISPLAY/XDG_RUNTIME_DIR from anything it runs as
# root, which breaks native-Wayland GUI apps launched this way (e.g. the
# Synaptic launcher) -- see files/pkexec-wayland for the full story. This
# wrapper + helper + policy action fixes it generically, for any
# root-needing GUI tool launched from a panel/menu entry, not just
# Synaptic.
install -o root -g root -m 755 files/pkexec-wayland /usr/local/bin/pkexec-wayland
install -o root -g root -m 755 files/pkexec-wayland-helper /usr/local/bin/pkexec-wayland-helper
install -o root -g root -m 644 files/local.pkexec-wayland.policy /usr/share/polkit-1/actions/local.pkexec-wayland.policy

install -d -o root -g root -m 755 /usr/local/lib/wayfire-customize
install -o root -g root -m 644 files/owf-update-weather.sh.tmpl /usr/local/lib/wayfire-customize/owf-update-weather.sh.tmpl
install -o root -g root -m 644 files/panel-weather.sh /usr/local/lib/wayfire-customize/panel-weather.sh
install -o root -g root -m 644 files/owf-weather.service /usr/local/lib/wayfire-customize/owf-weather.service
install -o root -g root -m 644 files/owf-weather.timer /usr/local/lib/wayfire-customize/owf-weather.timer

# ------------------------------------------------------------- host user --

read -rp "Host account that stays on weston as the stable base [droid]: " HOST_USER
HOST_USER="${HOST_USER:-droid}"
id "$HOST_USER" &>/dev/null || die "host account '$HOST_USER' doesn't exist -- create it first"

# --------------------------------------------------------- pick accounts --

mapfile -t CANDIDATES < <(awk -F: -v host="$HOST_USER" \
  '$3>=1000 && $3<60000 && $1!=host && $7 !~ /nologin|false/ {print $1}' /etc/passwd)

[ "${#CANDIDATES[@]}" -gt 0 ] || die "no other accounts found -- run 00-create-users.sh first"

echo
echo "Existing accounts available to onboard as wayfire desktops:"
for i in "${!CANDIDATES[@]}"; do printf "  %d) %s\n" "$((i + 1))" "${CANDIDATES[$i]}"; done
read -rp "Which to include (numbers, space-separated, or 'all'): " -a picks

SELECTED=()
if [ "${picks[0]:-}" = "all" ]; then
  SELECTED=("${CANDIDATES[@]}")
else
  for p in "${picks[@]}"; do
    if ! [[ "$p" =~ ^[0-9]+$ ]]; then
      warn "ignoring invalid pick: $p"
      continue
    fi
    idx=$((p - 1))
    if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#CANDIDATES[@]}" ]; then
      SELECTED+=("${CANDIDATES[$idx]}")
    else
      warn "ignoring out-of-range pick: $p"
    fi
  done
fi
[ "${#SELECTED[@]}" -gt 0 ] || die "nothing selected"

log "onboarding: ${SELECTED[*]}"

# --------------------------------------------------------- per-user work --

onboard_user() {
  local u="$1" home uid
  home="$(user_home "$u")"
  uid="$(user_uid "$u")"

  echo
  log "--- configuring $u ($home) ---"

  usermod -aG "video,render,${SEATD_GROUP}" "$u"

  loginctl enable-linger "$u"
  for _ in $(seq 1 10); do [ -d "/run/user/$uid" ] && break; sleep 0.5; done
  [ -d "/run/user/$uid" ] || warn "/run/user/$uid didn't appear yet -- it should on next login/reboot"

  if [ -f "$home/.config/wayfire.ini" ] && [ "$FORCE_CUSTOMIZATIONS" != y ]; then
    log "$u already has a wayfire.ini -- leaving their core desktop in place."
    log "(re-run with --force-new-user-customizations to reset $u's core desktop --"
    log " they'll need to re-run wayfire-customize.sh afterwards for their extras)"
    return
  fi

  read -rp "Timezone for $u [${DEFAULT_TZ}]: " tz
  tz="${tz:-$DEFAULT_TZ}"

  install -d -o "$u" -g "$u" -m 755 "$home/.config" "$home/.local/bin" "$home/.cache"

  backup_file "$home/.config/wayfire.ini"
  install -o "$u" -g "$u" -m 644 files/wayfire.ini.tmpl "$home/.config/wayfire.ini"
  backup_file "$home/.config/timezone"
  printf '%s\n' "$tz" | write_owned_file "$u" "$home/.config/timezone" 644

  install -o "$u" -g "$u" -m 755 files/panel-apt-updates.sh "$home/.local/bin/panel-apt-updates.sh"
  install -o "$u" -g "$u" -m 755 files/panel-apt-updates-tooltip.sh "$home/.local/bin/panel-apt-updates-tooltip.sh"
  install -o "$u" -g "$u" -m 755 files/panel-ram.sh "$home/.local/bin/panel-ram.sh"

  {
    echo "[panel]"
    echo "widgets_left = menu spacing4 launchers window-list"
    echo "widgets_right = volume command-output clock tray"
    echo "commands_output_max_chars = 60"
    echo
    echo "command_output_updates = ${home}/.local/bin/panel-apt-updates.sh"
    echo "command_output_tooltip_updates = ${home}/.local/bin/panel-apt-updates-tooltip.sh"
    echo "command_output_period_updates = 1800"
    echo "command_output_icon_updates = software-update-available-symbolic"
    echo "command_output_icon_size_updates = 0"
    echo "command_output_icon_position_updates = left"
    echo
    echo "command_output_ram = ${home}/.local/bin/panel-ram.sh"
    echo "command_output_period_ram = 10"
    echo "command_output_icon_ram = drive-harddisk-system-symbolic"
    echo "command_output_icon_size_ram = 0"
    echo "command_output_icon_position_ram = left"
  } | { backup_file "$home/.config/wf-shell.ini"; write_owned_file "$u" "$home/.config/wf-shell.ini" 644; }

  log "$u has the core desktop. They can run 'wayfire-customize.sh' (or use"
  log "Customize Desktop in their own app menu) to add a terminal, weather,"
  log "clocks, or the Synaptic launcher, on their own terms."
}

for u in "${SELECTED[@]}"; do
  onboard_user "$u"
done

# ------------------------------------------------------- switch-desktop --

log "deploying /usr/local/bin/switch-desktop.sh"
backup_file /usr/local/bin/switch-desktop.sh
install -o root -g root -m 755 files/switch-desktop.sh /usr/local/bin/switch-desktop.sh

# ------------------------------------------------------------- aliases ---

HOST_HOME="$(user_home "$HOST_USER")"
ALIASES_FILE="${HOST_HOME}/.bash_aliases"
touch "$ALIASES_FILE"
backup_file "$ALIASES_FILE"

for u in "${SELECTED[@]}"; do
  line="alias ${u}-wayfire='/usr/local/bin/switch-desktop.sh ${u} & disown; sudo su - ${u}'"
  # Filter the old line out and append fresh, rather than sed-replacing it
  # in place -- the alias text contains a literal & (from "... & disown"),
  # which sed's replacement syntax treats as "the whole matched line" if
  # unescaped, splicing the old line into the new one instead of
  # overwriting it, corrupting the line further on every re-run for an
  # already-aliased user.
  tmp_aliases="$(mktemp)"
  grep -v "^alias ${u}-wayfire=" "$ALIASES_FILE" > "$tmp_aliases" || true
  mv "$tmp_aliases" "$ALIASES_FILE"
  echo "$line" >> "$ALIASES_FILE"
done
chown "${HOST_USER}:$(id -gn "$HOST_USER")" "$ALIASES_FILE"

# --------------------------------------------------------------- summary --

echo
log "Done. From ${HOST_USER}'s own terminal (not sudo'd into), run:"
for u in "${SELECTED[@]}"; do
  echo "    ${u}-wayfire"
done
echo
log "Each stops weston and starts that user's own wayfire compositor on real DRM."
log "Exiting the 'sudo su - <user>' shell it drops you into does NOT kill the compositor"
log "(that's what linger is for) -- run another *-wayfire alias, or restart weston.socket"
log "+ weston.service yourself as ${HOST_USER}, to switch again."
log "Each onboarded user can run wayfire-customize.sh (or use Customize Desktop"
log "in their own app menu) to add a terminal, weather, clocks, or Synaptic, and"
log "Change Background to pick their own wallpaper -- both are already installed"
log "for everyone."
