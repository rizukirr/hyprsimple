-- Bindings are install-owned JSON data, loaded before the user's overrides.
local home = os.getenv("HOME")
local file = home .. "/.local/state/hyprsimple/plugins/bindings.json"
local present = io.open(file, "r")
if not present then return end
present:close()
local function quote(value) return "'" .. value:gsub("'", "'\\''") .. "'" end
local function diagnostic(message) io.stderr:write("hyprsimple plugins: " .. message .. "\n") end
local filter = [[
  def text: type == "string" and length > 0 and (test("[\u0000-\u001f\u007f]") | not);
  if length != 1 then error("expected one bindings document") else .[0] end |
  if type != "object" or keys != ["bindings","schemaVersion"] or .schemaVersion != 1 or (.bindings | type) != "array"
  then error("invalid bindings document") else .bindings[] end |
  if type == "object" and keys == ["action","description","key","pluginId"] and
     (.pluginId | text and test("^[a-z][a-z0-9]*([.-][a-z0-9]+)*$") and (startswith("hyprsimple.") | not)) and
     (.key | text and test("^((SUPER|SHIFT|CTRL|ALT|MOD[1-5]) \\+ )*([A-Za-z0-9_]+|code:[0-9]+)$")) and
     (.description | text) and .action == "toggle-panel"
  then [.pluginId,.key,.description] | join("\t") else "!invalid binding" end
]]
local unique = '[.[] | if length == 2 then .[0] else .[0][:-1] end | select(length > 0)] | length == (unique | length)'
local pipe = io.popen("jq --stream -s -e " .. quote(unique) .. " -- " .. quote(file) .. " >/dev/null 2>&1 && jq -r -s " .. quote(filter) .. " -- " .. quote(file) .. " 2>/dev/null", "r")
if not pipe then diagnostic("cannot read bindings"); return end
local rows = pipe:read("a")
local ok = pipe:close()
if not ok then diagnostic("ignoring malformed bindings document"); return end
local bar = require("default.hypr.vars").bar
for row in rows:gmatch("[^\n]+") do
  local id, key, description = row:match("^([^\t]+)\t([^\t]+)\t([^\t]+)$")
  if id then
    local command = "qs -p " .. quote(bar) .. " ipc call bar toggle " .. quote("plugin:" .. id)
    local bound, reason = pcall(function()
      hl.bind(key, hl.dsp.exec_cmd(command), { description = description })
    end)
    if not bound then diagnostic("ignoring binding for " .. id .. ": " .. tostring(reason)) end
  else diagnostic("ignoring malformed binding") end
end
