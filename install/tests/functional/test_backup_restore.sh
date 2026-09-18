#!/bin/bash
# FUNCTIONAL TEST -- runs the real backup-user.sh and restore-user.sh
# against scratch $HOME directories. No sudo needed: neither script ever
# touches anything outside $HOME.
#
# No -e: this file runs six numbered scenarios (B.1-B.6) back to back,
# each ending in its own assert_eq/assert_contains/assert_file_*
# call -- those capture pass/fail themselves and are meant to let every
# later scenario still run (and summarize_and_exit still print a full
# tally) even if an earlier assertion in the sequence didn't hold.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/testlib.sh

echo "test_backup_restore:"

FILES="$(cd ../.. && pwd)/files"
SRC_HOME="$SCRATCH/src-home"
DST_HOME="$SCRATCH/dst-home"
ARCHIVE="$SCRATCH/backup.tar.gz"

setup_customized_home() {
  local home="$1"
  mkdir -p "$home/.config"
  cp "$FILES/wayfire.ini.tmpl" "$home/.config/wayfire.ini"
  echo "[panel]" > "$home/.config/wf-shell.ini"
  echo "Australia/Brisbane" > "$home/.config/timezone"
  cat > "$home/.config/wayfire-customize.conf" <<'EOF'
WANT_FOOT=y
FOOT_SIZE=quarter
WANT_WEATHER=y
WEATHER_LOC='Testville'
WEATHER_LAT='10.0'
WEATHER_LON='20.0'
WANT_CLOCK=n
CLOCK_SPEC=''
WANT_SYNAPTIC=y
EOF
  # A tiny fake PNG -- content doesn't matter, only that it round-trips.
  printf '\x89PNG\r\n\x1a\nfaketestimage' > "$home/.config/background.png"
}

# --- B.1: backup contains only source-of-truth files ---
setup_customized_home "$SRC_HOME"
HOME="$SRC_HOME" bash "$FILES/backup-user.sh" "$ARCHIVE" >/dev/null
assert_file_exists "the archive was created" "$ARCHIVE"

manifest="$(tar -tzf "$ARCHIVE" | sort)"
assert_eq "the archive contains exactly the source-of-truth files, nothing generated" \
  "$manifest" "$(printf './\n./background.png\n./timezone\n./wayfire-customize.conf\n')"

# --- B.2 / B.3: restore onto a fresh, differently-located home ---
export SUPPORT="$SCRATCH/support"
mkdir -p "$SUPPORT"
cp "$FILES/owf-update-weather.sh.tmpl" "$FILES/panel-weather.sh" \
   "$FILES/owf-weather.service" "$FILES/owf-weather.timer" "$SUPPORT/"

mkdir -p "$DST_HOME/.config"
cp "$FILES/wayfire.ini.tmpl" "$DST_HOME/.config/wayfire.ini"
echo "[panel]" > "$DST_HOME/.config/wf-shell.ini"

PATH="$SCRATCH/bin:$PATH"
mkdir -p "$SCRATCH/bin"
cat > "$SCRATCH/bin/wayfire-customize.sh" <<EOF
#!/bin/bash
exec bash "$FILES/wayfire-customize.sh" "\$@"
EOF
cat > "$SCRATCH/bin/set-background.sh" <<EOF
#!/bin/bash
exec bash "$FILES/set-background.sh" "\$@"
EOF
chmod +x "$SCRATCH/bin/wayfire-customize.sh" "$SCRATCH/bin/set-background.sh"

# restore-user.sh calls the real installed paths directly; point those
# at our scratch stand-ins for this test the same way $PATH already
# would in a real install.
sed "s|/usr/local/bin/wayfire-customize.sh|$SCRATCH/bin/wayfire-customize.sh|; s|/usr/local/bin/set-background.sh|$SCRATCH/bin/set-background.sh|" \
  "$FILES/restore-user.sh" > "$SCRATCH/restore-user.sh"

HOME="$DST_HOME" bash "$SCRATCH/restore-user.sh" "$ARCHIVE" >/dev/null 2>/dev/null

assert_eq "the restored timezone matches the backup" \
  "$(cat "$DST_HOME/.config/timezone")" "Australia/Brisbane"
assert_eq "the restored conf file matches the backup" \
  "$(cat "$DST_HOME/.config/wayfire-customize.conf")" "$(cat "$SRC_HOME/.config/wayfire-customize.conf")"
assert_contains "restoring re-applied the customization (foot autostart present)" \
  "$(cat "$DST_HOME/.config/wayfire.ini")" "term1 = "
assert_contains "restoring re-applied the customization (synaptic launcher present)" \
  "$(cat "$DST_HOME/.config/wf-shell.ini")" "launcher_cmd_synaptic"
assert_eq "restoring re-applied the background image" \
  "$(cat "$DST_HOME/.config/background.png")" "$(cat "$SRC_HOME/.config/background.png")"

# --- B.4: round-trip idempotency ---
ARCHIVE2="$SCRATCH/backup2.tar.gz"
HOME="$DST_HOME" bash "$FILES/backup-user.sh" "$ARCHIVE2" >/dev/null
assert_eq "backing up the restored account matches the original backup's conf" \
  "$(tar -xzOf "$ARCHIVE2" ./wayfire-customize.conf)" "$(tar -xzOf "$ARCHIVE" ./wayfire-customize.conf)"

# --- B.5: partial backup (background only) degrades gracefully ---
PARTIAL_HOME="$SCRATCH/partial-home"
mkdir -p "$PARTIAL_HOME/.config"
cp "$FILES/wayfire.ini.tmpl" "$PARTIAL_HOME/.config/wayfire.ini"
echo "[panel]" > "$PARTIAL_HOME/.config/wf-shell.ini"
printf 'onlyabackground' > "$PARTIAL_HOME/.config/background.png"

PARTIAL_ARCHIVE="$SCRATCH/partial.tar.gz"
HOME="$PARTIAL_HOME" bash "$FILES/backup-user.sh" "$PARTIAL_ARCHIVE" >/dev/null

RESTORE_TARGET="$SCRATCH/restore-target-home"
mkdir -p "$RESTORE_TARGET/.config"
cp "$FILES/wayfire.ini.tmpl" "$RESTORE_TARGET/.config/wayfire.ini"
echo "[panel]" > "$RESTORE_TARGET/.config/wf-shell.ini"

assert_success "restoring a background-only backup doesn't crash" -- \
  env HOME="$RESTORE_TARGET" bash "$SCRATCH/restore-user.sh" "$PARTIAL_ARCHIVE"
assert_file_absent "a background-only restore doesn't invent a conf file" \
  "$RESTORE_TARGET/.config/wayfire-customize.conf"
assert_eq "a background-only restore still applies the image" \
  "$(cat "$RESTORE_TARGET/.config/background.png")" "onlyabackground"

# --- B.6: nothing this test produced is anywhere near the repo ---
REPO_ROOT="$(cd ../../.. && pwd)"
assert_not_contains "no backup archive landed inside the repo" \
  "$(find "$REPO_ROOT" -name '*.tar.gz' 2>/dev/null)" "tar.gz"

summarize_and_exit
