#!/bin/bash
# apps/install.sh -- optional applications on top of the desktop. Run as root;
# see usage(). Each app is apps/<app>/install.sh; shared helpers and guards are
# in apps/lib.sh. For a fresh machine; the guards are under "Scope" in
# apps/README.md. Default settings are separate: see apps/defaults.sh.
set -uo pipefail
APPS_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=lib.sh
source "$APPS_DIR/lib.sh" || { echo "!! could not load apps/lib.sh" >&2; exit 1; }
umask 022   # keeps a strict root umask from apt and package scripts (extrepo sets its own)

usage() {
  local f
  printf 'usage: sudo apps/install.sh <app>...\n\napps:\n'
  for f in "$APPS_DIR"/*/install.sh; do f="${f%/install.sh}"; echo "  ${f##*/}"; done
  cat <<'USAGE'

Apps are installed in the order named; the first failure stops the run.
Third-party repositories are set up through extrepo. Setup needs extrepo's
"non-free" policy: if it is off, the installer uncomments Debian's line for it,
or stops if that line is missing. The policy stays on. An app from such a
repository that is already installed as its package is left alone. --list (this
text) needs no root.
USAGE
}

apps=()
for arg; do
  case "$arg" in
    --list|-h|--help) usage; exit 0 ;;
    -*) die "unknown option: $arg (see --list)" ;;
    *) { [[ "$arg" =~ ^[a-z0-9][a-z0-9-]*$ ]] && [ -f "$APPS_DIR/$arg/install.sh" ]; } || die "no such app: $arg (see --list)"
       apps+=("$arg") ;;
  esac
done
[ "${#apps[@]}" -gt 0 ] || { usage >&2; exit 1; }
require_root

# A fresh VM's package lists are often empty, so refresh them first.
apt-get update -qq || warn "apt-get update failed -- installing from the package lists as they are"
for app in "${apps[@]}"; do . "$APPS_DIR/$app/install.sh" || die "could not install $app"; done
