#!/bin/bash
# Runs as the session user inside the container: launches wayfire nested
# in a window on the host's X server or Wayland compositor, and relaunches it when dev-restart
# asks (so a freshly installed ~/.config/wayfire.ini gets picked up).
# Closing the window (wayfire exits without the restart flag) ends the
# session and the container.
set -uo pipefail

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export WLR_RENDERER=pixman
# Name the render node explicitly. On a Wayland host wlroots otherwise asks
# the host compositor which device to use, and not every compositor's
# answer works out ("Failed to get DRM file descriptor").
[ -e /dev/dri/renderD128 ] && export WLR_RENDER_DRM_DEVICE=/dev/dri/renderD128
if [ "${DEV_HOST_MODE:-x11}" = wayland ]; then
  # Nested in the host's compositor. The absolute path is only for
  # wayfire's own backend connection; wayfire then serves its own
  # wayland-N socket in $XDG_RUNTIME_DIR to everything it launches.
  export WLR_BACKENDS=wayland WAYLAND_DISPLAY=/run/host-wayland/socket
  unset DISPLAY XAUTHORITY
else
  export WLR_BACKENDS=x11 XAUTHORITY=/run/dev-session/xauth
fi
export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=wayfire
export DEV_SESSION=1
FLAG=/run/dev-session/restart

while :; do
  rm -f "$FLAG" "$XDG_RUNTIME_DIR"/wayland-*
  if [ -f "$HOME/.config/wayfire.ini" ]; then
    cfg="$HOME/.config/wayfire.ini"; echo "== wayfire using $cfg"
  else
    cfg=/usr/local/lib/dev-session/bootstrap-wayfire.ini
    echo "== no ~/.config/wayfire.ini yet -- wayfire using the bootstrap config"
  fi
  WAYFIRE_CONFIG_FILE="$cfg" dbus-run-session -- wayfire
  rc=$?
  if [ -e "$FLAG" ]; then echo "== restarting wayfire"; continue; fi
  echo "== wayfire exited (rc=$rc); ending session"
  exit "$rc"
done
