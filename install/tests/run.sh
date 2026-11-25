#!/bin/bash
# run.sh -- test suite dispatcher.
#
#   ./run.sh unit          pure functions, no sudo, no system access
#   ./run.sh functional    real scripts via real CLI entry points, mostly
#                          no sudo (a couple need it; each skips itself
#                          cleanly if sudo isn't available); also runs the
#                          optional apps layer's test, ../../apps/tests/
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
# summaries (one per tier, naming its directories).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

run_dir() {  # run_dir <dir>... -- one summary for all of them
  local total_pass=0 total_fail=0 dir f rc
  for dir; do
    # A directory with no tests is a failure, not a pass: a moved or misnamed one must not vanish.
    compgen -G "$dir/*.sh" >/dev/null || { echo "no tests found in $dir" >&2; total_fail=$((total_fail + 1)); continue; }
    for f in "$dir"/*.sh; do
      bash "$f"
      rc=$?
      if [ "$rc" -ne 0 ]; then total_fail=$((total_fail + 1)); else total_pass=$((total_pass + 1)); fi
      echo
    done
  done
  echo "$*: $total_pass file(s) passed, $total_fail file(s) failed"
  [ "$total_fail" -eq 0 ]
}

# The optional apps layer's test (apps/tests/) runs with the functional tier.
FUNCTIONAL=(functional ../../apps/tests)

case "${1:-all}" in
  unit) run_dir unit ;;
  functional) run_dir "${FUNCTIONAL[@]}" ;;
  disruptive)
    echo "Disruptive tests are never run by this dispatcher -- see disruptive/*.sh"
    echo "and run one directly, deliberately, from the host account's own terminal:"
    ls disruptive/*.sh
    ;;
  all)
    ok=y
    run_dir unit || ok=n
    run_dir "${FUNCTIONAL[@]}" || ok=n
    [ "$ok" = y ]
    ;;
  *) echo "usage: run.sh [unit|functional|disruptive|all]" >&2; exit 1 ;;
esac
