#!/bin/bash
# FUNCTIONAL TEST -- apps/install.sh and apps/defaults.sh through their real
# CLIs. apt-get, dpkg-query and extrepo are stubs and install.sh gets a scratch
# /etc, so the machine isn't changed. Installer checks past argument handling,
# and "defaults refuse root", need root or passwordless sudo; "the installer
# needs root" and the other defaults checks need a non-root user, and the one
# that another user can't read Claude's settings also needs passwordless sudo.
# Skips are reported. Real extrepo and apt need a real install.
#
#   bash apps/tests/test_apps.sh
set -uo pipefail
umask 022   # the scratch files, stubs included: usable by us, writable by no one else
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source ../install/tests/lib/testlib.sh || exit 1   # SCRATCH must be its own, not the caller's
unset BASH_ENV APPS NAMES XG CC DPKG_INSTALLED DPKG_STATUS $(compgen -A variable FAIL_)   # none inherited from the caller's shell
echo "test_apps:"

# Stubs. apt-get and extrepo log what they were asked to do into $SCRATCH/calls.
#   apt-get     logs the DEBIAN_FRONTEND of an install. Fails an install whose
#               arguments contain $FAIL_INSTALL, or $FAIL_PARTLY (after leaving
#               that package in state $FAIL_PARTLY_STATE); fails every update if $FAIL_UPDATE is
#               set; with $FAIL_ADDED set, fails an update once an extrepo
#               source exists (as real apt does for a conflicting one)
#   dpkg-query  answers only the query install.sh makes: $DPKG_INSTALLED is in
#               state $DPKG_STATUS (default installed); a package apt-get left
#               partway is in the state it recorded
#   extrepo     "enable <name>" fails unless the non-free policy is on. It writes
#               the source file, and for google_chrome overwrites the defaults
#               file, as the real one does; with $FAIL_EXTREPO set it fails
#               after writing them
STUB="$SCRATCH/stub"; mkdir -p "$STUB"
cat > "$STUB/apt-get" <<'STUB_END'
#!/bin/sh
echo "apt-get $*" >> "$SCRATCH/calls"
case "$1" in
  update)  [ -z "$FAIL_UPDATE" ] || exit 1
           if [ -n "$FAIL_ADDED" ]; then for f in "$APPS_ETC"/apt/sources.list.d/extrepo_*.sources; do [ ! -e "$f" ] || exit 1; done; fi ;;
  install) echo "frontend: ${DEBIAN_FRONTEND:-unset}" >> "$SCRATCH/calls"
           [ -z "$FAIL_INSTALL" ] || case "$*" in *"$FAIL_INSTALL"*) exit 1 ;; esac
           if [ -n "$FAIL_PARTLY" ]; then case "$*" in *"$FAIL_PARTLY"*) printf '%s' "${FAIL_PARTLY_STATE:-installed}" > "$SCRATCH/installed-$FAIL_PARTLY"; exit 1 ;; esac; fi ;;
