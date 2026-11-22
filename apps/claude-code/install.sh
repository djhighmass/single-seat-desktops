#!/bin/bash
# DESCRIPTION: Claude Code, Anthropic's coding assistant CLI (Anthropic's apt repository)
# Run as root. Follows Anthropic's documented apt setup
# (https://code.claude.com/docs/en/setup, "Install with Linux package
# managers", apt) step by step. Anthropic doesn't publish a script for this:
#   1. download the signing key to /etc/apt/keyrings/claude-code.asc
#   2. check it holds exactly the fingerprint the page lists
#   3. add the repository and install the claude-code package
# A key that doesn't match is never installed.
#
#   sudo apps/claude-code/install.sh                  stable channel
#   sudo apps/claude-code/install.sh --channel=latest
#
# apt installs don't auto-update: `sudo apt update && sudo apt upgrade claude-code`.
set -uo pipefail
APPS_DIR="${APPS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/common.sh
source "$APPS_DIR/lib/common.sh"

KEY_URL="https://downloads.claude.ai/keys/claude-code.asc"
# The only fingerprint the setup page says the key should have.
KEY_FINGERPRINT="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"
CURL="${CURL:-curl}"

channel=stable
for arg in "$@"; do
  case "$arg" in
    --channel=stable|--channel=latest) channel="${arg#--channel=}" ;;
    *) die "unknown option: $arg (use --channel=stable or --channel=latest)" ;;
  esac
done
require_root

apt_ensure curl gnupg || die "could not install curl and gnupg"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
"$CURL" -fsSL "$KEY_URL" -o "$tmp" || die "could not download $KEY_URL"
fprs="$(gpg --show-keys --with-colons "$tmp" 2>/dev/null | awk -F: '$1 == "pub" { want = 1; next } want && $1 == "fpr" { print $10; want = 0 }')"
[ "$fprs" = "$KEY_FINGERPRINT" ] || die "the downloaded key is not the one Anthropic lists (got: ${fprs:-none}) -- not installing it"

install -d -m 0755 "$APT_KEYRINGS_DIR"
install -m 0644 "$tmp" "$APT_KEYRINGS_DIR/claude-code.asc"
echo "deb [signed-by=$APT_KEYRINGS_DIR/claude-code.asc] https://downloads.claude.ai/claude-code/apt/$channel $channel main" \
  > "$APT_SOURCES_DIR/claude-code.list"
log "Anthropic's apt repository added ($channel channel, key $KEY_FINGERPRINT)"

"$APT_GET" update -qq || die "apt-get update failed"
DEBIAN_FRONTEND=noninteractive "$APT_GET" install -y claude-code || die "could not install claude-code"
log "claude-code installed -- run 'claude' to sign in"
