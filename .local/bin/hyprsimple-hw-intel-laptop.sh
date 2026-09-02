#!/bin/bash

# Exit 0 if this machine is an Intel laptop new enough for thermald to help.
#
# thermald is Intel-specific and only meaningful from Sandy Bridge (CPU model 42)
# onwards, and only on machines that actually run warm and on battery. Used as a
# condition, not run for output:
#
#   if hyprsimple-hw-intel-laptop.sh; then ...

# Intel CPU
grep -q "GenuineIntel" /proc/cpuinfo || exit 1

# Sandy Bridge or newer. The "model" line is distinct from "model name".
cpu_model=$(grep -m1 '^model[[:space:]]*:' /proc/cpuinfo | cut -d: -f2 | tr -d ' ')
[[ -n $cpu_model ]] || exit 1
(( cpu_model >= 42 )) || exit 1

# Has a battery, i.e. is a laptop
"$(dirname "${BASH_SOURCE[0]}")/hyprsimple-hw-battery.sh" || exit 1

exit 0
