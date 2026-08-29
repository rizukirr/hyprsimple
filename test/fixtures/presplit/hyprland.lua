-- Hyprland Lua config entrypoint.
-- See https://wiki.hypr.land/Configuring/Start/

local home = os.getenv("HOME") or ""
package.path = home .. "/.config/?.lua;" .. package.path

require("hypr.vars")
require("hypr.monitors")
require("hypr.input")
require("hypr.looknfeel")
require("hypr.windows")
require("hypr.bindings")
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
