-- Checks the defaults-and-overrides config layout.
-- Run with: lua test/config-split-test.lua

local failures = 0

local function pass(name) print("ok - " .. name) end
local function fail(name, want, got)
  io.stderr:write(("not ok - %s (want %s, got %s)\n"):format(name, tostring(want), tostring(got)))
  failures = failures + 1
end
local function check(name, got, want)
  if got == want then pass(name) else fail(name, want, got) end
end

-- Hyprland provides these at runtime. Under a plain interpreter they must be
-- stubbed or every config file raises on its first call.
local function stub_hl()
  local noop = function() end
  hl = {
    animation = noop, bind = noop, config = noop, curve = noop, device = noop,
    env = noop, exec_cmd = noop, gesture = noop, layer_rule = noop,
    monitor = noop, on = noop, window_rule = noop,

    -- dsp is a namespace, not a function. Indexing a function raises, so every
    -- path the config actually calls has to exist here. Derived with
    -- `grep -rhoE 'hl(\.[a-z_]+)+'` over .config/hypr, which reads full paths
    -- rather than stopping at the first segment.
    dsp = {
      exec_cmd = noop, focus = noop, layout = noop,
      window = { close = noop, drag = noop, float = noop, move = noop, resize = noop },
      workspace = { move = noop },
    },
  }
end

local repo = os.getenv("REPO") or "."

-- ---- the install is reachable as a module root --------------------------

stub_hl()
package.path = repo .. "/?.lua;" .. package.path
local ok, probe = pcall(require, "default.hypr.probe")
check("a module loads from the install root", ok and probe.loaded_from_install, true)

-- ---- vars merges a user table over the defaults --------------------------

local function fresh_vars(user_table)
  for k in pairs(package.loaded) do
    if k == "hypr.vars" or k == "default.hypr.vars" then package.loaded[k] = nil end
  end
  package.preload["hypr.vars"] = user_table and function() return user_table end or nil
  return require("default.hypr.vars")
end

local v = fresh_vars({ terminal = "kitty" })
check("user value wins", v.terminal, "kitty")
check("unset key keeps the default", v.browser,
  "brave --enable-features=UseOzonePlatform --ozone-platform=wayland")

local v2 = fresh_vars(nil)
check("absent user vars yields defaults", v2.terminal, "ghostty")

-- A user file that raises must degrade to the defaults, not kill the session.
for k in pairs(package.loaded) do
  if k == "hypr.vars" or k == "default.hypr.vars" then package.loaded[k] = nil end
end
package.preload["hypr.vars"] = function() error("deliberate syntax error") end
local ok3, v3 = pcall(require, "default.hypr.vars")
check("broken user vars does not raise", ok3, true)
check("broken user vars yields defaults", ok3 and v3.terminal, "ghostty")
package.preload["hypr.vars"] = nil

-- ---- every default module loads under a stubbed hl ----------------------

local modules = {
  "default.hypr.env", "default.hypr.input", "default.hypr.looknfeel",
  "default.hypr.windows", "default.hypr.bindings", "default.hypr.autostart",
  "default.hypr.bindings.media", "default.hypr.bindings.recording",
  "default.hypr.bindings.screenshot", "default.hypr.bindings.system",
  "default.hypr.bindings.window-management", "default.hypr.bindings.workspaces",
}
for _, name in ipairs(modules) do
  stub_hl()
  package.loaded[name] = nil
  local loaded = pcall(require, name)
  check("loads: " .. name, loaded, true)
end

-- A default module must never depend on a user file.
local f = assert(io.open(repo .. "/default/hypr/bindings.lua"))
local body = f:read("a")
f:close()
check("default bindings does not require a user module",
  body:match('require%("hypr%.') == nil, true)

if failures > 0 then
  io.stderr:write(("\n%d check(s) failed\n"):format(failures))
  os.exit(1)
end
print("\nall checks passed")
