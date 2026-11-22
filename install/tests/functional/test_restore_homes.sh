#!/bin/bash
# FUNCTIONAL TEST -- runs 05-restore-homes.sh's real copy logic against scratch
# directories (no sudo, nothing outside $SCRATCH is touched), plus its real CLI
# in --dry-run mode, which never writes.
#
# No -e: every numbered scenario ends in its own assertion and must still run
# when an earlier one fails; failures are tallied by summarize_and_exit.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/testlib.sh

echo "test_restore_homes:"

SCRIPT="$(cd ../.. && pwd)/05-restore-homes.sh"
# An account name no real system has, so the CLI cases below see "no such account".
FIXTURE="zz-restore-test-$$"
BK="$SCRATCH/backup"
DST="$SCRATCH/dst"

mk_backup_home() {
  local h="$BK/home/$FIXTURE"
  mkdir -p "$h/.ssh" "$h/.config/gh" "$h/docs"
  echo "PRIVATE-KEY"  > "$h/.ssh/id_ed25519"
  echo "GHTOKEN"      > "$h/.config/gh/hosts.yml"
  echo "notes v-old"  > "$h/docs/notes"
  echo "keepme"       > "$h/.bashrc"
}

# shellcheck source=../../05-restore-homes.sh
source "$SCRIPT"
set +e  # the sourced script turned on -e; this file tallies failures itself

# --- R.1: a plain restore copies everything, dotfiles and keys included ---
mk_backup_home; mkdir -p "$DST"
restore_one_home "$BK/home/$FIXTURE" "$DST" >/dev/null 2>&1
assert_file_exists "ordinary file restored" "$DST/docs/notes"
assert_file_exists "dotfile restored" "$DST/.bashrc"
assert_file_exists "ssh key restored" "$DST/.ssh/id_ed25519"
assert_file_exists "nested config restored" "$DST/.config/gh/hosts.yml"

# --- R.2: extra arguments go to rsync, so a caller can leave things out ---
rm -rf "$DST"; mkdir -p "$DST"
restore_one_home "$BK/home/$FIXTURE" "$DST" --exclude=/.ssh >/dev/null 2>&1
assert_file_absent "an excluded path is not restored" "$DST/.ssh/id_ed25519"
assert_file_exists "everything else still is" "$DST/docs/notes"

# --- R.3: an existing differing file is kept, never silently overwritten ---
rm -rf "$DST"; mkdir -p "$DST/docs"
echo "notes v-new-local" > "$DST/docs/notes"
restore_one_home "$BK/home/$FIXTURE" "$DST" >/dev/null 2>&1
assert_eq "restored content wins at the original path" "$(cat "$DST/docs/notes")" "notes v-old"
kept="$(cat "$DST"/docs/notes.pre-restore-* 2>/dev/null)"
assert_eq "the previous local file is kept as .pre-restore-<time>" "$kept" "notes v-new-local"

# --- R.4: dry run changes nothing ---
rm -rf "$DST"; mkdir -p "$DST"
restore_one_home "$BK/home/$FIXTURE" "$DST" -n -i >/dev/null 2>&1
assert_eq "dry run copied nothing" "$(ls -A "$DST" | wc -l)" "0"

# --- R.5: the backup is only read ---
assert_eq "backup untouched (secret still there)" "$(cat "$BK/home/$FIXTURE/.ssh/id_ed25519")" "PRIVATE-KEY"
assert_eq "backup untouched (no .pre-restore files in it)" "$(find "$BK" -name '*.pre-restore-*' | wc -l)" "0"

# --- R.5b: a copy that can't finish is reported as a failure ---
if [ "$(id -u)" -ne 0 ]; then
  rm -rf "$DST"; mkdir -p "$DST"
  chmod 000 "$BK/home/$FIXTURE/docs/notes"
  restore_one_home "$BK/home/$FIXTURE" "$DST" >/dev/null 2>&1; rc=$?
  chmod 644 "$BK/home/$FIXTURE/docs/notes"
  assert_eq "an unreadable file makes the restore report failure" "$([ "$rc" -ne 0 ] && echo failed)" "failed"
fi
# --- R.6: the CLI refuses bad input and a missing backup ---
assert_failure "missing backup directory is refused" bash "$SCRIPT" --dry-run --backup="$SCRATCH/nope"
assert_failure "unknown option is refused" bash "$SCRIPT" --bogus
assert_failure "a user not in the backup is refused" bash "$SCRIPT" --dry-run --backup="$BK" --users=nobody-here
# A typo anywhere in --users is caught before any home is touched.
out="$(bash "$SCRIPT" --dry-run --backup="$BK" --users="$FIXTURE,nobody-here" 2>&1)"; rc=$?
assert_eq "a typo in --users is refused" "$([ "$rc" -ne 0 ] && echo refused)" "refused"
assert_not_contains "...before the first home is processed" "$out" " -> "
out="$(bash "$SCRIPT" --dry-run --backup="$BK" --users="$FIXTURE" 2>&1)"; rc=$?
assert_contains "an account missing on this system is reported, not created" "$out" "skipped, not ready: $FIXTURE"
assert_eq "a skipped account makes the run exit non-zero" "$([ "$rc" -ne 0 ] && echo failed)" "failed"
assert_contains "the run still says nothing changed" "$out" "nothing changed"

# An account that exists but has no home directory is skipped the same way.
# "nobody" is a standard account whose home (/nonexistent) does not exist.
nohome="$(getent passwd nobody | cut -d: -f6)"
if [ -n "$nohome" ] && [ ! -e "$nohome" ]; then
  mkdir -p "$BK/home/nobody"; echo x > "$BK/home/nobody/f"
  out="$(bash "$SCRIPT" --dry-run --backup="$BK" --users=nobody 2>&1)"; rc=$?
  assert_contains "an account with no home directory is reported" "$out" "no home directory at $nohome"
  assert_eq "...and makes the run exit non-zero" "$([ "$rc" -ne 0 ] && echo failed)" "failed"
  assert_file_absent "...and nothing was created for it" "$nohome"
fi

summarize_and_exit
