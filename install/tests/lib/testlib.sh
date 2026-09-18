# shellcheck shell=bash
# Shared helpers for install/tests/. Sourced by every test file.

TESTS_PASSED=0
TESTS_FAILED=0

pass() { TESTS_PASSED=$((TESTS_PASSED + 1)); echo "  ok - $1"; }
fail() { TESTS_FAILED=$((TESTS_FAILED + 1)); echo "  NOT OK - $1" >&2; }

assert_eq() {
  # assert_eq <description> <actual> <expected>
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (got: $2 | want: $3)"; fi
}

assert_contains() {
  # assert_contains <description> <haystack> <needle>
  case "$2" in
    *"$3"*) pass "$1" ;;
    *) fail "$1 (did not find '$3' in: $2)" ;;
  esac
}

assert_not_contains() {
  case "$2" in
    *"$3"*) fail "$1 (found '$3' but shouldn't have)" ;;
    *) pass "$1" ;;
  esac
}

assert_file_exists() {
  [ -f "$2" ] && pass "$1" || fail "$1 (no such file: $2)"
}

assert_file_absent() {
  [ -f "$2" ] && fail "$1 (file exists but shouldn't: $2)" || pass "$1"
}

assert_success() {
  # assert_success <description> [--] <command...>
  local desc="$1"; shift
  [ "${1:-}" = "--" ] && shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc (command failed: $*)"; fi
}

assert_failure() {
  local desc="$1"; shift
  [ "${1:-}" = "--" ] && shift
  if "$@" >/dev/null 2>&1; then fail "$desc (command unexpectedly succeeded: $*)"; else pass "$desc"; fi
}

# A fresh, isolated scratch directory per test file, discarded on exit --
# nothing a test produces ever needs to (or should) land in the repo.
SCRATCH="$(mktemp -d /tmp/wf-install-tests.XXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT

summarize_and_exit() {
  echo
  echo "$TESTS_PASSED passed, $TESTS_FAILED failed"
  [ "$TESTS_FAILED" -eq 0 ]
}
