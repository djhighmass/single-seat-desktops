#!/bin/bash
# Our default settings for LXTerminal, for the user running this (not root):
# a scrollback of at least 10000 lines (LXTerminal's own default is 1000).
# A larger value you've set is kept.
set -uo pipefail
APPS_DIR="${APPS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/common.sh
source "$APPS_DIR/lib/common.sh"
[ "$(id -u)" -ne 0 ] || die "run this as the user it's for, not as root"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/lxterminal/lxterminal.conf"
if [ "$(ini_ensure_key "$CONF" general scrollback 10000 min)" = changed ]; then
  log "LXTerminal: scrollback is now at least 10000 lines ($CONF)"
fi
