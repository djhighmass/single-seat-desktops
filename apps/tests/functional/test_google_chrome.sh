#!/bin/bash
# FUNCTIONAL TEST (needs sudo) -- apps/google-chrome/install.sh with curl and
# apt-get stubbed and a scratch-built .deb standing in for Google's:
# the right architecture's URL is fetched, a real google-chrome-stable
# package is handed to apt, anything else is refused, unsupported
# architectures are refused, and an installed Chrome is left alone.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/testlib.sh
APP="$(cd ../../google-chrome && pwd)"

if ! sudo -n true 2>/dev/null; then
  echo "test_google_chrome: skipped (needs passwordless sudo)"; exit 0
fi
echo "test_google_chrome:"
assert_failure "refuses to run without root" env -u SUDO_USER bash -c "[ \$(id -u) -ne 0 ] && bash '$APP/install.sh'"

mkdeb() {  # mkdeb <package name> <out>
  local d="$SCRATCH/deb-$1"; mkdir -p "$d/DEBIAN"
  printf 'Package: %s\nVersion: 1\nArchitecture: all\nMaintainer: t <t@invalid>\nDescription: t\n' "$1" > "$d/DEBIAN/control"
  dpkg-deb --build -Zgzip "$d" "$2" >/dev/null
}
STUB="$SCRATCH/stub"; mkdir -p "$STUB"
printf '#!/bin/sh\nfor a; do case "$a" in https:*) echo "$a" > %s/url ;; esac; done\nwhile [ $# -gt 0 ]; do [ "$1" = -o ] && cp "$FAKE_DEB" "$2"; shift; done\n' "$SCRATCH" > "$STUB/curl"
printf '#!/bin/sh\necho "$@" > %s/apt-args\nfor a; do case "$a" in *.deb) dpkg-deb -f "$a" Package > %s/apt-pkg ;; esac; done\n' "$SCRATCH" "$SCRATCH" > "$STUB/apt-get"
chmod +x "$STUB"/*
mkdeb google-chrome-stable "$SCRATCH/good.deb"
mkdeb something-else "$SCRATCH/bad.deb"
chmod -R a+rX "$SCRATCH"
run() {  # run <deb> <arch>
  rm -f "$SCRATCH/url" "$SCRATCH/apt-args" "$SCRATCH/apt-pkg"
  sudo -n env FAKE_DEB="$1" DPKG_ARCH="$2" CURL="$STUB/curl" APT_GET="$STUB/apt-get" \
    bash "$APP/install.sh" 2>&1
}

if dpkg -s google-chrome-stable >/dev/null 2>&1; then
  out="$(run "$SCRATCH/good.deb" arm64)"
  assert_contains "an installed Chrome is left alone" "$out" "already installed"
  assert_file_absent "nothing is downloaded" "$SCRATCH/url"
  echo "  skip - download/install checks (Chrome is installed here; they run on a machine without it)"
  summarize_and_exit; exit $?
fi

out="$(run "$SCRATCH/good.deb" arm64)"; rc=$?
assert_eq "succeeds" "$rc" "0"
assert_eq "fetches Google's arm64 .deb" "$(cat "$SCRATCH/url")" "https://dl.google.com/linux/direct/google-chrome-stable_current_arm64.deb"
assert_eq "hands google-chrome-stable to apt" "$(cat "$SCRATCH/apt-pkg")" "google-chrome-stable"
run "$SCRATCH/good.deb" amd64 >/dev/null
assert_eq "fetches the amd64 .deb on amd64" "$(cat "$SCRATCH/url")" "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
out="$(run "$SCRATCH/bad.deb" arm64)"; rc=$?
assert_eq "a different package is refused" "$rc" "1"
assert_file_absent "and never reaches apt" "$SCRATCH/apt-args"
out="$(run "$SCRATCH/good.deb" armhf)"; rc=$?
assert_eq "an unsupported architecture is refused" "$rc" "1"
assert_file_absent "without downloading" "$SCRATCH/url"

summarize_and_exit
