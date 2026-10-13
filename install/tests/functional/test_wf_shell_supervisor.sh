#!/bin/bash
# FUNCTIONAL TEST (no sudo). Runs the real wf-shell-supervisor.sh with
# stub clients, fix-output and env publisher, and a `sleep` standing in
# for the compositor. Covers restart, crash-loop give-up, output mode
# re-applied after restart, and stopping once the compositor is gone.
#
# No -e: assertions record failures and keep going; summarize_and_exit
# decides the exit status.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/testlib.sh

echo "test_wf_shell_supervisor:"

SCRIPT="$(cd ../.. && pwd)/files/wf-shell-supervisor.sh"
BIN="$SCRATCH/bin"
mkdir -p "$BIN"

# stub <name> <seconds to stay up> -- records each start in $SCRATCH/<name>.starts
stub() {
  cat > "$BIN/$1" <<EOF
#!/bin/bash
echo start >> "$SCRATCH/$1.starts"
exec sleep $2
EOF
  chmod +x "$BIN/$1"
}
cat > "$BIN/fix-output" <<EOF
#!/bin/bash
echo fix >> "$SCRATCH/fix.runs"
EOF
cat > "$BIN/publish" <<EOF
#!/bin/bash
for v in "\$@"; do echo "\$v=\${!v}"; done >> "$SCRATCH/published"
EOF
chmod +x "$BIN/fix-output" "$BIN/publish"

count() { [ -f "$1" ] && wc -l < "$1" | tr -d ' ' || echo 0; }

# run_supervisor <compositor pid> -- starts it in the background, returns its pid in $sup
run_supervisor() {
  env -u XDG_CURRENT_DESKTOP -u XDG_SESSION_TYPE LOG="$SCRATCH/supervisor.log" PANEL_CMD="$BIN/panel" BACKGROUND_CMD="$BIN/background" \
    FIX_OUTPUT_CMD="$BIN/fix-output" ENV_PUBLISH_CMD="$BIN/publish" PORTAL_RESET_CMD=true \
    COMPOSITOR_PID="$1" RESTART_DELAY=0.1 FAST_EXIT_SECS=5 MAX_FAST_EXITS=3 \
    WAYLAND_DISPLAY=wayland-test DISPLAY= \
    bash "$SCRIPT" &
  sup=$!
}

# --- a client that keeps dying is restarted, then given up on ---------

stub panel 0.2         # dies right away, like a reconnect-killed panel
stub background 30     # stays up
sleep 30 & compositor=$!
run_supervisor "$compositor"

for _ in $(seq 1 50); do grep -q 'giving up on it' "$SCRATCH/supervisor.log" 2>/dev/null && break; sleep 0.1; done
assert_eq "a panel that exits is started again (3 starts before the crash-loop limit)" \
  "$(count "$SCRATCH/panel.starts")" "3"
assert_contains "a panel that keeps exiting right after starting is given up on, not spun forever" \
  "$(cat "$SCRATCH/supervisor.log")" "wf-panel exited 3 times"
assert_eq "the output mode is re-applied after each panel restart (not after the last, abandoned one)" \
  "$(count "$SCRATCH/fix.runs")" "2"
assert_eq "the background is left running while the panel is being restarted" \
  "$(count "$SCRATCH/background.starts")" "1"
assert_eq "the session's display variables are published, and only the ones actually set" \
  "$(cat "$SCRATCH/published" 2>/dev/null)" "WAYLAND_DISPLAY=wayland-test"

kill "$sup" 2>/dev/null; wait "$sup" 2>/dev/null
kill "$compositor" 2>/dev/null; wait "$compositor" 2>/dev/null

# --- nothing restarts once the compositor is gone ---------------------

rm -f "$SCRATCH"/*.starts "$SCRATCH/fix.runs"
stub panel 1
stub background 1
sleep 30 & compositor=$!
run_supervisor "$compositor"
sleep 0.5
kill "$compositor"; wait "$compositor" 2>/dev/null

for _ in $(seq 1 50); do kill -0 "$sup" 2>/dev/null || break; sleep 0.1; done
assert_failure "the supervisor exits by itself once the compositor is gone" -- kill -0 "$sup"
assert_eq "the panel isn't restarted after the compositor is gone" "$(count "$SCRATCH/panel.starts")" "1"
assert_eq "the background isn't restarted after the compositor is gone" "$(count "$SCRATCH/background.starts")" "1"
kill "$sup" 2>/dev/null

# --- the compositor is found when it isn't an ancestor -----------------

# Like wayfire's autostart: the compositor is not the supervisor's parent.
rm -f "$SCRATCH"/*.starts
stub panel 1
stub background 1
cp "$(command -v sleep)" "$BIN/fakecomp"
"$BIN/fakecomp" 30 & compositor=$!
env -u XDG_CURRENT_DESKTOP -u XDG_SESSION_TYPE LOG="$SCRATCH/lookup.log" PANEL_CMD="$BIN/panel" BACKGROUND_CMD="$BIN/background" \
  FIX_OUTPUT_CMD=true ENV_PUBLISH_CMD=true PORTAL_RESET_CMD=true COMPOSITOR_NAME=fakecomp \
  RESTART_DELAY=0.1 WAYLAND_DISPLAY=wayland-test bash "$SCRIPT" &
sup=$!
for _ in $(seq 1 30); do grep -q 'session compositor' "$SCRATCH/lookup.log" 2>/dev/null && break; sleep 0.1; done
assert_contains "the compositor is found by name, not by walking up the parents" \
  "$(cat "$SCRATCH/lookup.log")" "session compositor: pid $compositor (fakecomp)"
kill "$compositor"; wait "$compositor" 2>/dev/null
for _ in $(seq 1 50); do kill -0 "$sup" 2>/dev/null || break; sleep 0.1; done
assert_failure "and the supervisor stops once that compositor is gone" -- kill -0 "$sup"
kill "$sup" 2>/dev/null; pkill -f "$BIN/" 2>/dev/null

summarize_and_exit