esac
exit 0
STUB_END
cat > "$STUB/dpkg-query" <<'STUB_END'
#!/bin/sh
[ "$1" = -W ] && [ "$2" = '-f=${db:Status-Status}' ] || exit 1
[ ! -e "$SCRATCH/installed-$3" ] || { cat "$SCRATCH/installed-$3"; exit 0; }
[ "$3" = "$DPKG_INSTALLED" ] && printf '%s' "${DPKG_STATUS:-installed}"
STUB_END
cat > "$STUB/extrepo" <<'STUB_END'
#!/bin/sh
echo "extrepo $*" >> "$SCRATCH/calls"
[ "$1" = enable ] || exit 1
grep -qxE -- '[[:space:]]*- non-free[[:space:]]*(#.*)?' "$APPS_ETC/extrepo/config.yaml" || exit 1
echo "Signed-By: /var/lib/extrepo/keys/$2.asc" > "$APPS_ETC/apt/sources.list.d/extrepo_$2.sources"
[ "$2" != google_chrome ] || echo 'repo_add_once="false"' > "$APPS_ETC/default/google-chrome"
[ -z "$FAIL_EXTREPO" ] || exit 1
STUB_END
chmod +x "$STUB"/*
# If a stub can't run (say /tmp is noexec), the real command would, maybe as root.
for c in apt-get dpkg-query extrepo; do
  [ "$(PATH="$STUB:$PATH"; command -v "$c")" = "$STUB/$c" ] || { echo "  NOT OK - the $c stub can't run; stopping" >&2; exit 1; }
done

ETC="$SCRATCH/etc"
as_root() { if [ "$EUID" -eq 0 ]; then env "$@"; else sudo -n env "$@"; fi; }
as_root true 2>/dev/null && have_root=y || have_root=n
# another_can_read <file under $SCRATCH>: can "nobody" read it? Lets others
# through the directories down to it first, so they don't decide the answer.
another_can_read() {
  local d="$1"
  while [ "$d" != "$SCRATCH" ]; do d="$(dirname "$d")"; chmod o+x "$d" || return 1; done
  as_root setpriv --reuid=nobody --regid=nogroup --clear-groups cat "$1" >/dev/null 2>&1
}
# Root-run install.sh creates things under $ETC that this user may not be able to remove.
[ "$have_root" = n ] || trap 'as_root rm -rf "$SCRATCH"' EXIT
# Debian's lines, plus a look-alike ("non-free-firmware") that must stay as it is.
SHIPPED=$'---\nenabled_policies:\n- main\n# - contrib\n# - non-free\n# - non-free-firmware'
fresh_etc() {
  as_root rm -rf "$ETC"; mkdir -p "$ETC/apt/sources.list.d" "$ETC/default" "$ETC/extrepo"
  printf '%s\n' "$SHIPPED" > "$ETC/extrepo/config.yaml"
}
repo_files() { find "$ETC/apt" "$ETC/default" ! -type d | wc -l; }
# Settings for a run go in the environment, e.g. FAIL_ADDED=1 install_apps claude-code.
# It runs with no DEBIAN_FRONTEND and under a hostile umask (077).
install_apps() {
  local v fwd=()
  for v in DPKG_INSTALLED DPKG_STATUS $(compgen -A variable FAIL_); do
    [ -z "${!v:-}" ] || fwd+=("$v=${!v}")
  done
  : > "$SCRATCH/calls"; as_root rm -f "$SCRATCH"/installed-*
  as_root -u DEBIAN_FRONTEND SCRATCH="$SCRATCH" PATH="$STUB:$PATH" APPS_ETC="$ETC" "${fwd[@]}" \
    sh -c 'umask 077; exec bash install.sh "$@"' sh "$@" 2>&1
}
calls() { cat "$SCRATCH/calls"; }
call_line() { calls | grep -n -m1 -- "$1" | cut -d: -f1; }
in_order() { local a b; a="$(call_line "$1")"; b="$(call_line "$2")"; [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; }
# run_ok / run_fail <description> <command...>: keep the output in $out and
# assert that it exited 0 / 1.
run_ok()   { local d="$1"; shift; out="$("$@" 2>&1)"; rc=$?; assert_eq "$d" "$rc" "0"; }
run_fail() { local d="$1"; shift; out="$("$@" 2>&1)"; rc=$?; assert_eq "$d" "$rc" "1"; }

# --- install.sh: arguments. Stubbed, with a scratch /etc, in case a check ever
# stopped working while the suite ran as root. ---
bare_install() { env SCRATCH="$SCRATCH" PATH="$STUB:$PATH" APPS_ETC="$SCRATCH/no-etc" bash install.sh "$@"; }
: > "$SCRATCH/calls"
run_ok "--list succeeds without root" bare_install --list
for app in lxterminal claude-code google-chrome; do assert_contains "...naming $app" "$out" "$app"; done
run_fail "no apps named is refused" bare_install;                 assert_contains "...with the usage" "$out" "usage:"
run_fail "an unknown app is refused" bare_install nonesuch;       assert_contains "...saying so" "$out" "no such app"
run_fail "an unknown option is refused" bare_install --channel=latest claude-code; assert_contains "...saying so" "$out" "unknown option"
if [ "$EUID" -eq 0 ]; then echo "  skip - refusing to run without root can't be checked as root"
else run_fail "running without root is refused" bare_install lxterminal; assert_contains "...saying so" "$out" "run this as root"; fi
assert_eq "none of these touch apt" "$(calls)" ""

# An app is just a folder: in a copy of apps/, a new one needs no other edit.
COPY="$SCRATCH/copy"; mkdir -p "$COPY/install" "$COPY/apps/demo" "$COPY/apps/broken"
cp -r ../install/lib "$COPY/install/"; cp -r install.sh defaults.sh lib.sh ./*/ "$COPY/apps/"
echo 'apt_install demo-package' > "$COPY/apps/demo/install.sh"
echo 'new_default sh "$HOME/demo.conf" "demo=1" "demo set"' > "$COPY/apps/demo/defaults.sh"
echo 'false' > "$COPY/apps/broken/install.sh"
run_ok "a new app folder is listed by the installer" bash "$COPY/apps/install.sh" --list; assert_contains "...by name" "$out" "demo"
if [ "$EUID" -eq 0 ]; then echo "  skip - the defaults list can't be checked as root"
else
  run_ok "...and by the defaults" bash "$COPY/apps/defaults.sh" --list; assert_contains "...by name" "$out" "demo"
  assert_not_contains "...which lists only apps with defaults" "$out" "google-chrome"
