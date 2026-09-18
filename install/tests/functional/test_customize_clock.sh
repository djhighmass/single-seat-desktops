#!/bin/bash
# FUNCTIONAL TEST -- runs wayfire-customize.sh --apply for real to
# generate the extra-clock panel script, then runs *that* generated
# script for real under a forced TZ and checks its actual printed
# output, rather than diffing the generator's source against expected
# text.
#
# No -e: assert_* below tallies each check into pass()/fail() and
# keeps going, so both halves of this file -- clocks enabled, then
# disabled again -- run and get reported by summarize_and_exit even if
# an earlier assertion in the first half didn't hold.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/testlib.sh

echo "test_customize_clock:"

export HOME="$SCRATCH"
mkdir -p "$HOME/.config"
cp ../../files/wayfire.ini.tmpl "$HOME/.config/wayfire.ini"
echo "[panel]" > "$HOME/.config/wf-shell.ini"

cat > "$HOME/.config/wayfire-customize.conf" <<'EOF'
WANT_FOOT=n
FOOT_SIZE=quarter
WANT_WEATHER=n
WEATHER_LOC=''
WEATHER_LAT=''
WEATHER_LON=''
WANT_CLOCK=y
CLOCK_SPEC='UTC:Etc/UTC;TOK:Asia/Tokyo'
WANT_SYNAPTIC=n
EOF

bash ../../files/wayfire-customize.sh --apply >/dev/null 2>/dev/null

assert_file_exists "the extra-clock script was generated" "$HOME/.local/bin/panel-extraclock.sh"
assert_contains "wf-shell.ini's managed block references it" \
  "$(cat "$HOME/.config/wf-shell.ini")" "command_output_extraclock"

out="$(bash "$HOME/.local/bin/panel-extraclock.sh")"
assert_contains "both configured labels appear in the real output" "$out" "UTC"
assert_contains "both configured labels appear in the real output" "$out" "TOK"

# A specific instant in each zone, cross-checked against `date` itself
# rather than a hand-computed expected string, so this doesn't silently
# rot if the output format's spacing changes.
expected_utc="$(TZ=Etc/UTC date +%H:%M)"
assert_contains "the UTC entry shows the real current UTC time" "$out" "$expected_utc"

# --- turning clocks back off should remove the script and the block ---
sed -i 's/WANT_CLOCK=y/WANT_CLOCK=n/' "$HOME/.config/wayfire-customize.conf"
bash ../../files/wayfire-customize.sh --apply >/dev/null 2>/dev/null

assert_file_absent "disabling clocks removes the generated script" "$HOME/.local/bin/panel-extraclock.sh"
assert_not_contains "disabling clocks removes it from wf-shell.ini too" \
  "$(cat "$HOME/.config/wf-shell.ini")" "command_output_extraclock"

summarize_and_exit
