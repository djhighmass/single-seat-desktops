#!/bin/bash
# backup-user.sh [output-file] -- bundles this account's personal
# desktop preferences into one portable archive, for safekeeping
# somewhere off-device (Google Drive, a laptop, another phone) and
# restoring onto fresh hardware later with restore-user.sh.
#
# Deliberately backs up only source-of-truth files:
# ~/.config/wayfire-customize.conf, ~/.config/timezone, and
# ~/.config/background.png if set. Everything else (the generated
# weather-fetch script, the extra-clock script, wf-shell.ini's managed
# block) is *derived* from the conf file by wayfire-customize.sh --apply
# -- backing those up too would be redundant, and would drift from
# whatever templates the installer ships as it evolves. None of this
# needs root: it only ever touches your own $HOME.
#
#   backup-user.sh                 writes to ~/wayfire-backup.tar.gz
#   backup-user.sh /path/to/out.tar.gz

# No -e: each of the three `[ -f ... ] && cp ...` lines below is a bare
# && with no || fallback, so a normal, expected case -- one of those
# files simply not existing yet -- makes that whole line's exit status
# nonzero. -e would abort right there instead of letting the following
# `[ -z "$(ls -A "$STAGE")" ]` check (which is what actually decides
# whether there was nothing worth backing up) ever run.
set -uo pipefail

OUT="${1:-$HOME/wayfire-backup.tar.gz}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

[ -f "$HOME/.config/wayfire-customize.conf" ] && cp "$HOME/.config/wayfire-customize.conf" "$STAGE/"
[ -f "$HOME/.config/timezone" ] && cp "$HOME/.config/timezone" "$STAGE/"
[ -f "$HOME/.config/background.png" ] && cp "$HOME/.config/background.png" "$STAGE/"

if [ -z "$(ls -A "$STAGE")" ]; then
  echo "nothing to back up yet -- no wayfire-customize.conf, timezone, or background.png found" >&2
  exit 1
fi

tar -C "$STAGE" -czf "$OUT" .
echo "backed up to $OUT:"
tar -tzf "$OUT" | sed 's/^/  /'
