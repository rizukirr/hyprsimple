#!/bin/bash
# Takes a real pre-split config from main, migrates it, and loads the result
# through the actual entrypoint. Every other suite passed against a migration
# that broke here, because none of them loaded a migrated config for real.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }

command -v lua >/dev/null || { echo "lua is required" >&2; exit 2; }

# The install, and a user config exactly as main shipped it.
mkdir -p "$TMP/install" "$TMP/home/.config"
git -C "$REPO" archive HEAD | tar -x -C "$TMP/install"
mkdir -p "$TMP/home/.config/hypr/bindings"
for rel in hyprland.lua vars.lua monitors.lua input.lua looknfeel.lua windows.lua \
           autostart.lua bindings.lua bindings/applications.lua bindings/media.lua \
           bindings/recording.lua bindings/screenshot.lua bindings/system.lua \
           bindings/window-management.lua bindings/workspaces.lua; do
  git -C "$REPO" show "main:.config/hypr/$rel" >"$TMP/home/.config/hypr/$rel"
done

cat >"$TMP/load.lua" <<'LUA'
local counts = {}
local function rec(k) return function(...) counts[k] = (counts[k] or 0) + 1 end end
local function ns(ks) local t = {} for _, k in ipairs(ks) do t[k] = rec(k) end return t end
hl = {
  animation = rec("animation"), bind = rec("bind"), config = rec("config"),
  curve = rec("curve"), device = rec("device"), env = rec("env"),
  exec_cmd = rec("exec_cmd"), gesture = rec("gesture"), layer_rule = rec("layer_rule"),
  monitor = rec("monitor"), on = rec("on"), window_rule = rec("window_rule"),
  dsp = { exec_cmd = rec("d"), focus = rec("d"), layout = rec("d"),
          window = ns({"close","drag","float","move","resize"}),
          workspace = ns({"move"}) },
}
local root = assert(os.getenv("ROOT"))
local install = assert(os.getenv("INSTALL"))
os.getenv = (function(o) return function(k)
  if k == "HOME" then return root end
  if k == "HYPRSIMPLE_PATH" then return install end
  return o(k)
end end)(os.getenv)
package.path = root .. "/.config/?.lua;" .. install .. "/?.lua;" .. package.path
dofile(root .. "/.config/hypr/hyprland.lua")
print(counts.window_rule or 0)
LUA

before=$(ROOT="$TMP/home" INSTALL="$TMP/install" lua "$TMP/load.lua" 2>"$TMP/err_before")
if [[ -n $before ]]; then pass "a pre-split config loads"; else fail "a pre-split config loads: $(head -1 "$TMP/err_before")"; fi

HOME="$TMP/home" HYPRSIMPLE_PATH="$TMP/install" bash "$REPO/migrations/1787992467.sh" >/dev/null 2>&1

after=$(ROOT="$TMP/home" INSTALL="$TMP/install" lua "$TMP/load.lua" 2>"$TMP/err_after")
if [[ -n $after ]]; then pass "a migrated config still loads"; else fail "a migrated config still loads: $(head -1 "$TMP/err_after")"; fi

if [[ -n $before && "$before" == "$after" ]]; then
  pass "window rules are not duplicated"
else
  fail "window rules are not duplicated (before=$before after=$after)"
fi

if ((failures > 0)); then printf '\n%s check(s) failed\n' "$failures" >&2; exit 1; fi
printf '\nall checks passed\n'
