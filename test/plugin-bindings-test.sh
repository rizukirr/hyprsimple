#!/bin/bash
# Run the real Lua reader with jq and stub Hyprland, inside a disposable HOME.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT
mkdir -p "$TMP/home/.local/state/hyprsimple/plugins"
STATE="$TMP/home/.local/state/hyprsimple/plugins/bindings.json"
cat >"$TMP/check.lua" <<'LUA'
package.path = os.getenv("REPO") .. "/?.lua;" .. package.path
local calls = {}
hl = {
  dsp = {exec_cmd = function(command) return command end},
  bind = function(key, command, options)
    if key == "SUPER + B" then error("fixture rejected binding") end
    calls[#calls+1] = {key=key,command=command,description=options.description}
  end,
}
require("default.hypr.plugins")
if os.getenv("EMPTY") then assert(#calls == 0); print("ok - malformed or missing document ignored"); return end
assert(#calls == 2, "valid bindings survive malformed rows and binding exceptions")
assert(calls[1].key == "SUPER + P")
assert(calls[1].description == "Open 'quoted' $(touch /tmp/do-not-run)")
assert(calls[2].key == "SUPER + SHIFT + X")
local quoted = "'" .. os.getenv("HYPRSIMPLE_PATH"):gsub("'", "'\\''") .. "/default/quickshell'"
assert(calls[1].command == "qs -p " .. quoted .. " ipc call bar toggle 'plugin:example'")
assert(calls[2].command:match("'plugin:second'$"))
-- Execute only against an argv-recording qs stub to prove shell quoting.
assert(os.execute(calls[1].command))
print("ok - declarative bindings, namespace, escaping and failure containment")
LUA
mkdir -p "$TMP/bin"
cat >"$TMP/bin/qs" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" >"$ARGV_LOG"
STUB
chmod +x "$TMP/bin/qs"
cat >"$STATE" <<'JSON'
{"schemaVersion":1,"bindings":[
{"pluginId":"example","key":"SUPER + P","description":"Open 'quoted' $(touch /tmp/do-not-run)","action":"toggle-panel"},
{"pluginId":"example","key":"SUPER, P","description":"wrong syntax","action":"toggle-panel"},
{"pluginId":"example","key":"SUPER + B","description":"bind raises","action":"toggle-panel"},
{"pluginId":"evil; touch /tmp/no","key":"SUPER + E","description":"invalid id","action":"toggle-panel"},
{"pluginId":"example","key":"SUPER + E","description":"wrong action","action":"exec"},
{"pluginId":"example","key":"SUPER + E","description":"extra field","action":"toggle-panel","command":"bad"},
{"pluginId":"example","key":"SUPER + E","description":"newline\ninjected","action":"toggle-panel"},
{"pluginId":"second","key":"SUPER + SHIFT + X","description":"Second","action":"toggle-panel"}
]}
JSON
run() {
  HOME="$TMP/home" HYPRSIMPLE_PATH="$TMP/core ' \$(touch $TMP/escaped)" REPO="$REPO" \
    PATH="$TMP/bin:$PATH" ARGV_LOG="$TMP/argv" lua "$TMP/check.lua" 2>"$TMP/errors"
}
run
[[ $(sed -n '2p' "$TMP/argv") == "$TMP/core ' \$(touch $TMP/escaped)/default/quickshell" ]]
[[ $(sed -n '7p' "$TMP/argv") == 'plugin:example' ]]
[[ ! -e $TMP/escaped ]]
grep -q 'ignoring malformed binding' "$TMP/errors"
grep -q 'ignoring binding for example' "$TMP/errors"
for data in '{' '{"schemaVersion":2,"bindings":[]}' '{"schemaVersion":1,"bindings":{}}' '{"schemaVersion":1,"bindings":[]} {"schemaVersion":1,"bindings":[]}' '{"schemaVersion":1,"schemaVersion":1,"bindings":[]}' ; do
  printf '%s\n' "$data" >"$STATE"
  EMPTY=1 run
  grep -q 'ignoring malformed bindings document' "$TMP/errors"
done
rm "$STATE"
EMPTY=1 run
# Core bindings are read before the user files. Exercise the actual root config.
HOME="$TMP/home" REPO="$REPO" lua - <<'LUA'
local repo = os.getenv("REPO")
package.path = repo .. "/?.lua;" .. package.path
local f = assert(io.open(repo .. "/.config/hypr/hyprland.lua"))
local source = f:read("a")
f:close()
assert(source:find('require%("default.hypr.hyprsimple"%)') < source:find('load_override%("hypr.bindings.applications"%)'))
local g = assert(io.open(repo .. "/default/hypr/hyprsimple.lua"))
assert(g:read("a"):find('require%("default.hypr.plugins"%)'))
g:close()
print("ok - core plugin bindings precede user overrides")
LUA
