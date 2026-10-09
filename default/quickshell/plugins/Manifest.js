.pragma library

function object(value) { return value !== null && typeof value === "object" && !Array.isArray(value) }
function fields(value, allowed) { return object(value) && Object.keys(value).every(k => allowed.indexOf(k) !== -1) }
function exact(value, allowed) { return fields(value, allowed) && Object.keys(value).length === allowed.length }
function text(value) { return typeof value === "string" && value.length > 0 && !/[\x00-\x1f\x7f]/.test(value) }
function id(value) { return text(value) && /^[a-z][a-z0-9]*([.-][a-z0-9]+)*$/.test(value) && !value.startsWith("hyprsimple.") }
function placement(value) { return ["left", "center", "right"].indexOf(value) !== -1 }
function path(value) { return text(value) && value.split("/").every(p => p !== "" && p !== "." && p !== "..") }
function unique(values) { return new Set(values).size === values.length }
function packages(value) { return Array.isArray(value) && value.every(p => typeof p === "string" && /^[a-z0-9][a-z0-9@._+-]*$/.test(p)) && unique(value) }
function optional(value, key, check) { return !(key in value) || check(value[key]) }

function config(value) {
    if (!exact(value, ["schemaVersion", "plugins"]) || value.schemaVersion !== 1 || !object(value.plugins)) throw Error("invalid plugin config")
    Object.keys(value.plugins).forEach(key => {
        const c = value.plugins[key]
        if (!id(key) || !exact(c, ["enabled", "placement", "settings", "commit"]) || typeof c.enabled !== "boolean" || !placement(c.placement) || !object(c.settings) || typeof c.commit !== "string" || !/^([0-9a-f]{40}|[0-9a-f]{64})?$/.test(c.commit)) throw Error("invalid config for " + key)
    })
    return value.plugins
}

function validate(record) {
    const m = record.manifest
    if (record.error) throw Error(record.error)
    if (!fields(m, ["schemaVersion", "apiVersion", "id", "name", "version", "entryPoints", "placement", "dependencies", "lifecycle", "bindings", "panelAliases"]) || m.schemaVersion !== 1 || m.apiVersion !== 1 || !id(m.id) || m.id !== record.id || !text(m.name) || !text(m.version)) throw Error("invalid manifest")
    if (!fields(m.entryPoints, ["service", "widget", "panel"]) || Object.keys(m.entryPoints).length === 0 || !Object.values(m.entryPoints).every(p => path(p) && p.endsWith(".qml"))) throw Error("invalid entry points")
    if (!optional(m, "placement", placement) || !optional(m, "dependencies", d => fields(d, ["packages", "aur"]) && Object.values(d).every(packages)) || !optional(m, "lifecycle", l => fields(l, ["enable", "disable"]) && Object.values(l).every(path))) throw Error("invalid optional manifest fields")
    if (!optional(m, "bindings", b => Array.isArray(b) && b.every(v => exact(v, ["key", "description", "action"]) && text(v.key) && text(v.description) && v.action === "toggle-panel")) || !optional(m, "panelAliases", a => Array.isArray(a) && a.every(v => text(v) && /^[a-z][a-z0-9-]*$/.test(v)) && unique(a))) throw Error("invalid bindings or aliases")
    if (((m.bindings || []).length || (m.panelAliases || []).length) && !m.entryPoints.panel) throw Error("panel required for bindings or aliases")
    Object.values(m.entryPoints).concat(Object.values(m.lifecycle || {})).forEach(p => {
        const resolved = record.paths[p]
        if (!text(resolved) || !resolved.startsWith(record.base + "/")) throw Error("escaping or missing path: " + p)
    })
    return m
}

function url(path) { return "file://" + path.split("/").map(encodeURIComponent).join("/") }

// Arguments are passed separately to Bash. No manifest value becomes command text.
// Filesystem checks happen before Qt reads any external QML, including manual installations.
function catalogCommand(root, configPath, core) {
    return ["bash", "-c", `
set -euo pipefail
root=$1 config=$2 core=$3
unique_json() {
    jq -s -e 'length == 1' "$1" >/dev/null &&
    jq --stream -s -e '[.[] | if length == 2 then .[0] else .[0][:-1] end | select(length > 0)] | length == (unique | length)' "$1" >/dev/null
}
[[ ! -L $root ]] || { echo 'plugin root is a symlink' >&2; exit 1; }
base=$(realpath -m -- "$root")
core=$(realpath -m -- "$core")
[[ $base != "$core" && $base != "$core/"* ]] || { echo 'plugin root is inside core' >&2; exit 1; }
if [[ -e $config || -L $config ]]; then
    [[ -f $config && ! -L $config ]] && unique_json "$config" || { echo 'invalid or duplicate config' >&2; exit 1; }
    jq -c '{config:.,records:[]}' "$config"
else
    echo '{"config":{"schemaVersion":1,"plugins":{}},"records":[]}'
fi
for dir in "$root"/*; do
    [[ -e $dir || -L $dir ]] || continue
    id=$(basename -- "$dir")
    manifest="$dir/manifest.json"
    if [[ ! -d $dir || -L $dir || ! -f $manifest || -L $manifest ]] || ! unique_json "$manifest"; then
        jq -cn --arg id "$id" '{id:$id,error:"invalid directory or manifest (including duplicate fields)"}'
        continue
    fi
    plugin_base=$(realpath -e -- "$dir")
    paths='{}'
    while IFS= read -r path; do
        resolved=$(realpath -e -- "$dir/$path" 2>/dev/null) || resolved=''
        if [[ $resolved != "$plugin_base/"* || ! -f $resolved ]]; then resolved=''; fi
        paths=$(jq -cn --argjson paths "$paths" --arg path "$path" --arg resolved "$resolved" '$paths + {($path):$resolved}')
    done < <(jq -r '(.entryPoints,.lifecycle) | objects | .[] | strings' "$manifest")
    jq -c --arg id "$id" --arg base "$plugin_base" --argjson paths "$paths" '{id:$id,base:$base,paths:$paths,manifest:.}' "$manifest"
done
`, "hyprsimple-plugin-catalog", root, configPath, core]
}
