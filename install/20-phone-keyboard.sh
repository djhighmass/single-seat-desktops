#!/bin/bash
# 20-phone-keyboard.sh -- OPTIONAL. Lets this VM pick which on-screen keyboard
# Android uses while the Terminal app is in front, and put yours back when it
# is not. Skip this unless you have the problem it solves.
#
# Why you might want it: on some phones a hardware keyboard loses characters
# (seen on a Pixel 9 Pro XL with Gboard as the active keyboard: every "." and
# the space after it) because Android's keyboard app re-processes the keys
# before the Terminal gets them. Nothing inside the VM can fix that, since the
# keys never arrive. A different keyboard app may not do it. This installs a
# small watcher on the phone that makes the keyboard YOU choose current while
# the Terminal app is focused and gives you your usual one back as soon as it
# is not. Nothing is disabled or uninstalled.
#
#   sudo ./20-phone-keyboard.sh --user=alice              install, then pick a keyboard
#   sudo ./20-phone-keyboard.sh --user=alice --keyboard=<id>   no questions
#   sudo ./20-phone-keyboard.sh --user=alice --list       show keyboards on the phone
#   sudo ./20-phone-keyboard.sh --user=alice --remove     undo (watcher, autostart, config)
#   (--no-autostart installs and configures without the systemd user service)
#
# SECURITY: pairing gives that account (and root) an Android shell on the phone:
# shared storage, screenshots, input injection, app installs. phone-adb uses a
# private adb server socket so other accounts on the VM cannot use it. Revoke
# under Developer options > Wireless debugging > Paired devices.
#
# What still needs a human, once per VM (the installer prints these when it
# gets there; none of it can be scripted):
#   * install the keyboard app you want on the phone (e.g. from Google Play);
#   * Settings > Developer options > Wireless debugging: turn it on, tap
#     "Pair device with pairing code", then run
#         phone-adb pair <wifi-ip:port> <code>        (as the account above)
#     A fresh VM (after a Terminal app upgrade) needs this again.
# Wireless debugging needs Wi-Fi on. Its port changes; phone-adb rescans.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=lib/common.sh
source lib/common.sh

BIN_DIR=${PHONE_KBD_BIN_DIR:-/usr/local/bin}

# render_unit -- the systemd user unit that re-arms the watcher at login/boot,
# retrying while the phone is not reachable yet.
render_unit() {
  cat <<'UNIT'
[Unit]
Description=Choose the Android keyboard while the Terminal app is focused (phone-adb)
# Each attempt may scan for the debug port, so do not retry forever.
StartLimitIntervalSec=900
StartLimitBurst=10

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/phone-adb kbd-follow
Restart=on-failure
RestartSec=30

[Install]
WantedBy=default.target
UNIT
}

# pick_keyboard <choice> <installed-list> -- <choice> is an exact id, or a
# 1-based number into the list. Prints the id, or fails.
pick_keyboard() {
  local choice="$1" list="$2" id
  if grep -qxF -- "$choice" <<<"$list"; then echo "$choice"; return 0; fi
  if [[ "$choice" =~ ^[0-9]+$ ]]; then
    id="$(sed -n "${choice}p" <<<"$list")"
    [ -n "$id" ] && { echo "$id"; return 0; }
  fi
  return 1
}

as_user() { # as_user <user> <cmd...>
  local u="$1"; shift
  runuser -u "$u" -- env HOME="$(user_home "$u")" "$@"
}

main() {
  local user="" kb="" list=n remove=n autostart=y a
  for a in "$@"; do
    case "$a" in
      --user=*) user="${a#--user=}" ;;
      --keyboard=*) kb="${a#--keyboard=}" ;;
      --list) list=y ;;
      --remove) remove=y ;;
      --no-autostart) autostart=n ;;
      -h|--help) sed -n 2,35p "$0"; exit 0 ;;
      *) die "unknown option: $a (see --help)" ;;
    esac
  done
  require_root
  [ -n "$user" ] || user="${SUDO_USER:-}"
  [ -n "$user" ] || die "say which account runs it: --user=NAME"
  getent passwd "$user" >/dev/null || die "no such account: $user"
  local home conf unitdir
  home="$(user_home "$user")"
  conf="$home/.config/phone-adb/keyboard"
  unitdir="$home/.config/systemd/user"

  if [ "$remove" = y ]; then
    as_user "$user" "$BIN_DIR/phone-adb" kbd-release 2>/dev/null || warn "could not reach the phone to restore your keyboard (run phone-adb kbd-release later)"
    runuser -u "$user" -- env XDG_RUNTIME_DIR="/run/user/$(user_uid "$user")" systemctl --user disable --now phone-keyboard.service 2>/dev/null || true
    rm -f "$unitdir/phone-keyboard.service" "$unitdir/default.target.wants/phone-keyboard.service" "$conf"
    log "removed the keyboard watcher setup for $user (phone-adb itself is left installed)"
    return 0
  fi

  pkg_ensure adb python3 iproute2
  install -m 0755 files/phone-adb "$BIN_DIR/phone-adb"
  log "installed $BIN_DIR/phone-adb"

  # Stop any default adb server this account left on localhost:5037: every account
  # on the VM can reach it. phone-adb uses its own private socket instead.
  as_user "$user" adb kill-server >/dev/null 2>&1 || true

  if ! as_user "$user" "$BIN_DIR/phone-adb" connect >/dev/null 2>&1; then
    cat <<EOF

The VM is not paired with the phone yet. One-time, by hand:
  1. On the phone: Settings > Developer options > Wireless debugging: on
     (Wi-Fi must be on), then "Pair device with pairing code".
  2. In this VM, as $user:   phone-adb pair <wifi-ip:port> <code>
  3. Run this script again.
EOF
    return 0
  fi

  local installed; installed="$(as_user "$user" "$BIN_DIR/phone-adb" keyboards)"
  [ "$list" = y ] && { echo "$installed" | nl -w2 -s'  '; return 0; }
  [ "$(wc -l <<<"$installed")" -gt 1 ] || warn "only one keyboard is installed on the phone; install the one you want first (e.g. from Google Play), then run this again"

  if [ -z "$kb" ]; then
    echo "Keyboards on the phone:"; echo "$installed" | nl -w2 -s'  '
    read -r -p "Which should be used while the Terminal is focused? (number or id) " kb
  fi
  local chosen
  chosen="$(pick_keyboard "$kb" "$installed")" || die "not one of the installed keyboards: $kb"
  kb="$chosen"

  ensure_user_dirs "$user" "$home" .config/phone-adb
  echo "$kb" | write_owned_file "$user" "$conf" 644
  log "terminal keyboard for $user: $kb"

  as_user "$user" "$BIN_DIR/phone-adb" kbd-follow || warn "could not start the watcher now; it will retry via the service"

  if [ "$autostart" = y ]; then
    ensure_user_dirs "$user" "$home" .config/systemd/user/default.target.wants
    render_unit | write_owned_file "$user" "$unitdir/phone-keyboard.service" 644
    # Enable by writing the wants/ symlink ourselves: `systemctl --user enable`
    # needs the user's manager (and /run/user/<uid>) to exist, which races a
    # freshly enabled linger.
    ln -sfn ../phone-keyboard.service "$unitdir/default.target.wants/phone-keyboard.service"
    chown -h "$user:$(id -gn "$user")" "$unitdir/default.target.wants/phone-keyboard.service"
    loginctl enable-linger "$user"
    log "autostart enabled (re-arms the watcher when $user's user manager starts)"
  fi
  log "done. Undo any time: sudo ./20-phone-keyboard.sh --user=$user --remove"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
