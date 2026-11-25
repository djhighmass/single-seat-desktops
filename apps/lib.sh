# apps/lib.sh -- the installer's shared helpers and guards, sourced by
# apps/install.sh before each app's install.sh.
# shellcheck source=../install/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../install/lib/common.sh" || { echo "!! could not load install/lib/common.sh -- apps/ needs the whole repository" >&2; exit 1; }

# Where the files these helpers look at live; overridable for tests only.
APPS_ETC="${APPS_ETC:-/etc}"
EXTREPO_CONFIG="$APPS_ETC/extrepo/config.yaml"

apt_install() { DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" || die "could not install: $*"; }
pkg_status() { dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null; }
taken() { [ -e "$1" ] || [ -L "$1" ]; }   # anything there, even a dangling symlink

# Files this run created for the current app's repository. Removed on exit only
# if dpkg shows its package as absent (nothing, not-installed, config-files);
# any other state keeps them. Files already there are never listed.
added=() added_for=
cleanup() {
  local f state
  [ "${#added[@]}" -gt 0 ] || return 0
  state="$(pkg_status "$added_for")"
  case "$state" in
    ''|not-installed|config-files) ;;
    *) warn "$added_for is on this machine (dpkg says: $state), so its repository is kept"; return 0 ;;
  esac
  for f in "${added[@]}"; do
    taken "$f" || continue
    if rm -f "$f"; then warn "removed $f, which this run had created"; else warn "could not remove $f -- remove it yourself"; fi
  done
}
trap cleanup EXIT

# extrepo refuses these repositories until its "non-free" policy is enabled.
# Only the line as Debian ships it is changed.
allow_non_free() {
  [ -r "$EXTREPO_CONFIG" ] || die "$EXTREPO_CONFIG is missing or can't be read"
  grep -qxE -- '[[:space:]]*- non-free[[:space:]]*(#.*)?' "$EXTREPO_CONFIG" && return
  grep -qx -- '# - non-free' "$EXTREPO_CONFIG" \
    || die "$EXTREPO_CONFIG doesn't have the line '# - non-free' that Debian ships -- left as it is. List enabled_policies one per line, including '- non-free', then run this again."
  sed -i 's/^# - non-free$/- non-free/' "$EXTREPO_CONFIG" || die "could not edit $EXTREPO_CONFIG"
  log "enabled extrepo's non-free policy ($EXTREPO_CONFIG)"
}

# from_extrepo <repository> <package> [another file that enabling it overwrites]
# On failure, e.g. apt rejecting two keys for one repository, cleanup() handles
# what this created.
from_extrepo() {
  local repo="$1" pkg="$2" other="${3:-}" source="$APPS_ETC/apt/sources.list.d/extrepo_$1.sources"
  if [ "$(pkg_status "$pkg")" = installed ]; then log "$pkg is already installed -- left alone"; return; fi
  apt_install extrepo
  if taken "$source"; then
    # Not enabled again: that rewrites the file.
    log "$source already exists -- using it as it is (if it is disabled, run 'sudo extrepo enable $repo', then run this again)"
  else
    if [ -n "$other" ] && taken "$other"; then
      die "$other already exists, and enabling $repo would overwrite it -- left as it is. If you don't need it, move it away and run this again."
    fi
    allow_non_free
    added=("$source") added_for="$pkg"
    [ -z "$other" ] || added+=("$other")
    extrepo enable "$repo" || die "extrepo could not enable $repo"
  fi
  apt-get update -qq || die "apt-get update failed with the $repo repository in place (see apt's messages above)"
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" \
    || die "could not install $pkg with the $repo repository in place (see apt's messages above)"
  added=()   # proved good: keep them
  log "$pkg installed"
}
