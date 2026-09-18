#!/bin/bash
# FUNCTIONAL TEST -- runs the real wayfire-customize.sh binary via its
# real --apply CLI (a genuine non-interactive entry point, not a test
# hook), then actually executes the resulting term1 line through a real
# shell with a stub `foot` in PATH, and checks what the stub actually
# received and where its output actually landed. This exercises the
# generated command line's quoting/escaping as real behavior, not a
# string diff against expected text -- a reformatted but equivalent
# quoting scheme would still pass this test.
#
# No -e: assert_* below captures each comparison's own result and
# keeps going, so the later checks on the stub foot's recorded argv
# and its stdout/stderr logs still run -- and summarize_and_exit still
# reports a full tally -- even if an earlier one (e.g. the term1 line
# not being found) doesn't hold.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/testlib.sh

echo "test_customize_foot:"

export HOME="$SCRATCH"
mkdir -p "$HOME/.config"
cp ../../files/wayfire.ini.tmpl "$HOME/.config/wayfire.ini"
echo "[panel]" > "$HOME/.config/wf-shell.ini"

cat > "$HOME/.config/wayfire-customize.conf" <<'EOF'
WANT_FOOT=y
FOOT_SIZE=quarter
WANT_WEATHER=n
WEATHER_LOC=''
WEATHER_LAT=''
WEATHER_LON=''
WANT_CLOCK=n
CLOCK_SPEC=''
WANT_SYNAPTIC=n
EOF

# Fake sysfs so resolve_foot_args' "quarter" resolves deterministically
# instead of depending on whatever's actually connected on this machine.
mkdir -p "$SCRATCH/drm/card0-Fake"
echo "connected" > "$SCRATCH/drm/card0-Fake/status"
echo "1920x864" > "$SCRATCH/drm/card0-Fake/modes"
export DRM_SYS_PATH="$SCRATCH/drm"

bash ../../files/wayfire-customize.sh --apply >/dev/null 2>&1
assert_file_exists "wayfire.ini still exists after apply" "$HOME/.config/wayfire.ini"

term1="$(grep '^term1 = ' "$HOME/.config/wayfire.ini")"
assert_contains "term1 line was inserted into [autostart]" \
  "$(cat "$HOME/.config/wayfire.ini")" "term1 = "

# Stub foot: record its argv instead of launching a terminal.
mkdir -p "$SCRATCH/bin"
cat > "$SCRATCH/bin/foot" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$HOME/.cache/foot-argv.log"
echo "stub foot stdout"
echo "stub foot stderr" >&2
EOF
chmod +x "$SCRATCH/bin/foot"

# Run the actual generated command line through a real shell, exactly as
# wayfire's [autostart] would -- minus the 5s startup delay, which is
# irrelevant to what's under test here (the quoting/redirection).
cmd="${term1#term1 = }"
cmd="${cmd/sleep 5; /}"
PATH="$SCRATCH/bin:$PATH" sh -c "$cmd"

assert_file_exists "stub foot recorded its argv" "$HOME/.cache/foot-argv.log"
assert_eq "foot was invoked with the size computed from the fake screen" \
  "$(cat "$HOME/.cache/foot-argv.log")" "--window-size-pixels=960x432"
assert_eq "foot's stdout landed in the expected per-user log" \
  "$(cat "$HOME/.cache/foot-stdout.log")" "stub foot stdout"
assert_eq "foot's stderr landed in the expected per-user log" \
  "$(cat "$HOME/.cache/foot-stderr.log")" "stub foot stderr"

summarize_and_exit
