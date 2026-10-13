# shellcheck shell=bash
# Shared helpers for the wayfire multi-user desktop installer.
# Sourced by 00-create-users.sh and 10-install-wayfire-desktops.sh.

C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'

log()  { echo "${C_GREEN}==${C_RESET} $*"; }
warn() { echo "${C_YELLOW}!!${C_RESET} $*" >&2; }
err()  { echo "${C_RED}!!${C_RESET} $*" >&2; }
die()  { err "$*"; exit 1; }

require_root() {
  [ "$(id -u)" -eq 0 ] || die "run this as root (sudo $0 ...)"
}

pkg_ensure() {
  # pkg_ensure pkg1 pkg2 ... -- installs whichever of the given packages
  # aren't already installed, in one apt-get call.
  local missing=()
  for p in "$@"; do
    dpkg -s "$p" &>/dev/null || missing+=("$p")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    log "installing packages: ${missing[*]}"
    apt-get update -qq
    apt-get install -y "${missing[@]}"
  fi
}

backup_file() {
  # backup_file /path/to/file -- copies to /path/to/file.bak-<timestamp>
  # only if the file exists and differs from nothing (always backs up
  # an existing file before this installer overwrites it).
  local f="$1"
  [ -e "$f" ] || return 0
  cp -a "$f" "${f}.bak-$(date +%Y%m%d-%H%M%S)"
}

# Home directory and uid lookups that work regardless of who's asking.
user_home() { getent passwd "$1" | cut -d: -f6; }
user_uid()  { id -u "$1"; }

ensure_user_dirs() {
  # ensure_user_dirs <user> <home> <relpath>... -- creates each <home>/<relpath>
  # with every component owned by <user> (`install -d -o` owns only the
  # last one), re-owning any root-owned component. Symlinks are left alone.
  # Each component is opened no-follow relative to its already-open parent
  # and chowned by descriptor, so swapping one for a symlink mid-run can't
  # redirect root's chown outside the home. perl-base is Essential.
  local u="$1" home="$2" line
  shift 2
  while IFS= read -r line; do
    case "$line" in
      "repaired "*) log "repairing root-owned ${line#repaired } -> $u" ;;
      *) warn "$line" ;;
    esac
  done < <(perl - "$(id -u "$u")" "$(id -g "$u")" "$home" "$@" <<'PERL'
use strict; use warnings;
use Fcntl qw(O_RDONLY O_DIRECTORY O_NOFOLLOW);
my ($uid, $gid, $home, @rels) = @ARGV;
REL: for my $rel (@rels) {
  my ($dir, $next);
  sysopen($dir, $home, O_RDONLY | O_DIRECTORY) or do { print "$home: $!\n"; next REL };
  my $path = $home;
  for my $part (grep { length } split m{/}, $rel) {
    $path .= "/$part";
    chdir($dir) or do { print "$path: $!\n"; next REL };
    my $created = mkdir($part, 0755);
    unless (sysopen($next, $part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)) {
      print -l $part ? "$path is a symlink -- leaving it and its ownership alone\n" : "$path: $!\n";
      next REL;
    }
    if ($created || (stat($next))[4] == 0) {
      chown($uid, $gid, $next) or do { print "$path: chown: $!\n"; next REL };
      print "repaired $path\n" unless $created;
    }
    $dir = $next;
  }
}
PERL
)
}

# Core wayfire.ini settings that a file from an older installer lacks:
# foreign-toplevel (the panel's window list) and the panel supervisor in
# place of wayfire's one-shot autostart_wf_shell.
CORE_PLUGIN_ADD=foreign-toplevel
CORE_SHELL_CMD=/usr/local/bin/wf-shell-supervisor.sh

ensure_core_wayfire_ini() {
  # ensure_core_wayfire_ini <user> <path> -- adds the settings above to an
  # existing wayfire.ini, leaving every other line as is. Backs up and
  # rewrites only if something changes.
  local u="$1" ini="$2" tmp
  [ -f "$ini" ] || return 0
  tmp="$(mktemp)"
  awk -v plugin="$CORE_PLUGIN_ADD" -v shell_cmd="$CORE_SHELL_CMD" '
    function emit_autostart() {
      print "autostart_wf_shell = false"
      print "shell = " shell_cmd
    }
    # Matching is on the line as wayfire reads it: comment and surrounding
    # whitespace stripped. Lines are printed as written.
    function bare(s) { sub(/[ \t]*#.*/, "", s); gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    { line = bare($0) }
    line ~ /^\[.*\]$/ { section = line }
    section == "[core]" && line ~ /^plugins[ \t]*=/ {
      n = split(line, w, /[ \t=]+/); found = 0
      for (i = 2; i <= n; i++) if (w[i] == plugin) found = 1
      if (!found) {
        if (match($0, /[ \t]*#/)) $0 = substr($0, 1, RSTART - 1) " " plugin substr($0, RSTART)
        else $0 = $0 " " plugin
      }
    }
    section == "[autostart]" && line ~ /^(autostart_wf_shell|shell)[ \t]*=/ { next }
    { print }
    line == "[autostart]" && !seen_autostart { emit_autostart(); seen_autostart = 1 }
    END { if (!seen_autostart) { print ""; print "[autostart]"; emit_autostart() } }
  ' "$ini" > "$tmp"
  if cmp -s "$tmp" "$ini"; then
    rm -f "$tmp"
    return 0
  fi
  backup_file "$ini"
  write_owned_file "$u" "$ini" 644 < "$tmp"
  rm -f "$tmp"
  log "$u: updated core wayfire.ini settings (panel supervision, window list) -- previous copy backed up"
}

write_owned_file() {
  # write_owned_file <user> <path> <mode> <<'EOF' ... EOF
  local u="$1" path="$2" mode="$3"
  local tmp
  tmp="$(mktemp)"
  cat > "$tmp"
  install -o "$u" -g "$u" -m "$mode" "$tmp" "$path"
  rm -f "$tmp"
}
