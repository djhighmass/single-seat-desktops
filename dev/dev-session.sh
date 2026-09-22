#!/bin/bash
# dev-session.sh -- launch a full, visible wayfire desktop as a window on
# this machine's own desktop, running inside the dev container.
#
#   ./dev-session.sh              start (builds the image on first use)
#   ./dev-session.sh --rebuild    rebuild the image first
#   ./dev-session.sh shell        extra root shell in the running session
#
# The host display server is auto-detected; there is nothing to declare:
#   Wayland host (a live socket at $WAYLAND_DISPLAY)  -> WLR_BACKENDS=wayland,
#       the host compositor's socket is passed into the container
#   X11 host ($DISPLAY set)                           -> WLR_BACKENDS=x11,
#       the X socket plus a re-keyed X cookie are passed in
# Native Wayland wins when both exist (e.g. GNOME/KDE also run XWayland).
# Set DEV_SESSION_NAME to run a second session alongside the first.
#
# Both backends still get /dev/dri passed through: they run the software
# (pixman-capable) path but wlroots insists on opening a DRM render node.
#
# Inside the window: a terminal opens with instructions. In short,
# `dev-install` runs the real installer (host account droid, onboard
# wftest), `dev-restart` reloads wayfire with the new config, and
# `dev-customize` runs wayfire-customize.sh -- see /usr/local/lib/dev-session/motd.
# The repo is mounted live at /repo (read-only); the container and
# everything installed into it are discarded when the window closes.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
IMAGE=single-seat-desktops-dev
NAME="${DEV_SESSION_NAME:-single-seat-desktops-session}"
# shellcheck source=runtime.sh
source "$HERE/runtime.sh"

rebuild=n
case "${1:-}" in
  --rebuild) rebuild=y ;;
  shell) ;;
  "") ;;
  -h|--help) sed -n '2,/^set /p' "${BASH_SOURCE[0]}" | grep '^#' | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "unknown argument: $1 (see --help)" >&2; exit 2 ;;
esac

pick_runtime || exit 2

if [ "${1:-}" = shell ]; then
  exec "${RT[@]}" exec -it "$NAME" bash
fi

# ------------------------------------------------- detect the host display --

HOST_MODE=""
if [ -n "${WAYLAND_DISPLAY:-}" ]; then
  WL_SOCK="$WAYLAND_DISPLAY"
  case "$WL_SOCK" in /*) ;; *) WL_SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/$WL_SOCK" ;; esac
  [ -S "$WL_SOCK" ] && HOST_MODE=wayland
fi
if [ -z "$HOST_MODE" ] && [ -n "${DISPLAY:-}" ]; then
  HOST_MODE=x11
fi
[ -n "$HOST_MODE" ] || {
  echo "no display found: neither a live \$WAYLAND_DISPLAY socket nor \$DISPLAY." >&2
  echo "Run this from a graphical session on the machine you want the window on." >&2
  exit 2
}

if [ "$HOST_MODE" = x11 ]; then
  command -v xauth >/dev/null || { echo "xauth not found (apt install xauth)" >&2; exit 2; }
fi

if [ "$rebuild" = y ] || ! "${RT[@]}" image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "building $IMAGE with ${RT[*]} (first time takes a few minutes)..."
  build_image "$IMAGE" "$REPO" || { echo "image build failed" >&2; exit 2; }
fi

# :ro,z SELinux-relabels the mount for container access -- a no-op on a
# non-SELinux host, needed for it to be readable at all on an
# SELinux-enforcing one (common on podman's home turf, Fedora/RHEL).
args=(run --rm --name "$NAME" --ipc=host -v "$REPO:/repo:ro,z" -e "DEV_HOST_MODE=$HOST_MODE")

case "$HOST_MODE" in
  x11)
    # The container has a different hostname, and X cookies are keyed by
    # hostname, so re-key ours with family "wild" (ffff) to match any host.
    # Staged in a private temp dir; only the file itself is mounted.
    STAGE="$(mktemp -d)"
    trap 'rm -rf "$STAGE"' EXIT
    touch "$STAGE/xauth"
    xauth nlist "$DISPLAY" | sed -e 's/^..../ffff/' | xauth -f "$STAGE/xauth" nmerge - 2>/dev/null
    chmod 644 "$STAGE/xauth"
    args+=(-e "DISPLAY=$DISPLAY"
      -v /tmp/.X11-unix:/tmp/.X11-unix
      -v "$STAGE/xauth:/run/dev-session-xauth:ro")
    where="X11 display $DISPLAY"
    ;;
  wayland)
    # Connecting to a unix socket needs write permission on it, and the
    # host compositor's socket belongs to whoever runs it. So the session
    # user inside the container takes that uid (the entrypoint remaps it).
    SOCK_UID="$(stat -c %u "$WL_SOCK")"
    args+=(-v "$WL_SOCK:/run/host-wayland/socket" -e "DEV_HOST_UID=$SOCK_UID")
    where="Wayland compositor $WL_SOCK"
    if [ "$RT_NAME" = podman ]; then
      echo "warning: rootless podman maps the host socket's owner to container root;" >&2
      echo "         the session user may be refused. Docker is the tested path." >&2
    fi
    ;;
esac

if [ -e /dev/dri/renderD128 ]; then
  args+=(--device /dev/dri -e "DEV_RENDER_GID=$(stat -c %g /dev/dri/renderD128)")
else
  echo "warning: no /dev/dri/renderD128 on this host; wayfire will likely fail to start" >&2
fi
[ -t 0 ] && [ -t 1 ] && args+=(-it)

echo "starting nested wayfire on $where -- a window should appear; Ctrl-C here to stop"
"${RT[@]}" "${args[@]}" --entrypoint /usr/local/lib/dev-session/session-entrypoint.sh "$IMAGE"
