#!/bin/bash
# FUNCTIONAL TEST (needs sudo; creates and deletes a disposable account).
# Runs the real ensure_user_dirs() as root: on a fresh home and on one with
# a root-owned ~/.local, the user can create under ~/.local/share; a
# symlink is never chowned through.
#
# No -e: assertions record failures and keep going.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/testlib.sh

INSTALL_DIR="$(cd ../.. && pwd)"

if [ "$(id -u)" -ne 0 ] && ! sudo -n true 2>/dev/null; then
  echo "test_user_dirs_ownership: skipped (needs passwordless sudo)"
  exit 0
fi

echo "test_user_dirs_ownership:"

TESTUSER="wftest-dirs-$$"
cleanup() { sudo -n userdel -r "$TESTUSER" >/dev/null 2>&1; sudo -n rm -rf "$SCRATCH/rootdir"; }
trap 'cleanup; rm -rf "$SCRATCH"' EXIT

sudo -n useradd -m -U "$TESTUSER"
H="$(getent passwd "$TESTUSER" | cut -d: -f6)"

funcs="$(source "$INSTALL_DIR/lib/common.sh"; declare -f ensure_user_dirs log warn)"
run_ensure() {
  sudo -n bash -c "$funcs"$'\n'"ensure_user_dirs '$TESTUSER' '$H' .config .local/bin .local/share .cache" >/dev/null 2>&1
}
as_user() { sudo -n -u "$TESTUSER" "$@"; }
owner() { sudo -n stat -c %U "$@"; }

# --- fresh account: every level is the user's own ---
run_ensure
assert_success "fresh: user can create under ~/.local/share" -- as_user mkdir -p "$H/.local/share/probe"
assert_success "fresh: user can create directly under ~/.local" -- as_user mkdir "$H/.local/state"
for d in .config .local .local/bin .local/share .cache; do
  assert_eq "fresh: ~/$d is owned by the user" "$(owner "$H/$d")" "$TESTUSER"
done

# --- a root-owned ~/.local is re-owned ---
sudo -n rm -rf "$H/.local"
sudo -n install -d -o root -g root -m 755 "$H/.local"
sudo -n install -d -o "$TESTUSER" -g "$TESTUSER" -m 755 "$H/.local/bin"
assert_failure "precondition: root-owned ~/.local blocks the user" -- as_user mkdir "$H/.local/share"
run_ensure
assert_success "re-run: user can create directly under ~/.local again" -- as_user mkdir "$H/.local/state"
assert_eq "re-run: ~/.local is owned by the user again" "$(owner "$H/.local")" "$TESTUSER"
assert_success "re-run: user can create under ~/.local/share" -- as_user mkdir -p "$H/.local/share/probe"

# --- a symlink is never chowned through ---
sudo -n mkdir -p "$SCRATCH/rootdir"
sudo -n rm -rf "$H/.cache"
sudo -n ln -s "$SCRATCH/rootdir" "$H/.cache"
run_ensure
assert_eq "symlinked ~/.cache's root-owned target is left root-owned" \
  "$(owner "$SCRATCH/rootdir")" "root"
assert_eq "the symlink itself is left root-owned" "$(owner "$H/.cache")" "root"
assert_eq "and is still a symlink" "$(sudo -n stat -c %F "$H/.cache")" "symbolic link"

summarize_and_exit