fi
for bad in ../lxterminal lxterminal/ . tests; do
  run_fail "'$bad' is not an app name" bare_install "$bad"; assert_contains "...saying so" "$out" "no such app"
done
assert_eq "none of these touch apt" "$(calls)" ""

# --- install.sh: the apps (needs root) ---
if [ "$have_root" = n ]; then
  echo "  skip - install checks need root or passwordless sudo"
else
  fresh_etc; : > "$SCRATCH/calls"
  copy_install() { as_root SCRATCH="$SCRATCH" PATH="$STUB:$PATH" APPS_ETC="$ETC" bash "$COPY/apps/install.sh" "$@"; }
  run_ok "a new app folder installs" copy_install demo
  assert_contains "...running its file" "$(calls)" "install -y demo-package"
  : > "$SCRATCH/calls"
  run_fail "an app file that fails stops the run" copy_install broken demo
  assert_contains "...saying which" "$out" "could not install broken"
  assert_not_contains "...before the next app" "$(calls)" "demo-package"
  run_ok "lxterminal installs" install_apps lxterminal
  assert_success "...after refreshing the package lists" in_order "apt-get update" "install -y lxterminal"
  assert_contains "...non-interactively" "$(calls)" "frontend: noninteractive"
  assert_not_contains "...without extrepo" "$(calls)" "extrepo"
  assert_eq "...leaving extrepo's policy alone" "$(cat "$ETC/extrepo/config.yaml")" "$SHIPPED"
  run_fail "a bad app named after a good one fails the run" install_apps lxterminal nonesuch
  assert_eq "...before anything is installed" "$(calls)" ""
  FAIL_UPDATE=1 run_ok "a failing first update is only a warning" install_apps lxterminal
  assert_contains "...which says so" "$out" "package lists as they are"
  FAIL_INSTALL=lxterminal run_fail "a failed app stops the run, in the order named" install_apps lxterminal google-chrome
  assert_contains "...saying which" "$out" "could not install: lxterminal"
  assert_not_contains "...without claiming success" "$out" "lxterminal installed"
  assert_not_contains "...so the next one isn't started" "$(calls)" "extrepo"
  FAIL_INSTALL=extrepo run_fail "an extrepo that can't be installed fails the run" install_apps claude-code
  assert_contains "...saying so" "$out" "could not install: extrepo"
  assert_not_contains "...nothing is enabled" "$(calls)" "extrepo enable"
  assert_eq "...and the policy is untouched" "$(cat "$ETC/extrepo/config.yaml")" "$SHIPPED"

  for row in claude-code:anthropic-claude-code:claude-code:1 google-chrome:google_chrome:google-chrome-stable:2; do
    IFS=: read -r app repo pkg files <<< "$row"
    src="$ETC/apt/sources.list.d/extrepo_$repo.sources"
    fresh_etc
    run_ok "$app installs" install_apps "$app"
    assert_success "...extrepo is installed before it is used" in_order "install -y extrepo" "extrepo enable $repo"
    assert_success "...apt is refreshed between adding the repository and installing from it" \
      test "$(calls | sed -n "/extrepo enable/,/install -y $pkg/p" | grep -c '^apt-get update')" -gt 0
    assert_success "...then installs $pkg" in_order "extrepo enable $repo" "install -y $pkg"
    assert_eq "...both installs non-interactive" "$(calls | grep '^frontend:')" $'frontend: noninteractive\nfrontend: noninteractive'
    assert_eq "...only the non-free policy is enabled" "$(cat "$ETC/extrepo/config.yaml")" "${SHIPPED/'# - non-free'/- non-free}"
    assert_success "...another user can read the extrepo stub's file: install.sh replaced the caller's umask" another_can_read "$src"
    assert_eq "...and is kept" "$(repo_files)" "$files"
    run_ok "...a second run succeeds" install_apps "$app"
    assert_not_contains "...without enabling the repository again" "$(calls)" "extrepo enable"

    DPKG_INSTALLED="$pkg" run_ok "an installed $pkg is left alone" install_apps "$app" lxterminal
    assert_contains "...saying so" "$out" "already installed"
    assert_not_contains "...without touching extrepo" "$(calls)" "extrepo"
    assert_contains "...and the next app is still installed" "$(calls)" "install -y lxterminal"
    for state in config-files half-configured; do
      fresh_etc; DPKG_INSTALLED="$pkg" DPKG_STATUS="$state" run_ok "$pkg already $state is installed again" install_apps "$app"
      assert_contains "...by apt" "$(calls)" "install -y $pkg"
    done

    # A repository file that was already there is used as it is, and never removed.
    fresh_etc; echo mine > "$src"
    FAIL_INSTALL="$pkg" run_fail "with a repository file already there, a failed $app fails" install_apps "$app"
    assert_not_contains "...it was not enabled again" "$(calls)" "extrepo enable"
    assert_eq "...the file is untouched" "$(cat "$src")" "mine"
    assert_eq "...and so is the policy" "$(cat "$ETC/extrepo/config.yaml")" "$SHIPPED"
    fresh_etc; ln -s "$SCRATCH/nowhere" "$src"
    run_ok "a dangling link in its place isn't enabled over" install_apps "$app"
    assert_not_contains "...nothing was enabled" "$(calls)" "extrepo enable"
    assert_eq "...and it is still that link" "$(readlink "$src")" "$SCRATCH/nowhere"

    # Failures once the repository is being set up: what the run created goes.
    for how in FAIL_EXTREPO FAIL_ADDED FAIL_INSTALL; do
      value=1; [ "$how" != FAIL_INSTALL ] || value="$pkg"
      fresh_etc
      export "$how=$value"; run_fail "$app: $how fails the run" install_apps "$app"; unset "$how"
      assert_eq "...removing what it created" "$(repo_files)" "0"
      assert_contains "...saying so" "$out" "which this run had created"
      assert_not_contains "...without claiming success" "$out" "$pkg installed"
    done
    run_ok "...and running it again then succeeds" install_apps "$app"

    for state in installed half-configured half-installed unpacked; do
      fresh_etc; FAIL_PARTLY="$pkg" FAIL_PARTLY_STATE="$state" run_fail "$pkg left $state although apt reports failure" install_apps "$app"
      assert_eq "...keeps its repository" "$(repo_files)" "$files"
      assert_contains "...saying so" "$out" "so its repository is kept"
    done
    for state in config-files not-installed; do
      fresh_etc; FAIL_PARTLY="$pkg" FAIL_PARTLY_STATE="$state" run_fail "$pkg left $state by a failed install" install_apps "$app"
      assert_eq "...doesn't keep its repository" "$(repo_files)" "0"
    done
  done
  fresh_etc
  FAIL_INSTALL=lxterminal run_fail "a later app can fail after claude-code installs" install_apps claude-code lxterminal
  assert_file_exists "...and Claude's repository is kept" "$ETC/apt/sources.list.d/extrepo_anthropic-claude-code.sources"

  chrome_defaults="$ETC/default/google-chrome"
  chrome_source="$ETC/apt/sources.list.d/extrepo_google_chrome.sources"
  # Both files there before the run: a later failure must not remove either.
  fresh_etc; echo 'MY_SETTING=1' > "$chrome_defaults"; echo mine > "$chrome_source"
  FAIL_INSTALL=google-chrome-stable run_fail "a failed Chrome with both files already there" install_apps google-chrome
  assert_eq "...keeps the defaults file as it was" "$(cat "$chrome_defaults")" "MY_SETTING=1"
  assert_eq "...and the repository file" "$(cat "$chrome_source")" "mine"
  run_ok "a successful run in that state" install_apps google-chrome
  assert_eq "...leaves both alone" "$(cat "$chrome_defaults" "$chrome_source")" $'MY_SETTING=1\nmine'
  fresh_etc; echo 'MY_SETTING=1' > "$chrome_defaults"
  run_fail "Chrome's defaults file already there stops the install" install_apps google-chrome
  assert_contains "...naming it" "$out" "$chrome_defaults already exists"
  assert_eq "...it is untouched" "$(cat "$chrome_defaults")" "MY_SETTING=1"
  assert_not_contains "...nothing is enabled" "$(calls)" "extrepo enable"
  assert_eq "...nor is the policy" "$(cat "$ETC/extrepo/config.yaml")" "$SHIPPED"
  fresh_etc; ln -s "$SCRATCH/nowhere" "$chrome_defaults"
  run_fail "so does a dangling link there" install_apps google-chrome
  assert_eq "...which is kept" "$(readlink "$chrome_defaults")" "$SCRATCH/nowhere"

  for line in '- non-free' '  - non-free' '- non-free  # mine'; do
    fresh_etc; printf '%s\n' "$line" > "$ETC/extrepo/config.yaml"
    run_ok "a policy already enabled as '$line' is fine" install_apps claude-code
    assert_eq "...and the file is left as it was" "$(cat "$ETC/extrepo/config.yaml")" "$line"
  done
  # Look-alike policy lines are neither "already enabled" nor the shipped line.
  for line in '- non-free-firmware' '# - non-free-firmware'; do
    fresh_etc; printf '%s\n' "$line" > "$ETC/extrepo/config.yaml"
    run_fail "'$line' alone doesn't count as non-free" install_apps claude-code
    assert_contains "...saying what to do" "$out" "including '- non-free'"
    assert_eq "...the file is untouched" "$(cat "$ETC/extrepo/config.yaml")" "$line"
    assert_not_contains "...and nothing is enabled" "$(calls)" "extrepo enable"
  done
  fresh_etc; rm "$ETC/extrepo/config.yaml"
  run_fail "a missing policy file stops the install" install_apps claude-code
  assert_contains "...saying so" "$out" "is missing or can't be read"
  assert_not_contains "...and nothing is enabled" "$(calls)" "extrepo enable"
  fresh_etc; echo 'enabled_policies: [main]' > "$ETC/extrepo/config.yaml"
  run_fail "a policy file without the shipped line stops the install" install_apps claude-code
  assert_contains "...saying what to do" "$out" "including '- non-free', then run this again"
  assert_eq "...the file is untouched" "$(cat "$ETC/extrepo/config.yaml")" "enabled_policies: [main]"
  assert_not_contains "...and nothing is enabled" "$(calls)" "extrepo enable"
