#!/bin/bash
# DESCRIPTION: Google Chrome web browser (Google's own .deb, which adds Google's apt repository)
# Run as root. Downloads Google's Chrome .deb for this machine (amd64 or
# arm64) over HTTPS and installs it with apt. The package itself sets up
# Google's apt repository and signing key, so Chrome then updates with the
# rest of the system. No repository address or key is kept in this repo.
set -uo pipefail
APPS_DIR="${APPS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/common.sh
source "$APPS_DIR/lib/common.sh"
CURL="${CURL:-curl}"
DPKG_ARCH="${DPKG_ARCH:-$(dpkg --print-architecture)}"
require_root

if dpkg -s google-chrome-stable >/dev/null 2>&1; then
  log "google-chrome-stable is already installed -- it updates through apt"
  exit 0
fi
case "$DPKG_ARCH" in
  amd64|arm64) ;;
  *) die "Google publishes Chrome for amd64 and arm64 only (this is $DPKG_ARCH)" ;;
esac
apt_ensure curl || die "could not install curl"

dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
chmod 755 "$dir"   # apt's _apt user reads the .deb from here
deb="$dir/google-chrome-stable_current_$DPKG_ARCH.deb"
"$CURL" -fsSL "https://dl.google.com/linux/direct/google-chrome-stable_current_$DPKG_ARCH.deb" -o "$deb" \
  || die "could not download Chrome"
chmod 644 "$deb"
[ "$(dpkg-deb -f "$deb" Package 2>/dev/null)" = google-chrome-stable ] \
  || die "the download isn't Google's google-chrome-stable package -- not installing it"
DEBIAN_FRONTEND=noninteractive "$APT_GET" install -y "$deb" || die "could not install Chrome"
log "Google Chrome installed (Google's apt repository is now set up by the package)"
