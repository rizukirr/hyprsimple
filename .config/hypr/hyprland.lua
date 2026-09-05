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
--
-- Each of these is a file you are invited to edit, and a bare require aborts
-- this whole file on a syntax error or a deleted one: every later require, and
-- the theme overlay at the bottom, then never runs. Measured with a
-- one-character typo in windows.lua, nothing after that line loaded, so the
-- session came up with no theme and no explanation.
--
-- default/hypr/vars.lua already loads your vars.lua with pcall for this reason.
-- These do the same, and name the file that failed.
local failed = {}

local function load_override(module)
  local ok, err = pcall(require, module)
  if not ok then
    -- Single quotes and newlines are removed because the message is passed to
    -- notify-send inside a single-quoted shell argument.
    local message = (tostring(err):gsub("'", ""):gsub("%s+", " "))
    failed[#failed + 1] = message
  end
end

load_override("hypr.monitors")
load_override("hypr.bindings.applications")
load_override("hypr.looknfeel")
load_override("hypr.input")
load_override("hypr.windows")
load_override("hypr.autostart")

-- Reported once the session is up, because a notification cannot be shown
-- while the config is still being parsed.
if #failed > 0 then
  hl.on("hyprland.start", function()
    for _, message in ipairs(failed) do
      hl.exec_cmd(
        "notify-send -u critical 'hyprsimple: a config file did not load' "
          .. "'" .. message .. "'"
      )
    end
  end)
end

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
