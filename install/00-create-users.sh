#!/bin/bash
# 00-create-users.sh -- ensure the Linux accounts a wayfire multi-user
# desktop needs already exist, creating any that don't via adduser.
#
#   sudo ./00-create-users.sh alice bob carol
#   sudo ./00-create-users.sh --sudo-level=3 alice
#
# With no usernames, prompts for a space-separated list. --sudo-level=N
# (1 none, 2 password-required, 3 passwordless, as in the prompt) answers
# the sudo question for every account created, leaving only adduser's
# password prompt. Existing
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

  local USERNAMES=() SUDO_LEVEL="" arg
  for arg in "$@"; do
    case "$arg" in
      --sudo-level=*)
        SUDO_LEVEL="${arg#--sudo-level=}"
        [[ "$SUDO_LEVEL" =~ ^[123]$ ]] || die "--sudo-level must be 1, 2 or 3 (got: $SUDO_LEVEL)"
        ;;
      -*) die "unknown option: $arg" ;;
      *) USERNAMES+=("$arg") ;;
    esac
  done

  if [ "${#USERNAMES[@]}" -eq 0 ]; then
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

    if [ -n "$SUDO_LEVEL" ]; then
      level="$SUDO_LEVEL"
    else
      echo "Sudo level for $u:"
      echo "  1) none"
      echo "  2) password-required (member of the 'sudo' group)"
      echo "  3) passwordless (member of 'sudo' + a NOPASSWD:ALL sudoers.d entry)"
      read -rp "Choice [1]: " level
      level="${level:-1}"
    fi
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
