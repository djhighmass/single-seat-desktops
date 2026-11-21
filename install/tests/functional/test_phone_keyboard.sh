#!/bin/bash
# FUNCTIONAL TEST -- runs the real files/phone-adb against a stub `adb` (and a
# stub `ip`), and 20-phone-keyboard.sh's helper functions. No phone, no sudo;
# everything lives in $SCRATCH.
#
# No -e: each numbered scenario asserts for itself and must still run when an
# earlier one fails; failures are tallied by summarize_and_exit.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/testlib.sh

echo "test_phone_keyboard:"

PA="$(cd ../.. && pwd)/files/phone-adb"
INSTALLER="$(cd ../.. && pwd)/20-phone-keyboard.sh"
STUB="$SCRATCH/stub"; BIN="$SCRATCH/bin"; mkdir -p "$STUB" "$BIN"

cat > "$BIN/ip" <<'EOF'
#!/bin/bash
echo "default via 10.9.9.1 dev enp0s14 proto dhcp"
EOF
cat > "$BIN/adb" <<'EOF'
#!/bin/bash
# stub adb: state in $STUB
S=$STUB
case "$1" in
  devices) echo "List of devices attached"; [ -f "$S/connected" ] && printf '%s\tdevice\n' "$(cat "$S/connected")"; exit 0 ;;
  connect) echo "$2" >> "$S/connect-log"
           [ "${2##*:}" = "${STUB_OK_PORT:-}" ] && { echo "$2" > "$S/connected"; echo "connected to $2"; } || echo "failed to connect to $2"
           exit 0 ;;
  disconnect) exit 0 ;;
  pair) echo "pair $*" >> "$S/pair-log"; echo "Successfully paired"; exit 0 ;;
  -s) shift 2 ;;
esac
[ "$1" = shell ] || exit 1
shift
cmd="$*"
case "$cmd" in
  "settings get secure default_input_method") cat "$S/ime" ;;
  "ime list -a -s") cat "$S/imes" ;;
  "ime list -s") if [ -n "${STUB_ENABLED:-}" ]; then cat "$STUB_ENABLED"; else cat "$S/enabled-now"; fi ;;
  "ime enable "*) echo "enable ${cmd#ime enable }" >> "$S/enable-log"; grep -qxF "${cmd#ime enable }" "$S/enabled-now" || echo "${cmd#ime enable }" >> "$S/enabled-now" ;;
  "ime set "*) echo "${cmd#ime set }" > "$S/ime" ;;
  "cat > /data/local/tmp/kbd-watch.sh") cat > "$S/watch.sh" ;;
  nohup\ sh\ *) touch "$S/watcher-started" ;;
  "pgrep -f kbd-watch.sh") [ -f "$S/watcher-started" ] && echo 4242 ;;
  *pkill*|*\[k\]bd*) [ "${cmd#pgrep}" != "$cmd" ] && { [ -f "$S/watcher-started" ] && echo 4242; exit 0; }; rm -f "$S/watcher-started"; touch "$S/pkill-ran" ;;
esac
exit 0
EOF
chmod +x "$BIN/ip" "$BIN/adb"

GB=com.example.gboard/.Latin
SK=com.example.simple/.Latin
printf '%s\n%s\n' "$GB" "$SK" > "$STUB/imes"
echo "$GB" > "$STUB/ime"
printf '%s\n' "$GB" > "$STUB/enabled-now"   # the chosen keyboard is installed but NOT enabled yet

export PATH="$BIN:$PATH" STUB HOME="$SCRATCH/home" XDG_STATE_HOME="$SCRATCH/state" XDG_CONFIG_HOME="$SCRATCH/config"
mkdir -p "$HOME"
export PHONE_ADB_PORTS="40001 40002"
export STUB_OK_PORT=40002

# --- P.1: connect tries each candidate port until one authenticates ---
out="$(bash "$PA" connect 2>&1)"
assert_contains "connect reports the working port" "$out" "connected: 10.9.9.1:40002"
assert_contains "the first (wrong) port was tried too" "$(cat "$STUB/connect-log")" "10.9.9.1:40001"
assert_eq "the working port is remembered" "$(cat "$XDG_STATE_HOME/phone-adb/port")" "40002"

# --- P.2: connect fails clearly when nothing authenticates ---
rm -f "$STUB/connected"
out="$(STUB_OK_PORT=99 bash "$PA" connect 2>&1)"; rc=$?
assert_eq "connect fails when no port authenticates" "$rc" "1"
assert_contains "failure says what to check" "$out" "Wireless debugging"

# --- P.3: kbd-follow refuses without a chosen keyboard (opt-in, nothing assumed) ---
out="$(bash "$PA" kbd-follow 2>&1)"; rc=$?
assert_eq "kbd-follow with no keyboard configured fails" "$rc" "1"
assert_contains "it tells you to choose one" "$out" "no keyboard chosen"
assert_file_absent "no watcher was started" "$STUB/watcher-started"

