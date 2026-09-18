#!/bin/bash
# wayfire-customize.sh -- personal wayfire desktop customization.
#
# Run this as yourself (from your app menu's "Customize Desktop" entry,
# or directly from a terminal) -- it never needs root, because every
# package any of these extras could possibly need was already installed
# for everyone by the core installer.
#
# Prompts for a small set of optional extras (an autostart terminal,
# a weather widget, extra clocks, the Synaptic launcher) and remembers
# your answers in ~/.config/wayfire-customize.conf, so running it again
# re-applies (or lets you change) the same setup -- handy for rebuilding
# your environment from scratch on a fresh account.
#
#   wayfire-customize.sh          interactive prompts, then applies them
#   wayfire-customize.sh --apply  re-applies saved answers, no prompts
#   wayfire-customize.sh --show   prints saved answers and exits
#
# Core-owned files (wayfire.ini, wf-shell.ini) are only ever touched
# inside a clearly marked block or a single well-known line -- everything
# the core installer put there stays untouched.
#
# WAYFIRE_INI/WFSHELL_INI/CONF/SUPPORT/DRM_SYS_PATH below can be
# overridden by the environment before running or sourcing this file --
# that's for install/tests/ to point at scratch files and a fake sysfs
# tree instead of a real $HOME and real hardware, nothing else should
# ever need to set them.

# No -e: this script leans on bare `cond && action` one-liners with no
# `||` fallback (e.g. `[ -f "$CONF" ] && source "$CONF"` in
# load_defaults, `[ "$best_w" -gt 0 ] && break` in detect_resolution)
# where "cond" is false on entirely normal runs -- no saved conf file
# yet on a first run, no better DRM mode found on this loop iteration.
# -e would abort on any of those instead of falling through to the
# next line as intended.
set -uo pipefail

WAYFIRE_INI="${WAYFIRE_INI:-$HOME/.config/wayfire.ini}"
WFSHELL_INI="${WFSHELL_INI:-$HOME/.config/wf-shell.ini}"
CONF="${CONF:-$HOME/.config/wayfire-customize.conf}"
SUPPORT="${SUPPORT:-/usr/local/lib/wayfire-customize}"
BEGIN_MARK="# --- wayfire-customize: begin managed block (do not edit by hand) ---"
END_MARK="# --- wayfire-customize: end managed block ---"

confirm() {
  local prompt="$1" default="${2:-y}" reply hint
  hint="y/N"; [ "$default" = y ] && hint="Y/n"
  read -rp "$prompt [$hint] " reply
  reply="${reply:-$default}"
  [[ "$reply" =~ ^[Yy] ]]
}

# Resolves 'quarter' or 'full' against the actually-connected output's
# real maximum mode, so "a quarter-sized terminal" means the same thing
# on any screen instead of everyone guessing pixel counts for their own
# device.
#
# Deliberately the largest mode by area, not just the first line of the
# connector's modes list -- on this box's crosvm virtual display, the
# first-listed mode tracks the Android Linux Terminal app's own window
# size at the moment this connector was last probed, not the display's
# real maximum, and can change from one session to the next. Using
# that as "the screen size" would make "quarter" resolve against a
# moving target instead of the actual hardware.
detect_resolution() {
  local card mode drm_path="${DRM_SYS_PATH:-/sys/class/drm}" w h
  local best_w=0 best_h=0
  for card in "$drm_path"/card*-*; do
    [ "$(cat "${card}/status" 2>/dev/null)" = "connected" ] || continue
    while read -r mode; do
      [ -n "$mode" ] || continue
      w="${mode%x*}"; h="${mode#*x}"
      if [ $((w * h)) -gt $((best_w * best_h)) ]; then
        best_w="$w"; best_h="$h"
      fi
    done < "${card}/modes"
    [ "$best_w" -gt 0 ] && break
  done
  [ "$best_w" -gt 0 ] && echo "${best_w}x${best_h}"
}

resolve_foot_args() {
  case "$1" in
    full) ;;
    quarter)
      local res w h
      res="$(detect_resolution)"
      if [ -n "$res" ]; then
        w="${res%x*}"; h="${res#*x}"
        echo "--window-size-pixels=$((w / 2))x$((h / 2))"
      else
        echo "--window-size-pixels=960x540"
      fi
      ;;
    *) echo "--window-size-pixels=$1" ;;
  esac
}

