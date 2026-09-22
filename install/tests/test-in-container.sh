#!/bin/bash
# test-in-container.sh -- run the test suite inside a Debian trixie
# container (podman or docker), so it works on any dev machine and never
# touches the host's real accounts or /etc.
#
#   ./test-in-container.sh [unit|functional|all]   (default: all)
#   ./test-in-container.sh --rebuild [mode]        force an image rebuild
#   ./test-in-container.sh --shell                 drop into a shell in the container
#
# The repo is bind-mounted read-only at /repo, so edits are picked up
# without rebuilding. Tests that need real DRM hardware, a live
# compositor, or the (deliberately gated) shared-box installer test skip
# themselves inside the container exactly as they do anywhere else.
#
# No -e: the container run's exit status is the result we want to report.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
IMAGE=single-seat-desktops-dev
# shellcheck source=../../dev/runtime.sh
source "$REPO/dev/runtime.sh"

rebuild=n; shell=n; mode=all
for arg in "$@"; do
  case "$arg" in
    --rebuild) rebuild=y ;;
    --shell) shell=y ;;
    unit|functional|all|disruptive) mode="$arg" ;;
    -h|--help) sed -n '2,/^set /p' "${BASH_SOURCE[0]}" | grep '^#' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $arg (see --help)" >&2; exit 2 ;;
  esac
done

pick_runtime || exit 2

if [ "$rebuild" = y ] || ! "${RT[@]}" image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "building $IMAGE with ${RT[*]} (first time takes a few minutes)..."
  build_image "$IMAGE" "$REPO" || { echo "image build failed" >&2; exit 2; }
fi

args=(run --rm --user tester -v "$REPO:/repo:ro" -w /repo/install/tests)
# Rootless podman remaps uids; keep-id makes the container's uid 1000 the
# invoking user, so the read-only bind mount stays readable.
[ "$RT_NAME" = podman ] && args+=(--userns=keep-id)
[ -t 0 ] && [ -t 1 ] && args+=(-it)

if [ "$shell" = y ]; then
  exec "${RT[@]}" "${args[@]}" "$IMAGE" bash
fi
"${RT[@]}" "${args[@]}" "$IMAGE" bash run.sh "$mode"