# --- P.4: kbd-follow arms the phone-side watcher with the right keyboards ---
out="$(bash "$PA" kbd-follow "$SK" 2>&1)"
assert_contains "it reports the watcher" "$out" "watcher running on the phone"
assert_file_exists "the watcher was started on the phone" "$STUB/watcher-started"
assert_contains "watcher uses the chosen keyboard in the Terminal" "$(cat "$STUB/watch.sh")" "want=$SK;"
assert_contains "watcher returns the user's own keyboard otherwise" "$(cat "$STUB/watch.sh")" "else want=$GB;"
assert_contains "watcher keys on the Terminal package" "$(cat "$STUB/watch.sh")" "com.android.virtualization.terminal"
assert_contains "an installed-but-disabled keyboard is enabled first" "$(cat "$STUB/enable-log")" "enable $SK"
assert_not_contains "nothing is disabled" "$(cat "$STUB/enable-log" 2>/dev/null; echo)" "disable"

# --- P.5: the saved config is used when no keyboard is passed ---
mkdir -p "$XDG_CONFIG_HOME/phone-adb"; echo "$SK" > "$XDG_CONFIG_HOME/phone-adb/keyboard"
echo "$GB" > "$STUB/ime"
out="$(bash "$PA" kbd-follow 2>&1)"
assert_contains "config keyboard is used" "$out" "$SK in the Terminal"

# --- P.6: a stale run (terminal keyboard already current) reuses the saved own keyboard ---
echo "$SK" > "$STUB/ime"
out="$(bash "$PA" kbd-follow 2>&1)"
assert_contains "own keyboard is remembered across a stale run" "$out" "$GB elsewhere"

# --- P.6b: stale run with no saved own keyboard: one other typing keyboard is yours; ambiguity is refused ---
rm -f "$XDG_STATE_HOME/phone-adb/home-ime"; echo "$SK" > "$STUB/ime"
out="$(bash "$PA" kbd-follow 2>&1)"
assert_contains "single other enabled keyboard is taken as yours" "$out" "$GB elsewhere"
rm -f "$XDG_STATE_HOME/phone-adb/home-ime"; echo "$SK" > "$STUB/ime"
printf '%s\n%s\n%s\n' "$GB" "$SK" "com.example.other/.Latin" > "$SCRATCH/enabled3"
out="$(STUB_ENABLED="$SCRATCH/enabled3" bash "$PA" kbd-follow 2>&1)"; rc=$?
assert_eq "two candidate own keyboards: refuses to guess" "$rc" "1"
assert_contains "and says why" "$out" "cannot tell which keyboard is yours"

# --- P.7: kbd-release stops the watcher and restores the user's keyboard ---
echo "$GB" > "$STUB/ime"; bash "$PA" kbd-follow >/dev/null 2>&1
echo "$SK" > "$STUB/ime"
bash "$PA" kbd-release >/dev/null 2>&1
assert_file_exists "release killed the watcher" "$STUB/pkill-ran"
assert_eq "release put the user's keyboard back" "$(cat "$STUB/ime")" "$GB"

# --- P.8: pair passes through and checks its arguments ---
bash "$PA" pair 192.0.2.7:4444 123456 >/dev/null 2>&1
assert_contains "pair calls adb pair with the address and code" "$(cat "$STUB/pair-log")" "192.0.2.7:4444 123456"
assert_failure "pair with missing code is refused" bash "$PA" pair 192.0.2.7:4444

# --- P.9: installer helpers ---
source "$INSTALLER"
set +e
list="$(printf '%s\n%s\n' "$GB" "$SK")"
assert_eq "pick by exact id" "$(pick_keyboard "$SK" "$list")" "$SK"
assert_eq "pick by number" "$(pick_keyboard 1 "$list")" "$GB"
assert_failure "an unknown keyboard is refused" pick_keyboard "nope/.X" "$list"
assert_failure "an out-of-range number is refused" pick_keyboard 9 "$list"
unit="$(render_unit)"
assert_contains "service re-arms the watcher" "$unit" "ExecStart=/usr/local/bin/phone-adb kbd-follow"
assert_contains "service retries while the phone is unreachable" "$unit" "Restart=on-failure"
assert_failure "installer refuses to run without --user and without sudo user" bash -c "SUDO_USER= bash '$INSTALLER'"
assert_failure "a keyboard that is not installed is refused" bash "$PA" kbd-follow "com.example.missing/.X"
assert_contains "installer asks for the adb package, not android-tools-adb" "$(cat "$INSTALLER")" "pkg_ensure adb python3"
assert_contains "service has a start limit" "$unit" "StartLimitBurst="
assert_not_contains "service does not use the meaningless network-online ordering" "$unit" "network-online"
assert_failure "installer refuses an unknown option" bash "$INSTALLER" --bogus

summarize_and_exit
