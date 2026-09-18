#!/bin/bash
# set-background.sh [--file <path>] -- change the desktop wallpaper.
#
# With no arguments, opens a GUI file-browse dialog (yad). With --file,
# applies the given image directly, skipping the dialog -- used by
# restore-user.sh to apply a backed-up wallpaper without a human clicking
# through a picker, and is also what makes this script's apply logic
# testable at all without driving a GUI dialog.
#
# Either way: copies the image to ~/.config/background.png, makes sure
# ~/.config/wf-shell.ini has a [background] section pointing at it, and
# restarts wf-background so the change shows up immediately. wf-background
# only reads the image at startup -- it doesn't watch the file for
# changes -- so the restart is required, not optional.

# No -e: `picked="$(yad ...)"` below exits nonzero when the user just
# clicks Cancel -- a normal, expected outcome, not an error -- and the
# very next line (`[ -z "$picked" ] && exit 0`) is what's meant to
# handle that cleanly. -e would abort on the assignment itself first,
# before that intended check ever runs.
set -uo pipefail

INI="$HOME/.config/wf-shell.ini"
BG="$HOME/.config/background.png"

if [ "${1:-}" = "--file" ]; then
  picked="${2:?usage: set-background.sh --file <path>}"
else
  picked="$(yad --file-selection --title="Choose a background image" \
    --file-filter="Images | *.png *.jpg *.jpeg *.bmp *.webp" \
    --width=800 --height=600 2>/dev/null)"
fi
[ -z "$picked" ] && exit 0
[ -r "$picked" ] || { echo "can't read '$picked'" >&2; exit 1; }

cp "$picked" "$BG"

if ! grep -q '^\[background\]' "$INI" 2>/dev/null; then
  {
    echo
    echo "[background]"
    echo "image = ${BG}"
  } >> "$INI"
elif ! grep -q '^image *=' "$INI"; then
  sed -i "/^\[background\]/a image = ${BG}" "$INI"
else
  sed -i "s|^image *=.*|image = ${BG}|" "$INI"
fi

pkill -x wf-background 2>/dev/null
sleep 0.3
wf-background &
disown
