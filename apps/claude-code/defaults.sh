# The classic renderer, so the terminal's own scrollback keeps working
# (https://code.claude.com/docs/en/fullscreen; honours CLAUDE_CONFIG_DIR).
# Sourced by apps/defaults.sh.
new_default claude "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" '{"tui": "default"}' \
  "Claude Code: classic renderer set" \
  ' -- if it has no "tui" and you want the classic renderer, add "tui": "default"'
