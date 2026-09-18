# shellcheck shell=bash
# Shared helpers for the wayfire multi-user desktop installer.
# Sourced by 00-create-users.sh and 10-install-wayfire-desktops.sh.

C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'

log()  { echo "${C_GREEN}==${C_RESET} $*"; }
warn() { echo "${C_YELLOW}!!${C_RESET} $*" >&2; }
err()  { echo "${C_RED}!!${C_RESET} $*" >&2; }
die()  { err "$*"; exit 1; }

require_root() {
  [ "$(id -u)" -eq 0 ] || die "run this as root (sudo $0 ...)"
}

pkg_ensure() {
  # pkg_ensure pkg1 pkg2 ... -- installs whichever of the given packages
  # aren't already installed, in one apt-get call.
  local missing=()
  for p in "$@"; do
    dpkg -s "$p" &>/dev/null || missing+=("$p")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    log "installing packages: ${missing[*]}"
    apt-get update -qq
    apt-get install -y "${missing[@]}"
  fi
}

backup_file() {
  # backup_file /path/to/file -- copies to /path/to/file.bak-<timestamp>
  # only if the file exists and differs from nothing (always backs up
  # an existing file before this installer overwrites it).
  local f="$1"
  [ -e "$f" ] || return 0
  cp -a "$f" "${f}.bak-$(date +%Y%m%d-%H%M%S)"
}

# Home directory and uid lookups that work regardless of who's asking.
user_home() { getent passwd "$1" | cut -d: -f6; }
user_uid()  { id -u "$1"; }

write_owned_file() {
  # write_owned_file <user> <path> <mode> <<'EOF' ... EOF
  local u="$1" path="$2" mode="$3"
  local tmp
  tmp="$(mktemp)"
  cat > "$tmp"
  install -o "$u" -g "$u" -m "$mode" "$tmp" "$path"
  rm -f "$tmp"
}
