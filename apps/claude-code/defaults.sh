#!/bin/bash
# Our default settings for Claude Code, for the user running this (not root):
# the classic renderer ("tui": "default" in ~/.claude/settings.json). Claude
# Code's fullscreen renderer takes over the terminal window, so the terminal's
# own scrollback (scrollbar, Shift+PageUp, mouse wheel) stops working.
# An explicit "tui" you've set is kept, and a settings file that isn't valid
# JSON is left alone.
set -uo pipefail
APPS_DIR="${APPS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/common.sh
source "$APPS_DIR/lib/common.sh"
[ "$(id -u)" -ne 0 ] || die "run this as the user it's for, not as root"
command -v python3 >/dev/null || { warn "python3 not found -- Claude Code defaults skipped"; exit 0; }

SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
python3 -I - "$SETTINGS" <<'PY'
import json, os, sys
path = sys.argv[1]
try:
    with open(path) as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
except ValueError:
    print(f"!! {path} isn't valid JSON -- left alone", file=sys.stderr)
    sys.exit(0)
if not isinstance(data, dict) or "tui" in data:
    sys.exit(0)
data["tui"] = "default"
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
print(f"Claude Code: classic renderer set, so terminal scrollback works ({path})")
PY
