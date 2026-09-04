-- Programs hyprsimple launches. A user overrides any of these by returning a
-- table of the same keys from ~/.config/hypr/vars.lua, which is merged over
-- these defaults. Adding a key here reaches every user without a migration.
local M = {}
M.terminal = "ghostty"
M.fileManager = "nautilus"
M.menu = os.getenv("HOME") .. "/.config/rofi/launcher/launcher.sh"
M.powermenu = os.getenv("HOME") .. "/.config/rofi/powermenu/powermenu.sh"
M.browser = "brave --enable-features=UseOzonePlatform --ozone-platform=wayland"
M.colorPicker = "hyprpicker"

-- pcall so a syntax error in the user's file degrades to these defaults rather
-- than killing the session. hypr.vars and default.hypr.vars are distinct module
-- names, so this is not a cycle.
local ok, user = pcall(require, "hypr.vars")
if ok and type(user) == "table" then
  for k, v in pairs(user) do
    M[k] = v
  end
end

-- This file is install-owned and reaches every machine on the next update, but
-- ~/.config/hypr/bindings/applications.lua is user-owned and does not. So
-- removing a key here breaks any older bindings file that still reads it, and
-- not in a contained way: exec_cmd raises "expected string, got nil", which
-- fails the whole config and takes every later binding in the file with it.
-- Dropping M.notes and M.androidstudio in #62 did exactly that.
--
-- An unknown key now answers with a command that says which key is missing and
-- where to set it, so an out-of-date bindings file loses one key rather than
-- all of them. This also covers a plain typo in a hand-written binding.
setmetatable(M, {
  __index = function(_, key)
    return "notify-send -u critical 'hyprsimple' "
      .. "'This key runs vars." .. key .. ", which hyprsimple does not set. "
      .. "Bind a program directly in ~/.config/hypr/bindings/applications.lua, "
      .. "or set " .. key .. " in ~/.config/hypr/vars.lua.'"
  end,
})

return M
