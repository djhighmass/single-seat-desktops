#!/bin/bash
apt list --upgradable 2>/dev/null | grep -v '^Listing' | cut -d/ -f1 | paste -sd, -
