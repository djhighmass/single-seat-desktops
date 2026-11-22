#!/bin/bash
# 05-restore-homes.sh -- copies home directories back from the Terminal app's
# own backup (mounted at /mnt/backup) after an app upgrade or reset gave you a
# fresh VM.
#
#   sudo ./05-restore-homes.sh --dry-run            show what would be copied
#   sudo ./05-restore-homes.sh                      restore every account that exists
#   sudo ./05-restore-homes.sh --users=alice,bob    only these accounts
#   sudo ./05-restore-homes.sh --exclude=.ssh       leave something out (repeatable;
#                                                   an rsync exclude pattern)
#   sudo ./05-restore-homes.sh --backup=/some/dir   a different backup root
#
# Order on a fresh VM: ./00-create-users.sh (accounts must already exist),
# then this, then ./10-install-wayfire-desktops.sh (which migrates restored
# config forward). Accounts that are in the backup but do not exist yet are
# listed and skipped; nothing is created here.
#
# It is a plain copy of each home, owned by its account. A file that already
# exists and differs (in size or modification time) is kept next to the
# restored one as <name>.pre-restore-<time>. The backup is only ever read.

set -euo pipefail
SELF="$(readlink -f "${BASH_SOURCE[0]}")"  # before the cd: $0 may be relative
cd "$(dirname "$SELF")"
# shellcheck source=lib/common.sh
source lib/common.sh

# restore_one_home <src-home> <dst-home> <dry-run y|n> <owner|""> [rsync args...]
# Returns 1 (after saying why) if rsync could not copy everything.
restore_one_home() {
  local src="$1" dst="$2" dry="$3" owner="$4"; shift 4
  [ -d "$dst" ] || die "destination home does not exist: $dst"
  local args=(-a --backup "--suffix=.pre-restore-$(date +%Y%m%d-%H%M%S)" "$@")
  [ "$dry" = y ] && args+=(-n -i)
  [ -n "$owner" ] && args+=("--chown=$owner")
  rsync "${args[@]}" "$src"/ "$dst"/ || { warn "$src: rsync exited $? -- not everything was copied"; return 1; }
}

main() {
  local backup=/mnt/backup users="" dry=n a excludes=()
  for a in "$@"; do
    case "$a" in
      --backup=*) backup="${a#--backup=}" ;;
      --users=*) users="${a#--users=}" ;;
      --exclude=*) excludes+=("$a") ;;
      --dry-run) dry=y ;;
      -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p}' "$SELF"; exit 0 ;;
      *) die "unknown option: $a (see --help)" ;;
    esac
  done
  [ "$dry" = y ] || require_root
  [ -d "$backup/home" ] || die "no $backup/home -- is the Terminal backup mounted? (looked for $backup/home)"
  if ! command -v rsync >/dev/null; then
    [ "$dry" = y ] && die "rsync is required"
    pkg_ensure rsync
  fi

  local want=() u d missing=() failed=() done_n=0 note="" owner dst
  [ "$dry" = y ] && note=" (dry run)"
  if [ -n "$users" ]; then IFS=, read -r -a want <<<"$users"
  else
    for d in "$backup"/home/*/; do [ -d "$d" ] && want+=("$(basename "$d")"); done
  fi
  [ "${#want[@]}" -gt 0 ] || die "nothing to restore under $backup/home"
  # Check every name before copying anything, so a typo cannot leave a
  # half-finished restore behind.
  for u in "${want[@]}"; do
    [ -d "$backup/home/$u" ] || die "no $backup/home/$u in the backup"
  done

  for u in "${want[@]}"; do
    if ! getent passwd "$u" >/dev/null; then missing+=("$u"); continue; fi
    dst="$(user_home "$u")"
    owner=""
    [ "$dry" = y ] || owner="$u:$(id -gn "$u")"
    log "$u: $backup/home/$u -> $dst$note"
    if restore_one_home "$backup/home/$u" "$dst" "$dry" "$owner" "${excludes[@]}"; then
      done_n=$((done_n + 1))
    else
      failed+=("$u")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    warn "no account yet for: ${missing[*]} -- create them first (sudo ./00-create-users.sh ${missing[*]}), then run this again"
  fi
  log "done: $done_n home(s) processed${note:+ (nothing changed: dry run)}"
  [ "${#failed[@]}" -eq 0 ] || die "incomplete restore for: ${failed[*]} (see the rsync messages above)"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
