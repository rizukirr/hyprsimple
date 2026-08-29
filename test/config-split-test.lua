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
    dsp = noop, env = noop, exec_cmd = noop, gesture = noop, layer_rule = noop,
    monitor = noop, on = noop, window_rule = noop,
  }
end

local repo = os.getenv("REPO") or "."

-- ---- the install is reachable as a module root --------------------------

stub_hl()
package.path = repo .. "/?.lua;" .. package.path
local ok, probe = pcall(require, "default.hypr.probe")
check("a module loads from the install root", ok and probe.loaded_from_install, true)

if failures > 0 then
  io.stderr:write(("\n%d check(s) failed\n"):format(failures))
  os.exit(1)
end
print("\nall checks passed")
