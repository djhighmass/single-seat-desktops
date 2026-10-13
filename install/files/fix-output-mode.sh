#!/bin/bash
# fix-output-mode.sh -- forces the compositor's live output to its largest
# mode in the orientation of the preferred mode (the Android window's
# current shape), via wlr-randr, every time wayfire starts (run from
# wayfire.ini's own [autostart]) and after wf-panel restarts.
#
# Necessary because wayfire's built-in "auto" mode setting follows
# whatever mode crosvm's virtual display currently flags as "preferred"
# -- which tracks the Android Linux Terminal app's own window state
# (size, rotation, foreground/background) rather than the display's
# real maximum, and can leave most of the desktop blank if the two
# diverge. The connector's *name* isn't stable either -- it can rename
# itself mid-session on a hotplug -- which rules out pinning a mode by
# connector name in wayfire.ini at install time; this re-detects the
# live connector fresh on every compositor start instead.
#
# No -e: the retry loop below expects wlr-randr to keep failing
# (nonzero) for up to ~10s while the compositor's socket comes up --
# -e would abort on the very first failed attempt instead of retrying.
set -uo pipefail

# wlr-randr needs the compositor's Wayland socket up first -- give it a
# few seconds rather than failing silently on a slow start.
for _ in $(seq 1 20); do
  info="$(wlr-randr 2>/dev/null)"
  [ -n "$info" ] && break
  sleep 0.5
done
[ -n "${info:-}" ] || exit 0

name="$(echo "$info" | head -1 | awk '{print $1}')"
[ -n "$name" ] || exit 0

# Keep the preferred mode's orientation; any mode if none is marked preferred.
orient() { if [ "${1%x*}" -lt "${1#*x}" ]; then echo portrait; else echo landscape; fi; }
preferred="$(echo "$info" | grep -oP '^\s+\K[0-9]+x[0-9]+(?= px.*preferred)' | head -1)"
want=any
[ -n "$preferred" ] && want="$(orient "$preferred")"

best="" best_area=0
while read -r mode; do
  [ -n "$mode" ] || continue
  [ "$want" = any ] || [ "$(orient "$mode")" = "$want" ] || continue
  w="${mode%x*}"; h="${mode#*x}"
  area=$((w * h))
  if [ "$area" -gt "$best_area" ]; then
    best_area="$area"
    best="$mode"
  fi
done < <(echo "$info" | grep -oP '^\s+\K[0-9]+x[0-9]+(?= px)')
[ -n "$best" ] || exit 0

wlr-randr --output "$name" --mode "$best" 2>/dev/null
