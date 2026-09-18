#!/bin/bash
# FUNCTIONAL TEST -- re-applies wayfire-customize.sh several times in a
# row with different combinations of extras, checking the *real*
# resulting wf-shell.ini after each pass: exactly one managed block,
# containing exactly what the current settings call for and nothing left
# over from a previous combination. Also checks the Synaptic launcher is
# wired through pkexec-wayland (the fix for pkexec silently dropping the
# Wayland session), not the raw synaptic-pkexec wrapper.
#
# No -e: this re-applies wayfire-customize.sh three times in a row
# (on, off, on-on) with an assert_eq/assert_contains after each pass --
# those tally into pass()/fail() and let every later pass still run,
# and summarize_and_exit still report a full tally, even if an earlier
# pass's marker count didn't come out as expected.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/testlib.sh

echo "test_customize_idempotent_block:"

export HOME="$SCRATCH"
mkdir -p "$HOME/.config"
cp ../../files/wayfire.ini.tmpl "$HOME/.config/wayfire.ini"
echo "[panel]" > "$HOME/.config/wf-shell.ini"

count_markers() {
  grep -c '^# --- wayfire-customize: begin managed block' "$HOME/.config/wf-shell.ini"
}

apply_with() {
  cat > "$HOME/.config/wayfire-customize.conf" <<EOF
WANT_FOOT=n
FOOT_SIZE=quarter
WANT_WEATHER=n
WEATHER_LOC=''
WEATHER_LAT=''
WEATHER_LON=''
WANT_CLOCK=n
CLOCK_SPEC=''
WANT_SYNAPTIC=$1
EOF
  bash ../../files/wayfire-customize.sh --apply >/dev/null 2>/dev/null
}

apply_with y
assert_eq "exactly one managed block after enabling Synaptic" "$(count_markers)" "1"
assert_contains "Synaptic is launched through pkexec-wayland, not raw pkexec" \
  "$(cat "$HOME/.config/wf-shell.ini")" "launcher_cmd_synaptic = /usr/local/bin/pkexec-wayland /usr/sbin/synaptic"

apply_with n
assert_eq "still exactly one block, none, after disabling it again" "$(count_markers)" "0"
assert_not_contains "the synaptic launcher line is actually gone, not just an empty block" \
  "$(cat "$HOME/.config/wf-shell.ini")" "synaptic"

apply_with y
apply_with y
assert_eq "re-applying the same settings twice doesn't duplicate the block" "$(count_markers)" "1"

summarize_and_exit