load_defaults() {
  WANT_FOOT=y
  FOOT_SIZE=quarter
  WANT_WEATHER=n
  WEATHER_LOC=""
  WEATHER_LAT=""
  WEATHER_LON=""
  WANT_CLOCK=n
  CLOCK_SPEC=""
  WANT_SYNAPTIC=n
  # shellcheck disable=SC1090
  [ -f "$CONF" ] && source "$CONF"
}

save_conf() {
  {
    echo "WANT_FOOT=$WANT_FOOT"
    echo "FOOT_SIZE=$(printf '%q' "$FOOT_SIZE")"
    echo "WANT_WEATHER=$WANT_WEATHER"
    echo "WEATHER_LOC=$(printf '%q' "$WEATHER_LOC")"
    echo "WEATHER_LAT=$(printf '%q' "$WEATHER_LAT")"
    echo "WEATHER_LON=$(printf '%q' "$WEATHER_LON")"
    echo "WANT_CLOCK=$WANT_CLOCK"
    echo "CLOCK_SPEC=$(printf '%q' "$CLOCK_SPEC")"
    echo "WANT_SYNAPTIC=$WANT_SYNAPTIC"
  } > "$CONF"
}

prompt_answers() {
  confirm "Autostart a terminal (foot) when your desktop starts?" "$WANT_FOOT" && WANT_FOOT=y || WANT_FOOT=n
  if [ "$WANT_FOOT" = y ]; then
    read -rp "Foot window size -- 'quarter', 'full', or WIDTHxHEIGHT [${FOOT_SIZE}]: " sz
    FOOT_SIZE="${sz:-$FOOT_SIZE}"
  fi

  confirm "Weather widget on the panel?" "$WANT_WEATHER" && WANT_WEATHER=y || WANT_WEATHER=n
  if [ "$WANT_WEATHER" = y ]; then
    read -rp "Location name (e.g. 'Surfers Paradise, QLD') [${WEATHER_LOC}]: " loc
    WEATHER_LOC="${loc:-$WEATHER_LOC}"
    local geo lat lon
    geo="$(curl -s "https://geocoding-api.open-meteo.com/v1/search?count=1&name=$(jq -rn --arg l "$WEATHER_LOC" '$l|@uri')")"
    lat="$(echo "$geo" | jq -r '.results[0].latitude // empty')"
    lon="$(echo "$geo" | jq -r '.results[0].longitude // empty')"
    if [ -z "$lat" ] || [ -z "$lon" ]; then
      echo "couldn't geocode '$WEATHER_LOC' -- enter coordinates manually"
      read -rp "  latitude [${WEATHER_LAT}]: " lat
      read -rp "  longitude [${WEATHER_LON}]: " lon
      lat="${lat:-$WEATHER_LAT}"
      lon="${lon:-$WEATHER_LON}"
    fi
    WEATHER_LAT="$lat"
    WEATHER_LON="$lon"
  fi

  confirm "Extra clock widget(s) for other timezones?" "$WANT_CLOCK" && WANT_CLOCK=y || WANT_CLOCK=n
  if [ "$WANT_CLOCK" = y ]; then
    echo "Entries as 'LABEL TZ' (e.g. 'BKK Asia/Bangkok'), one per line, blank to finish:"
    local entries=() label tzname
    while true; do
      read -rp "  > " label tzname
      [ -z "$label" ] && break
      entries+=("${label}:${tzname}")
    done
    if [ "${#entries[@]}" -gt 0 ]; then
      CLOCK_SPEC="$(IFS=';'; echo "${entries[*]}")"
    fi
  fi

  confirm "Synaptic package-manager launcher on the panel?" "$WANT_SYNAPTIC" && WANT_SYNAPTIC=y || WANT_SYNAPTIC=n
}

apply_wayfire_ini() {
  sed -i '/^term1 = /d' "$WAYFIRE_INI"
  if [ "$WANT_FOOT" = y ]; then
    local args term1_line
    args="$(resolve_foot_args "$FOOT_SIZE")"
    install -d -m 755 "$HOME/.cache"
    term1_line="term1 = sh -c \"sleep 5; foot ${args} > \\\"\$HOME/.cache/foot-stdout.log\\\" 2> \\\"\$HOME/.cache/foot-stderr.log\\\"\""
    sed -i "/^\[autostart\]/a ${term1_line//\\/\\\\}" "$WAYFIRE_INI"
  fi
}