fi

# --- defaults.sh: as this user, against a scratch HOME ---
# bin <name> <command>...: a PATH directory of fake apps and links to real tools.
bin() {
  local d="$SCRATCH/$1" c; shift; mkdir -p "$d"
  for c; do
    case "$c" in
      lxterminal|claude) : > "$d/$c"; chmod +x "$d/$c" ;;
      *) ln -sf "$(command -v "$c")" "$d/$c" ;;
    esac
  done
}
TOOLS="dirname mkdir mktemp ln rm"
bin both lxterminal claude $TOOLS
bin lx lxterminal $TOOLS
bin cc claude $TOOLS
bin none $TOOLS
# Settings for one call: APPS=<bin name> NAMES=<apps to name> XG=<XDG_CONFIG_HOME>
# CC=<CLAUDE_CONFIG_DIR>.
# The caller's own two directory variables are never passed on.
defaults() { ( umask 022; HOME="$H" XDG_CONFIG_HOME="${XG:-}" CLAUDE_CONFIG_DIR="${CC:-}" PATH="$SCRATCH/${APPS:-both}" /bin/bash defaults.sh ${NAMES-lxterminal claude-code} 2>&1 ); }
new_home() { H="$SCRATCH/home-$1"; mkdir -p "$H"; S="$H/.claude/settings.json"; L="$H/.config/lxterminal/lxterminal.conf"; }
everything() { find "$H" ! -type d | wc -l; }

