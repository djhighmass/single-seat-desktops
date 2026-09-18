#!/bin/bash
# FUNCTIONAL TEST (needs sudo; requires WF_TESTS_ALLOW_SHARED_BOX=1).
#
# The core installer's account picker lists *every* real account on the
# box (uid >=1000, valid shell, not the host) and selects among them by
# number -- on a machine that also hosts real personal accounts, getting
# that number wrong risks re-provisioning someone's actual desktop. This
# test computes the index carefully and only ever picks its own disposable
# throwaway account, never 'all', but the risk of a bug in this test
# itself touching a real account is real enough that it stays off by
# default. Run it in a disposable VM/container, or explicitly opt in:
#
#   WF_TESTS_ALLOW_SHARED_BOX=1 ./test_core_installer.sh
#
# No -e: assert_failure "a second run creates no backup file" below
# deliberately runs an `ls` that is *expected* to fail (no bak-* file
# should exist yet) and checks that outcome itself -- and every
# assert_*/fail() call here keeps going rather than aborting the file,
# so this still runs all three installer passes and the alias-file
# regression check, then reports a full tally via summarize_and_exit,
# even if one check along the way comes out unexpectedly.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/testlib.sh

if [ "${WF_TESTS_ALLOW_SHARED_BOX:-}" != 1 ]; then
  echo "test_core_installer: skipped (set WF_TESTS_ALLOW_SHARED_BOX=1 to run --"
  echo "  see this file's header for why it's off by default on a shared box)"
  exit 0
fi
if [ "$(id -u)" -ne 0 ] && ! sudo -n true 2>/dev/null; then
  echo "test_core_installer: skipped (needs passwordless sudo)"
  exit 0
fi

echo "test_core_installer:"

INSTALL_DIR="$(cd ../.. && pwd)"
TESTUSER="wftest-core-$$"
# Matches the real installer's own default -- logname/$SUDO_USER aren't
# reliable here (e.g. no utmp record in a ttyd-based session), and this
# needs to be an account that actually exists for the awk exclusion and
# the real prompt's default to agree.
HOST_USER="${WF_TEST_HOST_USER:-droid}"
id "$HOST_USER" &>/dev/null || { echo "  skip - host account '$HOST_USER' doesn't exist (set WF_TEST_HOST_USER)"; exit 0; }
HOST_HOME="$(getent passwd "$HOST_USER" | cut -d: -f6)"
ALIASES_FILE="$HOST_HOME/.bash_aliases"
cleanup() {
  # onboard_user() calls loginctl enable-linger, which keeps a systemd
  # --user instance running independent of any login session -- userdel
  # refuses to remove an account still "in use" by it, so it has to be
  # torn down first, not just killed and retried.
  sudo -n loginctl disable-linger "$TESTUSER" >/dev/null 2>&1
  sudo -n loginctl terminate-user "$TESTUSER" >/dev/null 2>&1
  sleep 1
  sudo -n pkill -9 -u "$TESTUSER" >/dev/null 2>&1
  sleep 1
  sudo -n userdel -r "$TESTUSER" >/dev/null 2>&1
  sudo -n rm -f "/etc/sudoers.d/90-$TESTUSER"
  # The installer writes a real alias into the HOST account's own
  # .bash_aliases as part of onboarding -- that's real, shared, persistent
  # state on whatever machine this runs on, not scoped to the throwaway
  # account, so it needs cleaning up here too rather than just deleting
  # the account.
  sudo -n bash -c "grep -v \"^alias ${TESTUSER}-wayfire=\" '$ALIASES_FILE' > '${ALIASES_FILE}.cleanup-tmp' 2>/dev/null; mv '${ALIASES_FILE}.cleanup-tmp' '$ALIASES_FILE'" 2>/dev/null
}
trap cleanup EXIT

sudo -n useradd -m -s /bin/bash "$TESTUSER"

# Same query 10-install-wayfire-desktops.sh uses to build its candidate
# list, so this picks TESTUSER by the same number the real prompt would
# show it at -- never 'all', which would also re-provision every real
# account on the box.
mapfile -t candidates < <(awk -F: -v host="$HOST_USER" \
  '$3>=1000 && $3<60000 && $1!=host && $7 !~ /nologin|false/ {print $1}' /etc/passwd)
index=-1
for i in "${!candidates[@]}"; do
  [ "${candidates[$i]}" = "$TESTUSER" ] && index=$((i + 1))
done
if [ "$index" -lt 0 ]; then
  fail "could not find $TESTUSER in the installer's own candidate list"
  summarize_and_exit
  exit $?
fi

run_installer() {
  printf '%s\n%s\n%s\n' "$HOST_USER" "$index" "Etc/UTC" | \
    sudo -n bash "$INSTALL_DIR/10-install-wayfire-desktops.sh" "$@" >/dev/null 2>&1
}

run_installer
assert_success "wayfire.ini was generated for the throwaway account" -- \
  sudo -n test -f "/home/$TESTUSER/.config/wayfire.ini"
before="$(sudo -n cat "/home/$TESTUSER/.config/wf-shell.ini")"

run_installer
after="$(sudo -n cat "/home/$TESTUSER/.config/wf-shell.ini")"
assert_eq "a second run without --force is a true no-op (byte-identical)" "$after" "$before"
assert_failure "a second run creates no backup file (nothing to force-regenerate)" -- \
  sudo -n bash -c 'ls /home/'"$TESTUSER"'/.config/wf-shell.ini.bak-* 2>/dev/null'

run_installer --force-new-user-customizations
assert_success "--force-new-user-customizations leaves a backup behind" -- \
  sudo -n bash -c 'ls /home/'"$TESTUSER"'/.config/wf-shell.ini.bak-* 2>/dev/null'
backup="$(sudo -n bash -c 'cat /home/'"$TESTUSER"'/.config/wf-shell.ini.bak-*')"
assert_eq "the backup actually preserves the pre-force content" "$backup" "$before"

# Regression test: the alias text contains a literal `&` (from
# "... & disown"), which sed's replacement syntax treats as "insert
# the whole matched line here" if unescaped -- a sed-replace-in-place
# alias writer would corrupt the line a little more on every re-run
# for the same user instead of just updating it. Three runs above
# exercises exactly that; this checks the real, shared host file
# actually came out clean.
alias_lines="$(sudo -n grep -c "^alias ${TESTUSER}-wayfire=" "$ALIASES_FILE")"
assert_eq "exactly one alias line for the throwaway user after 3 runs, not a growing pile" \
  "$alias_lines" "1"
assert_eq "the alias line is well-formed, not nested/duplicated" \
  "$(sudo -n grep "^alias ${TESTUSER}-wayfire=" "$ALIASES_FILE")" \
  "alias ${TESTUSER}-wayfire='/usr/local/bin/switch-desktop.sh ${TESTUSER} & disown; sudo su - ${TESTUSER}'"

summarize_and_exit
