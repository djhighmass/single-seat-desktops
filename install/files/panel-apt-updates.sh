#!/bin/bash
# Read-only: counts upgradable packages from apt's current (possibly stale)
# package lists. Does not run apt-get update or upgrade - those need sudo,
# so run them yourself in a terminal when you want to actually apply updates.
n="$(apt list --upgradable 2>/dev/null | grep -vc '^Listing')"
if [ "$n" -gt 0 ]; then
  echo "⬆ ${n}"
else
  echo "✓ up to date"
fi
