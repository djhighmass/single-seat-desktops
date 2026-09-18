#!/bin/bash
# FUNCTIONAL TEST -- runs wayfire-customize.sh --apply for real to
# generate the per-user weather fetcher, then runs *that* generated
# script for real against a stub `curl`, checking the actual JSON it
# writes (and, separately, that it correctly refuses to write garbage
# when the upstream API response is missing current_weather, rather
# than overwriting prior good data with a bogus zero reading).
#
# No -e: the second, regression case deliberately feeds the generated
# fetcher a response with no current_weather field at all, which is
# exactly the kind of thing owf-update-weather.sh.tmpl's own `[ -z ...
# ] && exit 1` is designed to handle -- assert_eq afterward checks that
# prior data.json was left untouched, not the fetcher's exit code, and
# every assert_* keeps going so summarize_and_exit still gets a full
# tally.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/testlib.sh

echo "test_customize_weather:"

export HOME="$SCRATCH"
mkdir -p "$HOME/.config"
cp ../../files/wayfire.ini.tmpl "$HOME/.config/wayfire.ini"
echo "[panel]" > "$HOME/.config/wf-shell.ini"

export SUPPORT="$SCRATCH/support"
mkdir -p "$SUPPORT"
cp ../../files/owf-update-weather.sh.tmpl "$SUPPORT/"
cp ../../files/panel-weather.sh "$SUPPORT/"
cp ../../files/owf-weather.service "$SUPPORT/"
cp ../../files/owf-weather.timer "$SUPPORT/"

cat > "$HOME/.config/wayfire-customize.conf" <<'EOF'
WANT_FOOT=n
FOOT_SIZE=quarter
WANT_WEATHER=y
WEATHER_LOC='Testville'
WEATHER_LAT='10.0'
WEATHER_LON='20.0'
WANT_CLOCK=n
CLOCK_SPEC=''
WANT_SYNAPTIC=n
EOF

# systemctl --user calls in apply_wfshell_ini will fail in this scratch
# environment (no real user session pointed at) -- that's expected and
# non-fatal (the script has no `set -e`); silence the noise for the test.
bash ../../files/wayfire-customize.sh --apply >/dev/null 2>/dev/null

assert_file_exists "the per-user weather fetcher was generated" "$HOME/.local/bin/owf-update-weather.sh"
assert_contains "the fetcher has the configured coordinates baked in" \
  "$(cat "$HOME/.local/bin/owf-update-weather.sh")" "LAT=10.0"
assert_contains "wf-shell.ini's managed block references the weather widget" \
  "$(cat "$HOME/.config/wf-shell.ini")" "command_output_weather"

mkdir -p "$SCRATCH/bin"

# --- success case: a normal Open-Meteo response ---
cat > "$SCRATCH/bin/curl" <<'EOF'
#!/bin/bash
echo '{"current_weather":{"temperature":21.4,"weathercode":1,"is_day":1}}'
EOF
chmod +x "$SCRATCH/bin/curl"

PATH="$SCRATCH/bin:$PATH" bash "$HOME/.local/bin/owf-update-weather.sh"
data_json="$HOME/.local/share/owf/data/data.json"
assert_file_exists "data.json was written on a valid response" "$data_json"
assert_contains "the temperature was rounded and formatted" "$(cat "$data_json")" "21°C"
good_data="$(cat "$data_json")"

# --- regression case: response has no current_weather field at all ---
cat > "$SCRATCH/bin/curl" <<'EOF'
#!/bin/bash
echo '{"error":true,"reason":"rate limited"}'
EOF
chmod +x "$SCRATCH/bin/curl"

PATH="$SCRATCH/bin:$PATH" bash "$HOME/.local/bin/owf-update-weather.sh"
assert_eq "a response with no current_weather leaves prior data untouched (not a bogus 0°C reading)" \
  "$(cat "$data_json")" "$good_data"

summarize_and_exit
