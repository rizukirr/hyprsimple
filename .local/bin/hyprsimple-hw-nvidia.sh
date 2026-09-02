#!/bin/bash

# Exit 0 if this machine has an NVIDIA GPU. Used as a condition, not run for
# output:
#
#   if hyprsimple-hw-nvidia.sh; then ...
#
# Answers only the yes or no. install.sh keeps its own capture of the model
# string, because it regex-matches that string to decide which driver a card
# needs, and a boolean cannot carry it.

lspci 2>/dev/null | grep -qi 'nvidia'
