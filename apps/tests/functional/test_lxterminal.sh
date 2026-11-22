#!/bin/bash
# FUNCTIONAL TEST (no sudo) -- apps/lxterminal: install.sh refuses to run
# without root and installs through apt (stub); defaults.sh, run as a normal
# user against a scratch HOME, raises the scrollback and keeps the rest.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/testlib.sh
APP="$(cd ../../lxterminal && pwd)"

echo "test_lxterminal:"

# --- X.1: install.sh needs root ---
if [ "$(id -u)" -ne 0 ]; then
  assert_failure "install.sh refuses to run without root" bash "$APP/install.sh"
fi
assert_contains "install.sh has a menu description" "$(sed -n 2p "$APP/install.sh")" "# DESCRIPTION: LXTerminal"

# --- X.2: install.sh installs lxterminal through apt (stubbed) ---
if sudo -n true 2>/dev/null; then
  printf '#!/bin/sh\necho "$@" > %s/apt-args\n' "$SCRATCH" > "$SCRATCH/apt-get"; chmod +x "$SCRATCH/apt-get"
  # dpkg -s fails for the made-up package, so it always counts as missing.
  sudo -n env APT_GET="$SCRATCH/apt-get" bash -c "
    source '$APP/../lib/common.sh'; apt_ensure lxterminal-not-installed-$$" >/dev/null 2>&1
  assert_eq "apt-get is asked to install the missing package" "$(cat "$SCRATCH/apt-args")" "install -y lxterminal-not-installed-$$"
  if dpkg -s lxterminal >/dev/null 2>&1; then
    rm -f "$SCRATCH/apt-args"
    sudo -n env APT_GET="$SCRATCH/apt-get" bash "$APP/install.sh" >/dev/null 2>&1
    assert_file_absent "an installed lxterminal is not reinstalled" "$SCRATCH/apt-args"
  fi
fi

# --- X.3: defaults.sh on a fresh HOME ---
H="$SCRATCH/home"; mkdir -p "$H"
out="$(env -u XDG_CONFIG_HOME HOME="$H" bash "$APP/defaults.sh")"
assert_eq "fresh config gets the scrollback" "$(cat "$H/.config/lxterminal/lxterminal.conf")" $'[general]\nscrollback=10000'
assert_contains "it says what it did" "$out" "scrollback"

# --- X.4: an existing config: raised, rest kept; then idempotent ---
printf '[general]\nfontname=Monospace 10\nscrollback=1000\n' > "$H/.config/lxterminal/lxterminal.conf"
env -u XDG_CONFIG_HOME HOME="$H" bash "$APP/defaults.sh" >/dev/null
conf="$(cat "$H/.config/lxterminal/lxterminal.conf")"
assert_eq "scrollback raised, font kept" "$conf" $'[general]\nfontname=Monospace 10\nscrollback=10000'
out="$(env -u XDG_CONFIG_HOME HOME="$H" bash "$APP/defaults.sh")"
assert_eq "a second run changes nothing" "$(cat "$H/.config/lxterminal/lxterminal.conf")" "$conf"
assert_eq "and says nothing" "$out" ""

# --- X.5: the user's larger value is kept ---
printf '[general]\nscrollback=99999\n' > "$H/.config/lxterminal/lxterminal.conf"
env -u XDG_CONFIG_HOME HOME="$H" bash "$APP/defaults.sh" >/dev/null
assert_eq "a larger scrollback is kept" "$(cat "$H/.config/lxterminal/lxterminal.conf")" $'[general]\nscrollback=99999'

summarize_and_exit
