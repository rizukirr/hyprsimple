-- Hyprland Lua config entrypoint.
-- See https://wiki.hypr.land/Configuring/Start/

local home = os.getenv("HOME") or ""
local hyprsimple = os.getenv("HYPRSIMPLE_PATH") or (home .. "/.local/share/hyprsimple")

-- Defaults come from the install and user overrides from ~/.config. ~/.config is
-- first so a user file of the same name wins, and the requires below load the
-- defaults before the user's, so user settings override on shared keys.
package.path = home .. "/.config/?.lua;" .. hyprsimple .. "/?.lua;" .. package.path

-- hyprsimple defaults, from the install.
require("default.hypr.hyprsimple")

-- Your overrides, from ~/.config. Loaded after the defaults so they win.
require("hypr.monitors")
require("hypr.bindings.applications")
require("hypr.looknfeel")
require("hypr.input")
require("hypr.windows")
require("hypr.autostart")

-- Theme overlay loaded last so it wins on shared keys (col.active_border, etc).
-- dofile() because the symlink target changes when the theme switches; require()
-- would cache by module name and miss the swap.
do
  local theme_path = home .. "/.config/hypr/theme-active.lua"
  local f = io.open(theme_path, "r")
  if f then
    f:close()
    dofile(theme_path)
  end
end