apply_wfshell_ini() {
  sed -i "/^${BEGIN_MARK}\$/,/^${END_MARK}\$/d" "$WFSHELL_INI"
  install -d -m 755 "$HOME/.local/bin"

  local extra=""

  if [ "$WANT_WEATHER" = y ] && [ -n "$WEATHER_LAT" ] && [ -n "$WEATHER_LON" ]; then
    sed "s|__LAT__|${WEATHER_LAT}|; s|__LON__|${WEATHER_LON}|" "$SUPPORT/owf-update-weather.sh.tmpl" > "$HOME/.local/bin/owf-update-weather.sh"
    chmod 755 "$HOME/.local/bin/owf-update-weather.sh"
    install -m 755 "$SUPPORT/panel-weather.sh" "$HOME/.local/bin/panel-weather.sh"

    install -d -m 755 "$HOME/.config/systemd/user"
    install -m 644 "$SUPPORT/owf-weather.service" "$HOME/.config/systemd/user/owf-weather.service"
    install -m 644 "$SUPPORT/owf-weather.timer" "$HOME/.config/systemd/user/owf-weather.timer"
    systemctl --user daemon-reload
    systemctl --user enable --now owf-weather.timer

    extra+="
command_output_weather = ${HOME}/.local/bin/panel-weather.sh
command_output_period_weather = 60
command_output_icon_weather = weather-few-clouds-symbolic
command_output_icon_size_weather = 0
command_output_icon_position_weather = left
"
  else
    systemctl --user disable --now owf-weather.timer >/dev/null 2>&1 || true
  fi

  if [ "$WANT_CLOCK" = y ] && [ -n "$CLOCK_SPEC" ]; then
    local clock_fmt="" e label tzname entries
    IFS=';' read -ra entries <<< "$CLOCK_SPEC"
    for e in "${entries[@]}"; do
      label="${e%%:*}"
      tzname="${e#*:}"
      clock_fmt+="\"${label} \$(TZ=${tzname} date +%H:%M)  \" "
    done
    {
      echo '#!/bin/bash'
      echo "printf '%s' $clock_fmt"
    } > "$HOME/.local/bin/panel-extraclock.sh"
    chmod 755 "$HOME/.local/bin/panel-extraclock.sh"

    extra+="
command_output_extraclock = ${HOME}/.local/bin/panel-extraclock.sh
command_output_period_extraclock = 30
command_output_icon_extraclock =
command_output_icon_size_extraclock = 0
command_output_icon_position_extraclock = left
"
  else
    rm -f "$HOME/.local/bin/panel-extraclock.sh"
  fi

  if [ "$WANT_SYNAPTIC" = y ]; then
    extra+="
launcher_cmd_synaptic = /usr/local/bin/pkexec-wayland /usr/sbin/synaptic
launcher_icon_synaptic = synaptic
launcher_label_synaptic = Software Updater
"
  fi

  if [ -n "$extra" ]; then
    {
      echo "$BEGIN_MARK"
      echo "$extra"
      echo "$END_MARK"
    } >> "$WFSHELL_INI"
  fi
}

restart_panel_if_running() {
  if [ -n "${WAYLAND_DISPLAY:-}" ] && pgrep -x wf-panel >/dev/null 2>&1; then
    pkill -x wf-panel
    ( wf-panel & disown ) 2>/dev/null
  else
    echo "(wf-panel isn't running in this session, or WAYLAND_DISPLAY isn't set -- restart it yourself, or just switch desktops, to see panel changes.)"
  fi
}

main() {
  [ -f "$WAYFIRE_INI" ] || { echo "no $WAYFIRE_INI -- run the core installer for this account first" >&2; exit 1; }

  load_defaults

  local mode=prompt
  case "${1:-}" in
    --show)
      [ -f "$CONF" ] && cat "$CONF" || echo "no saved customization yet -- run wayfire-customize.sh"
      exit 0
      ;;
    --apply) mode=apply ;;
    "") mode=prompt ;;
    *) echo "usage: wayfire-customize.sh [--apply|--show]" >&2; exit 1 ;;
  esac

  if [ "$mode" = prompt ]; then
    prompt_answers
    save_conf
  fi

  if [ "$mode" = apply ] && [ ! -f "$CONF" ]; then
    echo "no saved customization yet -- run wayfire-customize.sh without --apply first" >&2
    exit 1
  fi

  apply_wayfire_ini
  apply_wfshell_ini

  echo
  echo "Applied. Panel changes take effect now; the autostart-terminal change"
  echo "applies next time this desktop starts."
  restart_panel_if_running
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
