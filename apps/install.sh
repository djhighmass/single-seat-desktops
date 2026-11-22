#!/bin/bash
# apps/install.sh -- optional applications on top of the desktop, each from
# its supplier's own packages. Run as root. Nothing in install/ needs this:
# every app here is a choice, and each one is also runnable on its own
# (sudo apps/<app>/install.sh).
#
#   sudo apps/install.sh                       ask about each app
#   sudo apps/install.sh --apps=lxterminal,claude-code --defaults --users=alice
#
# Options:
#   --apps=a,b       install these apps without asking which (default: ask)
#   --defaults       also apply each chosen app's default settings
#   --no-defaults    never apply them (default: ask per app)
#   --users=a,b      whose settings get the defaults (default: $SUDO_USER)
#   --list           list the available apps and exit
#
# An app is a directory apps/<app>/ with an install.sh (root: installs the
# app) and optionally a defaults.sh (run as each chosen user: adds our default
# settings where the user hasn't set their own). The first "# DESCRIPTION:"
# line of install.sh is what the menu shows.
set -uo pipefail

APPS_DIR="${APPS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=lib/common.sh
source "$APPS_DIR/lib/common.sh"

describe() { sed -n 's/^# DESCRIPTION: //p' "$1/install.sh" | head -1; }

available_apps() {
  local d
  for d in "$APPS_DIR"/*/; do
    d="${d%/}"
    [ -f "$d/install.sh" ] && basename "$d"
  done
}

ask() {  # ask <question> <default y|n>
  local a hint="[y/N]"
  [ "$2" = y ] && hint="[Y/n]"
  read -rp "$1 $hint " a || a=""
  a="${a:-$2}"
  [[ "$a" =~ ^[Yy] ]]
}

main() {
  local want_apps="" defaults=ask users="${SUDO_USER:-}" arg
  for arg in "$@"; do
    case "$arg" in
      --apps=*) want_apps="${arg#--apps=}" ;;
      --defaults) defaults=y ;;
      --no-defaults) defaults=n ;;
      --users=*) users="${arg#--users=}" ;;
      --list)
        local a
        for a in $(available_apps); do printf '%-16s %s\n' "$a" "$(describe "$APPS_DIR/$a")"; done
        return 0 ;;
      -h|--help) sed -n '2,/^set -uo/p' "$0" | sed '$d; s/^# \{0,1\}//'; return 0 ;;
      *) die "unknown option: $arg (see --help)" ;;
    esac
  done
  require_root

  local all chosen=() a u
  all="$(available_apps)"
  if [ -n "$want_apps" ]; then
    for a in ${want_apps//,/ }; do
      grep -qx "$a" <<< "$all" || die "no such app: $a (see --list)"
      chosen+=("$a")
    done
  else
    for a in $all; do
      ask "Install $a ($(describe "$APPS_DIR/$a"))?" n && chosen+=("$a")
    done
  fi
  [ "${#chosen[@]}" -gt 0 ] || { log "nothing chosen -- no changes"; return 0; }

  for u in ${users//,/ }; do
    id "$u" >/dev/null 2>&1 || die "no such user: $u"
  done

  local failed=()
  for a in "${chosen[@]}"; do
    log "--- $a ---"
    if ! bash "$APPS_DIR/$a/install.sh"; then
      warn "$a: install failed -- skipping its defaults"
      failed+=("$a"); continue
    fi
    [ -f "$APPS_DIR/$a/defaults.sh" ] || continue
    if [ -z "$users" ]; then
      log "$a: no --users given, so no default settings applied"
      continue
    fi
    if [ "$defaults" = n ] || { [ "$defaults" = ask ] && ! ask "Apply our default settings for $a to: $users?" y; }; then
      continue
    fi
    for u in ${users//,/ }; do
      # As the user, so everything written is theirs.
      runuser -u "$u" -- env HOME="$(getent passwd "$u" | cut -d: -f6)" \
        bash "$APPS_DIR/$a/defaults.sh" || warn "$a: default settings failed for $u"
    done
  done
  [ "${#failed[@]}" -eq 0 ] || die "failed: ${failed[*]}"
  log "done"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
