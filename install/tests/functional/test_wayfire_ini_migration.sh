#!/bin/bash
# FUNCTIONAL TEST (needs sudo; creates and deletes a disposable account).
# Runs the real ensure_core_wayfire_ini() as root against an older
# installer's wayfire.ini (plus a term1 line): settings added, nothing
# else changed, still user-owned, second run a no-op, and the result
# loads in a real headless wayfire.
#
# No -e: assertions record failures and keep going.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/testlib.sh

INSTALL_DIR="$(cd ../.. && pwd)"

if [ "$(id -u)" -ne 0 ] && ! sudo -n true 2>/dev/null; then
  echo "test_wayfire_ini_migration: skipped (needs passwordless sudo)"
  exit 0
fi

echo "test_wayfire_ini_migration:"

TESTUSER="wftest-ini-$$"
cleanup() { sudo -n userdel -r "$TESTUSER" >/dev/null 2>&1; }
trap 'cleanup; rm -rf "$SCRATCH"' EXIT
sudo -n useradd -m -U "$TESTUSER"
H="$(getent passwd "$TESTUSER" | cut -d: -f6)"
INI="$H/.config/wayfire.ini"

# An earlier installer's output: no foreign-toplevel, no shell supervisor.
TERM1='term1 = sh -c "sleep 5; foot"'
sudo -n -u "$TESTUSER" mkdir -p "$H/.config"
{
  echo "[core]"
  echo "plugins = autostart wayfire-shell resize move grid wobbly decoration place"
  echo
  echo "[autostart]"
  echo "$TERM1"
  echo "fix_output = /usr/local/bin/fix-output-mode.sh"
  echo "polkit_agent = lxpolkit"
  echo
  echo "[move]"
  echo "activate = <alt> BTN_LEFT"
} | sudo -n -u "$TESTUSER" tee "$INI" >/dev/null
before="$(sudo -n cat "$INI")"

funcs="$(source "$INSTALL_DIR/lib/common.sh"; declare -f ensure_core_wayfire_ini backup_file write_owned_file log; declare -p CORE_PLUGIN_ADD CORE_SHELL_CMD)"
migrate() { sudo -n bash -c "$funcs"$'\n'"ensure_core_wayfire_ini '$TESTUSER' '$INI'" >/dev/null 2>&1; }

migrate
after="$(sudo -n cat "$INI")"
plugins="$(grep '^plugins' <<< "$after")"
assert_contains "foreign-toplevel is added to the plugins (the panel's window list needs it)" \
  "$plugins" " foreign-toplevel"
assert_eq "the existing plugins are all still there, in order" \
  "${plugins% foreign-toplevel}" "plugins = autostart wayfire-shell resize move grid wobbly decoration place"
assert_contains "wayfire's own one-shot panel/background autostart is turned off" \
  "$after" "autostart_wf_shell = false"
assert_contains "the supervisor is started instead" \
  "$after" "shell = /usr/local/bin/wf-shell-supervisor.sh"
assert_contains "wayfire-customize.sh's term1 line survives" "$after" "$TERM1"
assert_eq "nothing else in the file changed" \
  "$(grep -vE '^(plugins|autostart_wf_shell|shell) =' <<< "$after")" \
  "$(grep -vE '^plugins =' <<< "$before")"
assert_eq "the user still owns their wayfire.ini" "$(sudo -n stat -c %U "$INI")" "$TESTUSER"
assert_eq "the previous version was backed up, once" \
  "$(sudo -n bash -c "ls '$INI'.bak-* 2>/dev/null | wc -l" | tr -d ' ')" "1"
assert_eq "the backup holds the previous version" \
  "$(sudo -n bash -c "cat '$INI'.bak-*")" "$before"

sleep 1   # backup names are second-resolution timestamps
migrate
assert_eq "a second run leaves the file byte-identical" "$(sudo -n cat "$INI")" "$after"
assert_eq "a second run makes no further backup" \
  "$(sudo -n bash -c "ls '$INI'.bak-* 2>/dev/null | wc -l" | tr -d ' ')" "1"

RENDER_NODE=/dev/dri/renderD128
if [ -r "$RENDER_NODE" ] && command -v wayfire >/dev/null; then
  sudo -n cat "$INI" > "$SCRATCH/migrated.ini"
  # Scratch HOME/runtime/bus: keep the autostarted supervisor away from
  # the real account.
  out="$(timeout 4 env HOME="$SCRATCH" XDG_RUNTIME_DIR="$SCRATCH" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$SCRATCH/no-bus" \
    WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_RENDER_DRM_DEVICE="$RENDER_NODE" \
    WAYFIRE_CONFIG_FILE="$SCRATCH/migrated.ini" wayfire 2>&1)"
  assert_not_contains "the migrated file loads under a real wayfire without plugin errors" \
    "$out" "Failed to load plugin"
else
  echo "  skip - no readable $RENDER_NODE or wayfire not installed (headless load check)"
fi

summarize_and_exit
