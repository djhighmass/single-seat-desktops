#!/bin/bash
# run.sh -- test suite dispatcher.
#
#   ./run.sh unit          pure functions, no sudo, no system access
#   ./run.sh functional    real scripts via real CLI entry points, mostly
#                          no sudo (a couple need it; each skips itself
#                          cleanly if sudo isn't available)
#   ./run.sh disruptive    lists the disruptive tests instead of running
#                          them -- see disruptive/*.sh, run those
#                          yourself, deliberately, from the host's own
#                          terminal
#   ./run.sh all           unit + functional (never disruptive)
#
# With no argument, runs `all`.
#
# No -e: `bash "$f"` inside run_dir is expected to return nonzero
# whenever that test file has failing assertions -- that's data this
# dispatcher reads via `rc=$?` to build its own pass/fail tally, not
# an error to escalate. -e would abort run.sh itself at the first
# failing test file instead of running the rest and printing the
# per-directory and overall summaries.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

run_dir() {
  local dir="$1" total_pass=0 total_fail=0 f rc
  for f in "$dir"/*.sh; do
    [ -e "$f" ] || continue
    bash "$f"
    rc=$?
    if [ "$rc" -ne 0 ]; then total_fail=$((total_fail + 1)); else total_pass=$((total_pass + 1)); fi
    echo
  done
  echo "$dir: $total_pass file(s) passed, $total_fail file(s) failed"
  [ "$total_fail" -eq 0 ]
}

case "${1:-all}" in
  unit) run_dir unit ;;
  functional) run_dir functional ;;
  disruptive)
    echo "Disruptive tests are never run by this dispatcher -- see disruptive/*.sh"
    echo "and run one directly, deliberately, from the host account's own terminal:"
    ls disruptive/*.sh
    ;;
  all)
    ok=y
    run_dir unit || ok=n
    run_dir functional || ok=n
    [ "$ok" = y ]
    ;;
  *) echo "usage: run.sh [unit|functional|disruptive|all]" >&2; exit 1 ;;
esac
