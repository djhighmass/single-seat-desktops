#!/bin/bash
free -m | awk '/^Mem:/ {printf "%.1fG free\n", $7/1024}'
