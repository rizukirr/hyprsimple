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

return M
