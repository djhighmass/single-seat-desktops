#!/bin/bash
# FUNCTIONAL TEST (needs sudo; creates and deletes a disposable account).
# Runs the real apps/install.sh against a scratch apps directory holding two
# fake apps: picks only what's asked, runs defaults.sh as the chosen user
# (so its files are theirs), honours --no-defaults, refuses unknown apps
# and users, and skips an app's defaults when its install fails.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/testlib.sh

APPS="$(cd ../.. && pwd)"

if [ "$(id -u)" -ne 0 ] && ! sudo -n true 2>/dev/null; then
  echo "test_chooser: skipped (needs passwordless sudo)"
  exit 0
fi

echo "test_chooser:"

TESTUSER="appstest-$$"
cleanup() { sudo -n userdel -r "$TESTUSER" >/dev/null 2>&1; }
trap 'cleanup; sudo -n rm -rf "$SCRATCH"' EXIT
sudo -n useradd -m -U "$TESTUSER"
H="$(getent passwd "$TESTUSER" | cut -d: -f6)"

FAKE="$SCRATCH/apps"
mkdir -p "$FAKE/lib" "$FAKE/alpha" "$FAKE/beta" "$FAKE/broken"
cp "$APPS/lib/common.sh" "$FAKE/lib/"
cp "$APPS/install.sh" "$FAKE/"
OUT="$SCRATCH/out"; mkdir -p "$OUT"; chmod 777 "$OUT" "$SCRATCH"
for a in alpha beta; do
  printf '# DESCRIPTION: the %s app\necho installed >> %s/%s\n' "$a" "$OUT" "$a" > "$FAKE/$a/install.sh"
  printf 'echo "$(id -un) $HOME" >> %s/%s-defaults; touch "$HOME/%s-setting"\n' "$OUT" "$a" "$a" > "$FAKE/$a/defaults.sh"
done
printf '# DESCRIPTION: fails\nexit 1\n' > "$FAKE/broken/install.sh"
printf 'touch %s/broken-defaults\n' "$OUT" > "$FAKE/broken/defaults.sh"
chmod -R a+rX "$SCRATCH"
run() { sudo -n env APPS_DIR="$FAKE" bash "$FAKE/install.sh" "$@" </dev/null 2>&1; }

# --- C.1: --list shows each app with its description ---
out="$(bash "$FAKE/install.sh" --list)"
assert_contains "list shows alpha with its description" "$out" "the alpha app"
assert_contains "list shows beta" "$out" "beta"

# --- C.2: only the named app is installed; defaults run as the user ---
run --apps=alpha --defaults --users="$TESTUSER" >/dev/null
assert_file_exists "alpha installed" "$OUT/alpha"
assert_file_absent "beta not installed" "$OUT/beta"
assert_eq "defaults ran as the user, with their HOME" "$(cat "$OUT/alpha-defaults")" "$TESTUSER $H"
assert_eq "the setting file is the user's own" "$(sudo -n stat -c %U "$H/alpha-setting")" "$TESTUSER"

# --- C.3: --no-defaults installs but applies no settings ---
run --apps=beta --no-defaults --users="$TESTUSER" >/dev/null
assert_file_exists "beta installed" "$OUT/beta"
assert_file_absent "no defaults applied with --no-defaults" "$OUT/beta-defaults"

# --- C.4: interactive: answering nothing installs nothing ---
out="$(run)"
assert_contains "no answers means nothing chosen" "$out" "nothing chosen"

# --- C.5: bad input is refused before anything is installed ---
rm -f "$OUT"/*
assert_failure "an unknown app is refused" run --apps=alpha,nope
assert_failure "an unknown user is refused" run --apps=alpha --defaults --users=no-such-user-here
assert_file_absent "nothing installed after a refusal" "$OUT/alpha"
assert_failure "an unknown option is refused" run --bogus

# --- C.6: a failed install skips that app's defaults and reports it ---
out="$(run --apps=broken,alpha --defaults --users="$TESTUSER")"; rc=$?
assert_file_absent "broken app's defaults skipped" "$OUT/broken-defaults"
assert_file_exists "the next app still installs" "$OUT/alpha"
assert_contains "the failure is named" "$out" "failed: broken"
assert_eq "exit status reports the failure" "$rc" "1"

# --- C.7: not root ---
assert_failure "refuses to run without root" env APPS_DIR="$FAKE" bash "$FAKE/install.sh" --apps=alpha

summarize_and_exit
