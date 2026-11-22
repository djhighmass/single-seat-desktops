#!/bin/bash
# DESCRIPTION: LXTerminal, a lightweight tabbed terminal (Debian package)
# Run as root. Installs Debian's lxterminal package.
set -uo pipefail
APPS_DIR="${APPS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/common.sh
source "$APPS_DIR/lib/common.sh"
require_root
apt_ensure lxterminal || die "could not install lxterminal"
log "lxterminal installed"
