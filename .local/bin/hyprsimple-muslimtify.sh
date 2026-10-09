#!/bin/bash
# Compatibility aliases manage the external plugin, retaining packages and settings.
set -euo pipefail
manager="$HOME/.local/bin/hyprsimple-plugin"
root="${HYPRSIMPLE_PLUGIN_ROOT:-$HOME/.local/share/hyprsimple-plugins}"
repo='https://github.com/muslimtify-org/muslimtify-hyprsimple.git'
[[ $# == 1 ]] || { echo "Usage: $(basename "$0") add|remove" >&2; exit 1; }
case "$1" in
  add)
    "$manager" validate
    if [[ -d $root/muslimtify ]]; then
      "$manager" enable muslimtify
    else
      "$manager" install "$repo"
    fi
    if ! muslimtify daemon status; then
      echo 'Muslimtify daemon is not running. Run: muslimtify daemon install && muslimtify-add' >&2
      exit 1
    fi
    ;;
  remove)
    "$manager" validate
    [[ ! -d $root/muslimtify ]] || "$manager" remove muslimtify
    ;;
  *) echo "Usage: $(basename "$0") add|remove" >&2; exit 1 ;;
esac
