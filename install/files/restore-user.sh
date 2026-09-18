#!/bin/bash
# restore-user.sh <archive> -- restores a backup-user.sh archive onto
# this account and re-applies it. Works for rebuilding your own
# environment after a reset, or moving to entirely new hardware --
# nothing in the archive references a username or home path, so it
# doesn't matter if the account name is different from wherever the
# backup came from.
#
# Run the core installer for this account first (it needs a base
# ~/.config/wayfire.ini already in place to apply preferences on top of).
# Doesn't need root: it only touches your own $HOME and re-invokes
# wayfire-customize.sh/set-background.sh, neither of which need it either.

# No -e: `[ -f "$STAGE/timezone" ] && cp ...` below is a bare && with
# no || fallback -- an archive that simply never had a timezone file
# (a normal, expected shape, e.g. from an older backup) makes that
# line's own exit status nonzero. -e would abort the whole restore
# right there instead of moving on to the conf-file and background
# restores that follow, which are each already guarded by a proper if.
set -uo pipefail

ARCHIVE="${1:?usage: restore-user.sh <archive>}"
[ -f "$ARCHIVE" ] || { echo "no such file: $ARCHIVE" >&2; exit 1; }
[ -f "$HOME/.config/wayfire.ini" ] || { echo "no $HOME/.config/wayfire.ini -- run the core installer for this account first" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
tar -C "$STAGE" -xzf "$ARCHIVE"

mkdir -p "$HOME/.config"
[ -f "$STAGE/timezone" ] && cp "$STAGE/timezone" "$HOME/.config/timezone"

if [ -f "$STAGE/wayfire-customize.conf" ]; then
  cp "$STAGE/wayfire-customize.conf" "$HOME/.config/wayfire-customize.conf"
  /usr/local/bin/wayfire-customize.sh --apply
else
  echo "no saved customization in this archive -- leaving current settings as they are"
fi

if [ -f "$STAGE/background.png" ]; then
  /usr/local/bin/set-background.sh --file "$STAGE/background.png"
fi

echo "restored from $ARCHIVE"
