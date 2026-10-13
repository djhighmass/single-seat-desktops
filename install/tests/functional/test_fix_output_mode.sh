#!/bin/bash
# FUNCTIONAL TEST (no sudo). Runs the real fix-output-mode.sh with a stub
# wlr-randr first in PATH that prints a given mode list and records the
# mode it is asked to set.
#
# No -e: assertions record failures and keep going.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/testlib.sh

echo "test_fix_output_mode:"

SCRIPT="$(cd ../.. && pwd)/files/fix-output-mode.sh"
BIN="$SCRATCH/bin"
mkdir -p "$BIN"
cat > "$BIN/wlr-randr" <<EOF
#!/bin/bash
if [ \$# -eq 0 ]; then cat "$SCRATCH/modes"; else echo "\$*" > "$SCRATCH/set"; fi
EOF
chmod +x "$BIN/wlr-randr"

# chosen_mode <wlr-randr mode lines...> -- prints the mode the script sets
chosen_mode() {
  { echo 'Virtual-1 "Google Inc. CrosvmDisplay 0x00000001 (Virtual-1)"'
    echo '  Modes:'
    printf '    %s\n' "$@"
  } > "$SCRATCH/modes"
  rm -f "$SCRATCH/set"
  PATH="$BIN:$PATH" bash "$SCRIPT"
  sed -n 's/.*--mode \([^ ]*\).*/\1/p' "$SCRATCH/set" 2>/dev/null
}

assert_eq "a portrait window gets its portrait mode, not the larger landscape one" \
  "$(chosen_mode '1008x1865 px, 60.012001 Hz (preferred, current)' '1920x1200 px, 59.884998 Hz' '1680x1050 px, 59.953999 Hz')" \
  "1008x1865"
assert_eq "a landscape window gets the largest landscape mode" \
  "$(chosen_mode '1865x1008 px, 60.012001 Hz (preferred)' '1920x1200 px, 59.884998 Hz (current)' '1008x1865 px, 60.001999 Hz')" \
  "1920x1200"
assert_eq "with no preferred mode, the largest mode overall" \
  "$(chosen_mode '1008x1865 px, 60.012001 Hz' '1920x1200 px, 59.884998 Hz (current)')" \
  "1920x1200"

summarize_and_exit
