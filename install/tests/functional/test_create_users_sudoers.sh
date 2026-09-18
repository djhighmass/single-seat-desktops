#!/bin/bash
# FUNCTIONAL TEST (needs sudo; creates and deletes a disposable throwaway
# account -- not the shared wftest fixture other tests reuse). Calls the
# real install_nopasswd_sudoers() from 00-create-users.sh directly rather
# than driving the whole script's interactive adduser flow: reaching this
# code path through the real CLI requires a brand-new account, which
# drags in adduser's interactive password prompts (a separate concern,
# unrelated to the bug this guards against, and not worth automating via
# guessed stdin). The account itself is still real, created with the
# ordinary non-interactive `useradd` -- only the *sudoers* logic is
# exercised through its own function rather than the full script.
#
# No -e: the "broken visudo" case deliberately makes
# install_nopasswd_sudoers fail (that's the whole point of that block)
# and assert_file_absent checks the result afterward, not the exit
# code in between -- -e would abort the file right there instead of
# reaching the happy-path case and summarize_and_exit below it.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/testlib.sh

INSTALL_DIR="$(cd ../.. && pwd)"

if [ "$(id -u)" -ne 0 ] && ! sudo -n true 2>/dev/null; then
  echo "test_create_users_sudoers: skipped (needs passwordless sudo)"
  exit 0
fi

echo "test_create_users_sudoers:"

TESTUSER="wftest-sudoers-$$"
cleanup() { sudo -n userdel -r "$TESTUSER" >/dev/null 2>&1; }
trap cleanup EXIT

sudo -n useradd -m "$TESTUSER"

mkdir -p "$SCRATCH/bin"
cat > "$SCRATCH/bin/visudo" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$SCRATCH/bin/visudo"

DEST_FAIL="$SCRATCH/sudoers-90-fail"
DEST_OK="$SCRATCH/sudoers-90-ok"

# 00-create-users.sh's own top-level `cd`/`source lib/common.sh` only
# need to run once, in the child shells below that actually call the
# function -- sourcing it here in the test's own shell would relocate
# this script's cwd too, so the function is pulled out via `declare -f`
# instead and re-defined inside each throwaway shell.
funcs="$(cd "$INSTALL_DIR" && source lib/common.sh && source 00-create-users.sh 2>/dev/null; declare -f install_nopasswd_sudoers die err)"

# --- broken visudo: the write must not land ---
sudo -n env "PATH=$SCRATCH/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  bash -c "$funcs"$'\n'"install_nopasswd_sudoers '$TESTUSER' '$DEST_FAIL'" \
  >/dev/null 2>&1
assert_file_absent "a failing visudo leaves no sudoers file behind" "$DEST_FAIL"

# --- real visudo: the happy path should still work ---
sudo -n bash -c "$funcs"$'\n'"install_nopasswd_sudoers '$TESTUSER' '$DEST_OK'"
assert_file_exists "a valid sudoers entry is installed on success" "$DEST_OK"
assert_success "visudo itself accepts what got installed" -- sudo -n visudo -cf "$DEST_OK"
assert_contains "the entry actually grants what it's supposed to" \
  "$(sudo -n cat "$DEST_OK")" "$TESTUSER ALL=(ALL) NOPASSWD:ALL"

summarize_and_exit
