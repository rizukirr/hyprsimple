#!/bin/bash

# Reset waybar's config to hyprsimple's defaults, keeping the one setting people
# actually change. hyprsimple-refresh-config.sh keeps a backup and prints a diff,
# so everything else replaced here is recoverable.

WAYBAR_CONFIG="$HOME/.config/waybar/config.jsonc"

position=$(sed -nE 's/.*"position"[[:space:]]*:[[:space:]]*"(top|bottom|left|right)".*/\1/p' "$WAYBAR_CONFIG" 2>/dev/null | head -n 1)

"$HOME/.local/bin/hyprsimple-refresh-config.sh" waybar/config.jsonc
"$HOME/.local/bin/hyprsimple-refresh-config.sh" waybar/style.css

[[ -n $position ]] && sed -i -E "s/(\"position\"[[:space:]]*:[[:space:]]*\")[a-z]+(\")/\1${position}\2/" "$WAYBAR_CONFIG"

"$HOME/.local/bin/hyprsimple-restart-waybar.sh"
