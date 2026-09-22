#!/bin/bash
# Container entrypoint for dev/dev-session.sh. Runs as root just long
# enough to prepare the session user's runtime dir, then hands over to
# session-loop.sh as that user (default wftest).
set -euo pipefail
U="${DEV_USER:-wftest}"

# Wayland host: the compositor socket is owned by the host user's uid and
# connecting needs write access, so the session user takes that uid.
# If an image account already holds it (tester is uid 1000 -- the usual
# host uid), move that account aside first: two names on one uid makes
# id/whoami/prompts in the session report the wrong one.
if [ -n "${DEV_HOST_UID:-}" ] && [ "$DEV_HOST_UID" -ne 0 ] && [ "$DEV_HOST_UID" -ne "$(id -u "$U")" ]; then
  other="$(getent passwd "$DEV_HOST_UID" | cut -d: -f1 || true)"
  [ -n "$other" ] && usermod -u "$((DEV_HOST_UID + 20000))" "$other"
  usermod -u "$DEV_HOST_UID" "$U"
fi
uid="$(id -u "$U")"

# wf-panel's widgets connect to the D-Bus *system* bus at startup and the
# panel never draws if that fails; there's no init here to provide one.
install -d /run/dbus
dbus-daemon --system --fork

# Give the session user read access to the passed-through render node.
if [ -n "${DEV_RENDER_GID:-}" ]; then
  getent group "$DEV_RENDER_GID" >/dev/null || groupadd -g "$DEV_RENDER_GID" hostrender
  usermod -aG "$(getent group "$DEV_RENDER_GID" | cut -d: -f1)" "$U"
fi

install -d -m 700 -o "$U" -g "$U" "/run/user/$uid"
install -d -m 755 -o "$U" -g "$U" /run/dev-session

# The X cookie staged by dev-session.sh, made readable by the session user.
if [ -f /run/dev-session-xauth ]; then
  cp /run/dev-session-xauth /run/dev-session/xauth
  chown "$U:$U" /run/dev-session/xauth
  chmod 600 /run/dev-session/xauth
fi

exec runuser -u "$U" -- /usr/local/lib/dev-session/session-loop.sh
