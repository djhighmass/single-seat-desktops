#!/bin/bash
# Reads the JSON owf-update-weather.sh writes and prints just the temperature,
# for display via wf-panel's command-output widget (the native "weather"
# widget isn't compiled into this Debian build's wf-shell package).
jq -r '.temp' "$HOME/.local/share/owf/data/data.json" 2>/dev/null || echo "?"
