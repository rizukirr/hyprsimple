#!/bin/bash

# Show all Hyprland keybindings in rofi with fuzzy search
#
# NOTE: this parses the plain-text output of `hyprctl binds`, not `hyprctl -j binds`.
# Hyprland 0.56.0 emits malformed JSON for the `binds` endpoint (keys and values are
# misaligned, yielding unquoted tokens like `"keycode": T`), which makes jq bail out
# and leaves rofi with an empty list. The plain-text output is unaffected.

hyprctl binds |
  gawk '
    function modstr(m,   s) {
      s = ""
      if (and(m, 64)) s = s "SUPER + "
      if (and(m, 4))  s = s "CTRL + "
      if (and(m, 8))  s = s "ALT + "
      if (and(m, 1))  s = s "SHIFT + "
      return s
    }
    function val(   s) { s = $0; sub(/^[^:]*:[ \t]*/, "", s); return s }
    # Mouse buttons report as raw evdev codes; name them (as omarchy-menu-keybindings does).
    function keyname(k) {
      if (k == "mouse:272") return "LEFT MOUSE BUTTON"
      if (k == "mouse:273") return "RIGHT MOUSE BUTTON"
      if (k == "mouse:274") return "MIDDLE MOUSE BUTTON"
      return k
    }
    function flush(   d) {
      if (key == "" && keycode != "" && keycode != "0") key = "code:" keycode
      if (key == "") return
      d = desc
      # Lua-backed binds carry no readable dispatcher text, so skip undescribed ones.
      if (d == "" && dispatcher != "__lua")
        d = dispatcher (arg != "" ? " " arg : "")
      if (d == "") return
      printf "%-30s  %s\n", modstr(modmask) keyname(key), d
    }

    /^bind/        { flush(); modmask=0; key=""; keycode=""; desc=""; dispatcher=""; arg=""; next }
    /modmask:/     { modmask = $2 + 0; next }
    /key:/         { key = val(); next }
    /keycode:/     { keycode = val(); next }
    /description:/ { desc = val(); next }
    /dispatcher:/  { dispatcher = val(); next }
    /arg:/         { arg = val(); next }
    END            { flush() }
  ' |
  sort -u |
  rofi -dmenu -p "󰌌" -i -theme ~/.config/rofi/keybindings/style.rasi
