#!/bin/bash
# FUNCTIONAL TEST -- apps/claude-code.
# install.sh (needs sudo) runs for real against scratch keyring/sources
# directories, with curl and apt-get stubbed: a key with the documented
# fingerprint is installed and the repository added; any other key is
# refused and nothing is written. The test key is the one already in
# /etc/apt/keyrings (skipped if absent), and a throwaway key stands in for a
# wrong one.
# defaults.sh (no sudo) runs as this user against a scratch HOME.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/testlib.sh
APP="$(cd ../../claude-code && pwd)"

echo "test_claude_code:"

# --- A.1: defaults.sh on a fresh HOME ---
H="$SCRATCH/home"; mkdir -p "$H"
json_get() { python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get(sys.argv[2], "<unset>"))' "$@"; }
HOME="$H" bash "$APP/defaults.sh" >/dev/null
assert_eq "fresh settings get the classic renderer" "$(json_get "$H/.claude/settings.json" tui)" "default"

# --- A.2: other settings kept; idempotent ---
printf '{\n  "theme": "dark"\n}\n' > "$H/.claude/settings.json"
HOME="$H" bash "$APP/defaults.sh" >/dev/null
assert_eq "tui added" "$(json_get "$H/.claude/settings.json" tui)" "default"
assert_eq "theme kept" "$(json_get "$H/.claude/settings.json" theme)" "dark"
before="$(cat "$H/.claude/settings.json")"
out="$(HOME="$H" bash "$APP/defaults.sh" 2>&1)"
assert_eq "a second run changes nothing" "$(cat "$H/.claude/settings.json")" "$before"
assert_eq "and says nothing" "$out" ""

# --- A.3: the user's choice and a broken file are left alone ---
printf '{"tui": "fullscreen"}\n' > "$H/.claude/settings.json"
HOME="$H" bash "$APP/defaults.sh" >/dev/null
assert_eq "an explicit tui is kept" "$(json_get "$H/.claude/settings.json" tui)" "fullscreen"
printf '{broken\n' > "$H/.claude/settings.json"
out="$(HOME="$H" bash "$APP/defaults.sh" 2>&1)"
assert_eq "invalid JSON is not rewritten" "$(cat "$H/.claude/settings.json")" "{broken"
assert_contains "and the user is told" "$out" "isn't valid JSON"

# --- A.4: install.sh ---
assert_failure "an unknown option is refused" bash "$APP/install.sh" --channel=nightly
REAL_KEY=/etc/apt/keyrings/claude-code.asc
if ! sudo -n true 2>/dev/null || [ ! -r "$REAL_KEY" ]; then
  echo "  skip - install.sh checks need sudo and $REAL_KEY"
  summarize_and_exit; exit $?
fi
STUB="$SCRATCH/stub"; mkdir -p "$STUB"
# curl stub: "downloads" whatever file $FAKE_KEY names.
printf '#!/bin/sh\nwhile [ $# -gt 0 ]; do [ "$1" = -o ] && cp "$FAKE_KEY" "$2"; shift; done\n' > "$STUB/curl"
printf '#!/bin/sh\necho "$@" >> %s/apt-calls\n' "$SCRATCH" > "$STUB/apt-get"
chmod +x "$STUB"/*
run_install() {  # run_install <key file> [args...]
  local key="$1"; shift
  rm -rf "$SCRATCH/etc"; mkdir -p "$SCRATCH/etc/keyrings" "$SCRATCH/etc/sources"; : > "$SCRATCH/apt-calls"
  sudo -n env FAKE_KEY="$key" CURL="$STUB/curl" APT_GET="$STUB/apt-get" \
    APT_KEYRINGS_DIR="$SCRATCH/etc/keyrings" APT_SOURCES_DIR="$SCRATCH/etc/sources" \
    bash "$APP/install.sh" "$@" 2>&1
}

out="$(run_install "$REAL_KEY")"; rc=$?
assert_eq "the documented key is accepted" "$rc" "0"
assert_eq "the key is installed byte for byte" "$(sudo -n cmp -s "$REAL_KEY" "$SCRATCH/etc/keyrings/claude-code.asc" && echo same)" "same"
assert_eq "the stable repository line is the documented one" "$(cat "$SCRATCH/etc/sources/claude-code.list")" \
  "deb [signed-by=$SCRATCH/etc/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/stable stable main"
assert_contains "apt-get installs claude-code" "$(cat "$SCRATCH/apt-calls")" "install -y claude-code"

run_install "$REAL_KEY" --channel=latest >/dev/null
assert_contains "--channel=latest uses the latest path and suite" "$(cat "$SCRATCH/etc/sources/claude-code.list")" \
  "claude-code/apt/latest latest main"

# A throwaway key with a different fingerprint.
G="$SCRATCH/gnupg"; mkdir -m 700 "$G"
GNUPGHOME="$G" gpg --batch --quiet --passphrase '' --quick-gen-key "test <test@invalid>" ed25519 sign never 2>/dev/null
GNUPGHOME="$G" gpg --armor --export > "$SCRATCH/wrong.asc" 2>/dev/null
chmod a+r "$SCRATCH/wrong.asc"
out="$(run_install "$SCRATCH/wrong.asc")"; rc=$?
assert_eq "a different key is refused" "$rc" "1"
assert_contains "and the reason is given" "$out" "is not the one Anthropic lists"
assert_eq "no key installed" "$(ls -A "$SCRATCH/etc/keyrings" | wc -l)" "0"
assert_eq "no repository added" "$(ls -A "$SCRATCH/etc/sources" | wc -l)" "0"
assert_not_contains "nothing installed" "$(cat "$SCRATCH/apt-calls")" "claude-code"

summarize_and_exit
