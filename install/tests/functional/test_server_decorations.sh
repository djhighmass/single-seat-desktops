#!/bin/bash
# FUNCTIONAL TEST (needs sudo; creates and deletes a disposable account).
# Runs the real ensure_server_decorations() as root: the setting goes into
# [core], an explicit mode is kept, the file stays user-owned, and a second
# run is a no-op.
#
# No -e: assertions record failures and keep going.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/testlib.sh

INSTALL_DIR="$(cd ../.. && pwd)"

if [ "$(id -u)" -ne 0 ] && ! sudo -n true 2>/dev/null; then
  echo "test_server_decorations: skipped (needs passwordless sudo)"
  exit 0
fi

echo "test_server_decorations:"

TESTUSER="wftest-deco-$$"
cleanup() { sudo -n userdel -r "$TESTUSER" >/dev/null 2>&1; }
trap 'cleanup; rm -rf "$SCRATCH"' EXIT
sudo -n useradd -m -U "$TESTUSER"
H="$(getent passwd "$TESTUSER" | cut -d: -f6)"
INI="$H/.config/wayfire.ini"
sudo -n -u "$TESTUSER" mkdir -p "$H/.config"

funcs="$(source "$INSTALL_DIR/lib/common.sh"; declare -f ensure_server_decorations backup_file write_owned_file log; declare -p C_RESET C_GREEN)"
run() { sudo -n bash -c "$funcs"$'\n'"ensure_server_decorations '$TESTUSER' '$INI'" >/dev/null 2>&1; }
put() { printf "$1" | sudo -n -u "$TESTUSER" tee "$INI" >/dev/null; }

# --- D.1: added right under [core] ---
put '[core]   # main\nplugins = autostart decoration\n\n[move]\nactivate = <alt> BTN_LEFT\n'
run
ini="$(sudo -n cat "$INI")"
assert_contains "the setting goes right under the [core] header" "$ini" \
  $'[core]   # main\npreferred_decoration_mode = server\nplugins = autostart decoration'
assert_contains "the rest of the file survives" "$ini" "activate = <alt> BTN_LEFT"
assert_eq "the user still owns their wayfire.ini" "$(sudo -n stat -c %U "$INI")" "$TESTUSER"

# --- D.2: a second run changes nothing ---
sleep 1
run
assert_eq "a second run leaves the file byte-identical" "$(sudo -n cat "$INI")" "$ini"
assert_eq "one backup in total" "$(sudo -n bash -c "ls '$INI'.bak-* | wc -l" | tr -d ' ')" "1"

# --- D.3: an explicit choice is kept ---
put '[core]\n  preferred_decoration_mode = client  # I like CSD\nplugins = autostart\n'
before="$(sudo -n cat "$INI")"
run
assert_eq "an explicit preferred_decoration_mode is left as is" "$(sudo -n cat "$INI")" "$before"

# --- D.4: no [core] section yet ---
put '[move]\nactivate = <alt> BTN_LEFT\n'
run
assert_contains "a [core] section is added with the setting" "$(sudo -n cat "$INI")" \
  $'[core]\npreferred_decoration_mode = server'

# --- D.5: the template has it ---
assert_eq "template sets server decorations once" \
  "$(grep -c '^preferred_decoration_mode = server$' "$INSTALL_DIR/files/wayfire.ini.tmpl")" "1"

summarize_and_exit
