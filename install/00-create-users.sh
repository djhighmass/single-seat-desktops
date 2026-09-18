#!/bin/bash
# 00-create-users.sh -- ensure the Linux accounts a wayfire multi-user
# desktop needs already exist, creating any that don't via adduser.
#
#   sudo ./00-create-users.sh alice bob carol
#
# With no args, prompts for a space-separated username list. Existing
# accounts are left completely untouched (including their sudo config) --
# this script only ever adds new users, never modifies established ones.
# Run 10-install-wayfire-desktops.sh afterwards to wire accounts up as
# switchable wayfire desktops.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=lib/common.sh
source lib/common.sh

# install/tests/ sources this file and calls install_nopasswd_sudoers()
# directly against a scratch path, rather than driving the whole
# interactive adduser flow just to reach this one branch -- the
# destination parameter exists for that, production calls never pass it.
install_nopasswd_sudoers() {
  local u="$1" dest="${2:-/etc/sudoers.d/90-$1}" tmp_sudoers
  usermod -aG sudo "$u"
  tmp_sudoers="$(mktemp)"
  echo "$u ALL=(ALL) NOPASSWD:ALL" > "$tmp_sudoers"
  if ! visudo -cf "$tmp_sudoers"; then
    rm -f "$tmp_sudoers"
    die "generated sudoers file for $u failed validation -- not installed"
  fi
  install -o root -g root -m 440 "$tmp_sudoers" "$dest"
  rm -f "$tmp_sudoers"
}

main() {
  require_root

  local USERNAMES=()
  if [ "$#" -gt 0 ]; then
    USERNAMES=("$@")
  else
    read -rp "Usernames to ensure exist (space-separated): " -a USERNAMES
  fi

  [ "${#USERNAMES[@]}" -gt 0 ] || die "no usernames given"

  local u level
  for u in "${USERNAMES[@]}"; do
    if id "$u" &>/dev/null; then
      log "$u already exists -- leaving as-is, not touching sudo/group config"
      continue
    fi

    log "creating $u"
    adduser --gecos "" "$u"

    echo "Sudo level for $u:"
    echo "  1) none"
    echo "  2) password-required (member of the 'sudo' group)"
    echo "  3) passwordless (member of 'sudo' + a NOPASSWD:ALL sudoers.d entry)"
    read -rp "Choice [1]: " level
    level="${level:-1}"
    case "$level" in
      2) usermod -aG sudo "$u" ;;
      3) install_nopasswd_sudoers "$u" ;;
      *) : ;;
    esac
    log "$u created (sudo level: $level)"
  done

  echo
  log "Done. Next: sudo ./10-install-wayfire-desktops.sh"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
