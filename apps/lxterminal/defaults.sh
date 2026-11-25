# 10000 lines of scrollback (honours XDG_CONFIG_HOME). Sourced by
# apps/defaults.sh. LXTerminal creates its own config the first time it starts,
# so run this before then.
new_default lxterminal "${XDG_CONFIG_HOME:-$HOME/.config}/lxterminal/lxterminal.conf" $'[general]\nscrollback=10000' \
  "LXTerminal: scrollback set to 10000 lines" \
  ' -- for 10000 lines of scrollback, make [general] read scrollback=10000 (change its scrollback= line, or add one)'
