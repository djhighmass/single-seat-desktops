# shellcheck shell=bash
# Shared helpers for the optional app installers in apps/. Sourced by
# apps/install.sh and by each apps/<app>/install.sh and defaults.sh.
# Nothing here depends on install/: the app layer stands on its own.

C_RESET=$'\033[0m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'

log()  { echo "${C_GREEN}==${C_RESET} $*"; }
warn() { echo "${C_YELLOW}!!${C_RESET} $*" >&2; }
die()  { echo "${C_RED}!!${C_RESET} $*" >&2; exit 1; }

require_root() {
  [ "$(id -u)" -eq 0 ] || die "run this as root (sudo $0 ...)"
}

# Overridable for tests only; production never sets these.
APT_GET="${APT_GET:-apt-get}"
APT_KEYRINGS_DIR="${APT_KEYRINGS_DIR:-/etc/apt/keyrings}"
APT_SOURCES_DIR="${APT_SOURCES_DIR:-/etc/apt/sources.list.d}"

apt_ensure() {
  # apt_ensure pkg... -- installs whichever of the packages aren't installed.
  local missing=() p
  for p in "$@"; do
    dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
  done
  [ "${#missing[@]}" -eq 0 ] && return 0
  log "installing: ${missing[*]}"
  DEBIAN_FRONTEND=noninteractive "$APT_GET" install -y "${missing[@]}"
}

# --- per-user default settings (defaults.sh) ---------------------------------
# A defaults.sh runs AS the user it configures (never as root), so every file
# it writes is the user's own. It only adds a setting the user hasn't set.

ini_ensure_key() {
  # ini_ensure_key <file> <section> <key> <value> [min]
  # Sets key=value under [section] if the key is absent. With "min", an
  # existing numeric value below <value> is raised; anything else the user
  # set is kept. Creates the file (and section) if needed. Prints "changed"
  # when it wrote the file.
  local f="$1" sec="$2" key="$3" val="$4" mode="${5:-}" tmp
  mkdir -p "$(dirname "$f")"
  [ -f "$f" ] || : > "$f"
  tmp="$(mktemp)"
  awk -v sec="[$sec]" -v key="$key" -v val="$val" -v mode="$mode" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    { lines[NR] = $0
      t = trim($0)
      if (t ~ /^\[.*\]$/) { cur = t; if (t == sec && !hdr) hdr = NR; next }
      if (cur == sec && index(t, key "=") == 1) { found = NR; old = substr(t, length(key) + 2) } }
    END {
      for (i = 1; i <= NR; i++) {
        l = lines[i]
        if (i == found && mode == "min" && old ~ /^[0-9]+$/ && old + 0 < val + 0) l = key "=" val
        print l
        if (i == hdr && !found) print key "=" val
      }
      if (!hdr) { print sec; print key "=" val }
    }' "$f" > "$tmp"
  if cmp -s "$tmp" "$f"; then
    rm -f "$tmp"
  else
    cat "$tmp" > "$f"; rm -f "$tmp"
    echo changed
  fi
}