if [ "$have_root" = n ]; then
  echo "  skip - that defaults refuse root needs root or passwordless sudo"
else
  new_home root
  run_fail "defaults.sh refuses to run as root" as_root HOME="$H" XDG_CONFIG_HOME= CLAUDE_CONFIG_DIR= PATH="$SCRATCH/both" /bin/bash defaults.sh lxterminal claude-code
  assert_contains "...saying so" "$out" "not as root"
  assert_eq "...writing nothing" "$(everything)" "0"
fi
if [ "$EUID" -eq 0 ]; then
  echo "  skip - the other defaults checks need a non-root user"
else
  new_home args
  NAMES= run_fail "defaults with no app named is refused" defaults; assert_contains "...with the usage" "$out" "usage:"
  NAMES="lxterminal nonesuch" run_fail "an unknown app is refused" defaults; assert_contains "...saying so" "$out" "no such app: nonesuch"
  assert_eq "...before anything is written" "$(everything)" "0"
  for bad in ../lxterminal lxterminal/ . tests; do
    NAMES="$bad" run_fail "defaults: '$bad' is not an app name" defaults; assert_contains "...saying so" "$out" "no such app"
  done
  NAMES=google-chrome run_ok "an app without defaults is fine" defaults; assert_contains "...saying so" "$out" "google-chrome has no defaults"
  assert_eq "...writing nothing" "$(everything)" "0"
  NAMES=claude-code run_ok "only the named app is configured" defaults
  assert_eq "...and nothing else" "$(everything)" "1"
  assert_file_exists "...in its settings" "$S"
  new_home copy; run_ok "a new app's defaults apply" env HOME="$H" bash "$COPY/apps/defaults.sh" demo
  assert_eq "...from its own file" "$(cat "$H/demo.conf")" "demo=1"
  # Two settings in one app: the first can't be written (a file is where its directory should be).
  new_home two; : > "$H/blocked"
  printf '%s\n' 'new_default sh "$HOME/blocked/one" "a=1" "one set"' 'new_default sh "$HOME/two" "b=2" "two set"' > "$COPY/apps/demo/defaults.sh"
  run_fail "a failed write isn't hidden by a later one" env HOME="$H" bash "$COPY/apps/defaults.sh" demo
  assert_contains "...it is reported" "$out" "$H/blocked/one couldn't be written"
  assert_eq "...and the later one is still written" "$(cat "$H/two")" "b=2"
  new_home fails; echo 'false' > "$COPY/apps/demo/defaults.sh"
  run_fail "an app file that fails any other way is reported too" env HOME="$H" XDG_CONFIG_HOME= PATH="$SCRATCH/both" /bin/bash "$COPY/apps/defaults.sh" demo lxterminal
  assert_file_exists "...and the next app is still configured" "$L"
  new_home none
  APPS=none run_ok "with no apps it succeeds" defaults
  assert_contains "...says LXTerminal was skipped" "$out" "skipped: lxterminal"
  assert_contains "...and Claude Code" "$out" "skipped: claude"
  assert_eq "...and creates nothing" "$(everything)" "0"
  new_home lx; APPS=lx run_ok "LXTerminal alone is configured" defaults
  assert_eq "...and nothing else" "$(everything)" "1"
  assert_file_exists "...in its config" "$L"
  new_home cc; APPS=cc run_ok "Claude Code alone is configured" defaults
  assert_eq "...and nothing else" "$(everything)" "1"
  assert_file_exists "...in its settings" "$S"

  new_home fresh; run_ok "a first run succeeds" defaults
  assert_eq "LXTerminal gets 10000 lines of scrollback" "$(cat "$L")" $'[general]\nscrollback=10000'
  assert_eq "Claude Code gets the classic renderer" "$(cat "$S")" '{"tui": "default"}'
  if [ "$have_root" = n ]; then
    echo "  skip - that another user can't read Claude's settings needs root or passwordless sudo"
  else
    assert_failure "...which another user can't read" another_can_read "$S"
    chmod o+r "$S"; assert_success "...though they could if it allowed others" another_can_read "$S"
  fi
  assert_eq "...with no temp files left" "$(everything)" "2"

  echo mine > "$S"; : > "$L"; run_ok "a run over existing files succeeds" defaults
  assert_eq "...Claude Code's is untouched" "$(cat "$S")" "mine"
  assert_success "...an empty LXTerminal config is still there, and empty" test -f "$L" -a ! -s "$L"
  assert_contains "...says they were left alone" "$out" "left alone: $L"
  assert_contains "...and what to add for Claude Code" "$out" 'add "tui": "default"'
  assert_contains "...and for LXTerminal" "$out" "make [general] read scrollback=10000"

  new_home links; mkdir -p "$(dirname "$S")" "$(dirname "$L")"
  ln -s "$H/missing-settings" "$S"; ln -s "$H/missing-conf" "$L"
  run_ok "a run over dangling symlinks succeeds" defaults
  assert_eq "...Claude Code's link is kept" "$(readlink "$S")" "$H/missing-settings"
  assert_eq "...and LXTerminal's" "$(readlink "$L")" "$H/missing-conf"
  assert_eq "...and nothing is created" "$(everything)" "2"
  rm "$S"; ln -s "$S" "$S"; run_ok "a symlink to itself is left alone too" defaults
  assert_eq "...still a link" "$(readlink "$S")" "$S"

  new_home xdg; XG="$H/xdg" CC="$H/cc" run_ok "the config directory variables are honoured" defaults
  assert_file_exists "...for LXTerminal" "$H/xdg/lxterminal/lxterminal.conf"
  assert_file_exists "...and Claude Code" "$H/cc/settings.json"

  # One that can't be written is a failure, said out loud, and doesn't stop the other.
  new_home ro; mkdir -p "$H/.config"; chmod 555 "$H/.config"
  run_fail "a config that can't be written is a failure" defaults
  assert_contains "...which says so" "$out" "$L couldn't be written"
  assert_file_exists "...while Claude Code still gets its default" "$S"
  chmod 755 "$H/.config"
  new_home ro-claude; mkdir -p "$H/.claude"; chmod 555 "$H/.claude"
  run_fail "Claude Code settings that can't be written are a failure" defaults
  assert_contains "...which says so" "$out" "$S couldn't be written"
  assert_file_exists "...with LXTerminal's, written first, in place" "$L"
  chmod 755 "$H/.claude"
  # A file that appears after the check must not be replaced: ln itself refuses.
  new_home race; bin race lxterminal claude dirname mkdir mktemp rm
  printf '#!/bin/sh\nfor last; do :; done\necho theirs > "$last"\nexec %s "$@"\n' "$(command -v ln)" > "$SCRATCH/race/ln"; chmod +x "$SCRATCH/race/ln"
  APPS=race run_fail "a file that appears just before ours is put in place is a failure" defaults
  assert_eq "...and is not replaced" "$(cat "$S" "$L")" $'theirs\ntheirs'
  assert_eq "...with no temp files left" "$(everything)" "2"
  new_home noln; bin noln lxterminal dirname mkdir mktemp rm; printf '#!/bin/sh\nexit 1\n' > "$SCRATCH/noln/ln"; chmod +x "$SCRATCH/noln/ln"
  APPS=noln run_fail "a file that can't be put in place is a failure" defaults
  assert_eq "...leaving no partial or temp file" "$(everything)" "0"
fi

summarize_and_exit
