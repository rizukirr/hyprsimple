#!/bin/bash
# Usage: toggle_cpu_mode.sh <on|off>
#   on  - performance mode
#   off - powersave mode

case "$1" in
  on)
    # Reporting the mode only if cpupower set it. Announcing it either way is
    # how a failed governor change looked like a successful one.
    sudo cpupower frequency-set -g performance || { echo "CPU: could not set performance" >&2; exit 1; }
    echo "CPU: performance"
    ;;
  off)
    sudo cpupower frequency-set -g powersave || { echo "CPU: could not set powersave" >&2; exit 1; }
    echo "CPU: powersave"
    ;;
  *)
    echo "Usage: toggle_cpu_mode.sh <on|off>"
    exit 1
    ;;
esac
