#!/bin/bash
# apps/defaults.sh -- our default settings for the named apps, for the user
# running it (not root, so everything written is theirs). Each app's are in
# apps/<app>/defaults.sh. A default is a new settings file: if anything is
# already at that path (a file, a symlink even if its target is missing), it is
# left alone and nothing is merged into it. An app not found on PATH is skipped.
# Exits non-zero if a file couldn't be written.
set -uo pipefail
[ "$EUID" -ne 0 ] || { echo "!! run this as the user it's for, not as root" >&2; exit 1; }
APPS_DIR="$(dirname "${BASH_SOURCE[0]}")"

usage() {
  local f
  printf 'usage: apps/defaults.sh <app>...\n\napps with defaults:\n'
  for f in "$APPS_DIR"/*/defaults.sh; do f="${f%/defaults.sh}"; echo "  ${f##*/}"; done
}

# new_default <command> <path> <content> <what that did> [advice if something is there]
# A failed write also sets $status, so a later call can't hide it.
new_default() {
  command -v "$1" >/dev/null || { echo "skipped: $1 isn't on PATH"; return 0; }
  local f="$2" tmp= rc
  if [ -e "$f" ] || [ -L "$f" ]; then echo "left alone: $f already exists${5:-}"; return 0; fi
  # Written beside it, then hard-linked into place: ln fails rather than replace
  # anything, and a failed write leaves no partial file. (mktemp makes it
  # owner-only; Claude Code's settings can come to hold secrets.)
  mkdir -p "$(dirname "$f")" && tmp="$(mktemp "$(dirname "$f")/.default.XXXXXX")" \
    && printf '%s\n' "$3" > "$tmp" && ln -T "$tmp" "$f"
  rc=$?
  [ -z "$tmp" ] || rm -f "$tmp"
  [ "$rc" -eq 0 ] || { echo "!! $f couldn't be written" >&2; status=1; return 1; }
  echo "$4 ($f)"
}

apps=()
for arg; do
  case "$arg" in
    --list|-h|--help) usage; exit 0 ;;
    -*) echo "!! unknown option: $arg (see --list)" >&2; exit 1 ;;
    *) { [[ "$arg" =~ ^[a-z0-9][a-z0-9-]*$ ]] && [ -f "$APPS_DIR/$arg/install.sh" ]; } \
         || { echo "!! no such app: $arg (see --list)" >&2; exit 1; }
       apps+=("$arg") ;;
  esac
done
[ "${#apps[@]}" -gt 0 ] || { usage >&2; exit 1; }

status=0
for app in "${apps[@]}"; do   # one app's failure doesn't stop the others
  if [ -f "$APPS_DIR/$app/defaults.sh" ]; then
    . "$APPS_DIR/$app/defaults.sh" || status=1
  else
    echo "$app has no defaults"
  fi
done
exit "$status"
