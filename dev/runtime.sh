# shellcheck shell=bash
# Sourced by test-in-container.sh and dev/dev-session.sh.
# Sets RT (array) to the command that runs the container CLI, and
# RT_NAME to "podman" or "docker". Prefers podman, then docker, then
# `sudo docker` (for a user who isn't in the docker group).

pick_runtime() {
  RT=(); RT_NAME=""
  if command -v podman >/dev/null 2>&1; then
    RT=(podman); RT_NAME=podman; return 0
  fi
  if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
      RT=(docker); RT_NAME=docker; return 0
    fi
    if command -v sudo >/dev/null 2>&1; then
      echo "docker is installed but this user can't reach its daemon;" >&2
      echo "trying 'sudo docker' (add yourself to the docker group to avoid this)" >&2
      if sudo docker info >/dev/null 2>&1; then
        RT=(sudo docker); RT_NAME=docker; return 0
      fi
    fi
    echo "docker is installed but neither 'docker' nor 'sudo docker' can reach the daemon." >&2
    echo "Fix: sudo usermod -aG docker \$USER   (then log out and back in)" >&2
    return 1
  fi
  echo "no container runtime found -- install podman or docker" >&2
  return 1
}

# build_image <tag> <repo-root>
build_image() {
  "${RT[@]}" build -q -t "$1" -f "$2/dev/Containerfile" "$2/dev" >/dev/null
}
