#!/bin/bash

# Exit 0 if this machine has a battery, which is how hyprsimple decides it is a
# laptop. Used as a condition, not run for output:
#
#   if hyprsimple-hw-battery.sh; then ...
#
# The sysfs root is overridable so both answers can be tested on a machine
# whose own battery presence is fixed.

SYSFS_POWER="${HYPRSIMPLE_SYSFS_POWER:-/sys/class/power_supply}"

compgen -G "$SYSFS_POWER/BAT*" >/dev/null
