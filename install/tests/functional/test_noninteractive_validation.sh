#!/bin/bash
# FUNCTIONAL TEST (needs sudo). Each invalid non-interactive flag value for
# 00-create-users.sh and 10-install-wayfire-desktops.sh must abort, with
# stdin closed, before the script's first real action (package installs,
# or adduser). No case touches an account or /usr/local, so this needs no
# WF_TESTS_ALLOW_SHARED_BOX.
#
# No -e: each case is expected to fail; assertions record and keep going.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/testlib.sh

INSTALL_DIR="$(cd ../.. && pwd)"

if [ "$(id -u)" -ne 0 ] && ! sudo -n true 2>/dev/null; then
  echo "test_noninteractive_validation: skipped (needs passwordless sudo)"
  exit 0
fi

echo "test_noninteractive_validation:"

HOST_USER="${WF_TEST_HOST_USER:-droid}"
NOSUCH="wftest-nosuch-$$"

# rejects <description> <expected stderr fragment> <script> <args...>
rejects() {
  local desc="$1" want="$2" script="$3" out rc
  shift 3
  out="$(sudo -n bash "$INSTALL_DIR/$script" "$@" </dev/null 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    fail "$desc (exited 0)"
    return
  fi
  assert_contains "$desc: says why" "$out" "$want"
  # Each script's first-action log line: 10-install's, then 00-create-users'.
  assert_not_contains "$desc: stopped before installing anything" "$out" "installing shared prerequisites"
  assert_not_contains "$desc: stopped before creating anyone" "$out" "creating "
}

rejects "misspelled timezone" "no such timezone" \
  10-install-wayfire-desktops.sh --host="$HOST_USER" --users="$NOSUCH" "--timezone=$NOSUCH:Amerika/Chicago"
rejects "account that doesn't exist" "isn't an onboardable account" \
  10-install-wayfire-desktops.sh --host="$HOST_USER" --users="$NOSUCH"
rejects "the host itself as a desktop user" "isn't an onboardable account" \
  10-install-wayfire-desktops.sh --host="$HOST_USER" --users="$HOST_USER"
rejects "an empty --users list" "no account names given" \
  10-install-wayfire-desktops.sh --host="$HOST_USER" --users=,,
# One real onboardable account, to get past the --users check.
REAL="$(awk -F: -v host="$HOST_USER" \
  '$3>=1000 && $3<60000 && $1!=host && $7 !~ /nologin|false/ {print $1; exit}' /etc/passwd)"
if [ -n "$REAL" ]; then
  rejects "--timezone for someone not in --users" "isn't in --users" \
    10-install-wayfire-desktops.sh --host="$HOST_USER" --users="$REAL" "--timezone=other-$$:UTC"
else
  echo "  skip - no onboardable account on this box for the --timezone/--users case"
fi
rejects "--host without --users" "only apply with --users" \
  10-install-wayfire-desktops.sh --host="$HOST_USER"

rejects "--sudo-level out of range" "must be 1, 2 or 3" 00-create-users.sh --sudo-level=4 "$NOSUCH"
rejects "unknown option to 00-create-users.sh" "unknown option" 00-create-users.sh --sudo=3 "$NOSUCH"
assert_failure "no account was created along the way" -- id "$NOSUCH"

summarize_and_exit
