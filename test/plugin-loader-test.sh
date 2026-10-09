#!/bin/bash
# Isolated real QML runtime. No core desktop services or windows are started.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT
command -v qs >/dev/null || { echo 'SKIP: Quickshell is required for the offscreen loader harness'; exit 77; }
mkdir -p "$TMP/home/.config/hyprsimple" "$TMP/runtime" "$TMP/plugins" "$TMP/shell"
chmod 700 "$TMP/runtime"
for dir in plugins theme bar components panels system launcher notifications; do ln -s "$REPO/default/quickshell/$dir" "$TMP/shell/$dir"; done
cat >"$TMP/plugins/placeholder" <<'DATA'
invalid directory
DATA
create_plugin() {
  local id=$1 entries=$2
  mkdir -p "$TMP/plugins/$id"
  jq -n --arg id "$id" --argjson entries "$entries" '{schemaVersion:1,apiVersion:1,id:$id,name:$id,version:"1",entryPoints:$entries}' >"$TMP/plugins/$id/manifest.json"
}
create_plugin example '{"service":"Service.qml","widget":"Widget.qml","panel":"Panel.qml"}'
jq '.panelAliases=["external"]' "$TMP/plugins/example/manifest.json" >"$TMP/m"
mv "$TMP/m" "$TMP/plugins/example/manifest.json"
cat >"$TMP/plugins/example/Service.qml" <<'QML'
import QtQuick
import Hyprsimple
QtObject {
    required property var context
    property int calls: 0
    Component.onCompleted: { if (context.screen !== null || context.bar !== null) throw Error("service monitor leak"); console.log("SERVICE-ONCE") }
}
QML
cat >"$TMP/plugins/example/Widget.qml" <<'QML'
import QtQuick
import Hyprsimple
Capsule {
    required property var context
    property color observed: context.theme.accent
    StatusButton { label: context.settings.label; onClicked: context.togglePanel() }
    Component.onCompleted: { context.service.calls++; console.log("WIDGET", context.screen.name, context.settings.label) }
}
QML
cat >"$TMP/plugins/example/Panel.qml" <<'QML'
import QtQuick
import Hyprsimple
Item {
    required property var context
    // Compile every reusable export and its relative dependencies without opening a window.
    Component { StyledText {} }
    Component { TextField {} }
    Component { SectionLabel {} }
    Component { Meter {} }
    Component { IconButton {} }
    Component { TextButton {} }
    Component { Segmented {} }
    Component { Toggle {} }
    Component { Slider {} }
    Component { Dropdown {} }
    Component { Icon {} }
    Component { CAnim {} }
    Component { Anim {} }
}
QML
create_plugin broken '{"service":"Service.qml","widget":"Widget.qml","panel":"Panel.qml"}'
printf 'import QtQuick\nMissingType {}\n' >"$TMP/plugins/broken/Service.qml"
printf 'import QtQuick\nItem { required property var context; Component.onCompleted: console.log("DEPENDENT-MUST-NOT-LOAD") }\n' >"$TMP/plugins/broken/Widget.qml"
cp "$TMP/plugins/broken/Widget.qml" "$TMP/plugins/broken/Panel.qml"
create_plugin bad-widget '{"widget":"Widget.qml"}'
printf 'import QtQuick\nMissingType {}\n' >"$TMP/plugins/bad-widget/Widget.qml"
create_plugin missing-context '{"widget":"Widget.qml"}'
printf 'import QtQuick\nItem {}\n' >"$TMP/plugins/missing-context/Widget.qml"
create_plugin escape '{"widget":"Widget.qml"}'
cp "$TMP/plugins/broken/Widget.qml" "$TMP/outside.qml"
ln -s "$TMP/outside.qml" "$TMP/plugins/escape/Widget.qml"
create_plugin traversal '{"widget":"../outside.qml"}'
create_plugin manifest-link '{"widget":"Widget.qml"}'
cp "$TMP/plugins/manifest-link/manifest.json" "$TMP/manifest.json"
rm "$TMP/plugins/manifest-link/manifest.json"
ln -s "$TMP/manifest.json" "$TMP/plugins/manifest-link/manifest.json"
create_plugin unsupported '{"widget":"Widget.qml"}'
cp "$TMP/plugins/broken/Widget.qml" "$TMP/plugins/unsupported/Widget.qml"
jq '.apiVersion=2' "$TMP/plugins/unsupported/manifest.json" >"$TMP/m"
mv "$TMP/m" "$TMP/plugins/unsupported/manifest.json"
for id in alias-a alias-b; do
  create_plugin "$id" '{"panel":"Panel.qml"}'
  cp "$TMP/plugins/example/Panel.qml" "$TMP/plugins/$id/Panel.qml"
  jq '.panelAliases=["duplicate"]' "$TMP/plugins/$id/manifest.json" >"$TMP/m"
  mv "$TMP/m" "$TMP/plugins/$id/manifest.json"
done
create_plugin duplicate '{"widget":"Widget.qml"}'
printf '{"schemaVersion":1,"apiVersion":1,"id":"duplicate","id":"duplicate","name":"x","version":"1","entryPoints":{"widget":"Widget.qml"}}\n' >"$TMP/plugins/duplicate/manifest.json"
cp "$TMP/plugins/broken/Widget.qml" "$TMP/plugins/duplicate/Widget.qml"
for id in unknown-field invalid-deps lifecycle-escape mismatched-id duplicate-settings-object disabled; do
  create_plugin "$id" '{"widget":"Widget.qml"}'
  cp "$TMP/plugins/broken/Widget.qml" "$TMP/plugins/$id/Widget.qml"
done
jq '.extra=true' "$TMP/plugins/unknown-field/manifest.json" >"$TMP/m"
mv "$TMP/m" "$TMP/plugins/unknown-field/manifest.json"
jq '.dependencies={packages:["unsafe;command"]}' "$TMP/plugins/invalid-deps/manifest.json" >"$TMP/m"
mv "$TMP/m" "$TMP/plugins/invalid-deps/manifest.json"
jq '.lifecycle={enable:"enable.sh"}' "$TMP/plugins/lifecycle-escape/manifest.json" >"$TMP/m"
mv "$TMP/m" "$TMP/plugins/lifecycle-escape/manifest.json"
ln -s "$TMP/outside.qml" "$TMP/plugins/lifecycle-escape/enable.sh"
jq '.id="different"' "$TMP/plugins/mismatched-id/manifest.json" >"$TMP/m"
mv "$TMP/m" "$TMP/plugins/mismatched-id/manifest.json"
printf '{"schemaVersion":1,"apiVersion":1,"id":"duplicate-settings-object","name":"x","version":"1","entryPoints":{"widget":"Widget.qml"},"dependencies":{"packages":[]},"dependencies":{"aur":[]}}\n' >"$TMP/plugins/duplicate-settings-object/manifest.json"
ln -s "$TMP/plugins/example" "$TMP/plugins/directory-link"
# Internal entry symlinks are allowed and are loaded through their canonical URL.
mv "$TMP/plugins/example/Widget.qml" "$TMP/plugins/example/WidgetImpl.qml"
ln -s WidgetImpl.qml "$TMP/plugins/example/Widget.qml"
jq -n --argjson ids '["example","broken","bad-widget","missing-context","escape","traversal","manifest-link","unsupported","alias-a","alias-b","duplicate","unknown-field","invalid-deps","lifecycle-escape","mismatched-id","duplicate-settings-object","directory-link","disabled","absent"]' '{schemaVersion:1,plugins:($ids | map({key:.,value:{enabled:(. != "disabled"),placement:"left",settings:{label:"configured"},commit:""}}) | from_entries)}' >"$TMP/home/.config/hyprsimple/plugins.json"
printf '{"accent":"#123456"}\n' >"$TMP/theme.json"
cat >"$TMP/shell/shell.qml" <<'QML'
import QtQuick
import Quickshell
import Quickshell.Io
import qs.plugins
import qs.theme
import qs.components
import qs.bar
import qs.panels
ShellRoot {
    id: root
    property var errors: []
    Registry { id: registry; onFailed: (id, reason) => root.errors.push(id) }
    Item {
        id: bar1
        property var screen: ({name:"one"})
        property string openPanel: ""
        function toggle(name) { openPanel = openPanel === name ? "" : name; if (openPanel) bar2.openPanel = "" }
        PluginSlot { id: slot1; registry: registry; bar: bar1; placement: "left" }
    }
    Item {
        id: bar2
        property var screen: ({name:"two"})
        property string openPanel: ""
        function toggle(name) { openPanel = openPanel === name ? "" : name; if (openPanel) bar1.openPanel = "" }
        PluginSlot { id: slot2; registry: registry; bar: bar2; placement: "left" }
    }
    function require(value, message) { if (!value) { console.error("HARNESS-FAIL", message); Qt.quit(); throw Error(message) } }
    property bool tested: false
    property var first: null
    property var second: null
    Timer {
        interval: 100
        running: registry.ready
        repeat: true
        onTriggered: {
            if (root.tested) {
                if (String(root.first.widget.observed) !== "#abcdef") return
                require(root.second.widget.observed === root.first.widget.observed, "theme sharing")
                console.log("HARNESS-PASS")
                Qt.quit()
                return
            }
            require(registry.plugins.length === 3, "invalid plugins rejected and broken service excluded")
            require(registry.services.example.calls === 2, "service shared once across screens")
            require(registry.resolvePanel("external") === "plugin:example", "alias resolution")
            require(registry.resolvePanel("power") === "power", "built-in panel resolution")
            const repeater1 = slot1.children.find(child => typeof child.itemAt === "function")
            const repeater2 = slot2.children.find(child => typeof child.itemAt === "function")
            root.first = Array.from({length:repeater1.count}, (_, i) => repeater1.itemAt(i)).find(host => host.modelData.id === "example")
            root.second = Array.from({length:repeater2.count}, (_, i) => repeater2.itemAt(i)).find(host => host.modelData.id === "example")
            require(root.first.widget !== null && root.first.panel !== null, "external dynamic imports")
            require(root.first.widget.context !== root.second.widget.context, "per-screen contexts")
            require(root.first.widget.context.settings.label === "configured", "settings")
            const widgetWidth = root.first.width
            root.first.widget.visible = false
            require(root.first.width === 0 && slot1.implicitWidth === 0, "hidden widget takes no space")
            root.first.widget.visible = true
            require(root.first.width === widgetWidth, "widget visibility restored")
            root.first.widget.context.togglePanel()
            require(bar1.openPanel === "plugin:example" && root.first.widget.context.panelOpen, "namespaced toggle")
            root.second.widget.context.togglePanel()
            require(bar1.openPanel === "" && bar2.openPanel === "plugin:example", "cross-monitor owner")
            root.second.widget.context.closePanel()
            require(bar2.openPanel === "", "close panel")
            const rejected = ["broken","bad-widget","missing-context","escape","traversal","manifest-link","unsupported","alias-a","alias-b","duplicate","unknown-field","invalid-deps","lifecycle-escape","mismatched-id","duplicate-settings-object","directory-link","absent"]
            rejected.forEach(id => require(root.errors.indexOf(id) !== -1, "diagnostic for " + id))
            root.tested = true
            changeTheme.running = true
        }
    }
    Process { id: changeTheme; command: ["bash", "-c", "printf '%s\\n' '{\"accent\":\"#abcdef\"}' > \"$QS_THEME_FILE\""] }
}
QML
# Change the theme via an argv-safe process, with only fixture files in scope.
run_harness() {
  HOME="$TMP/home" HYPRSIMPLE_PLUGIN_ROOT="$TMP/plugins" HYPRSIMPLE_PATH="$REPO" \
    XDG_RUNTIME_DIR="$TMP/runtime" XDG_CONFIG_HOME="$TMP/home/.config" XDG_CACHE_HOME="$TMP/home/.cache" \
    QS_THEME_FILE="$TMP/theme.json" QML_IMPORT_PATH="$REPO/default/quickshell" QT_QPA_PLATFORM=offscreen \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$TMP/no-bus" XDG_DATA_HOME="$TMP/home/.local/share" XDG_STATE_HOME="$TMP/home/.local/state" \
    env -u WAYLAND_DISPLAY -u DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE timeout 20 qs -p "$TMP/shell" --no-color >"$TMP/log" 2>&1
}
if ! run_harness; then cat "$TMP/log"; exit 1; fi
cat "$TMP/log"
grep -q 'HARNESS-PASS' "$TMP/log"
if grep -q 'HARNESS-FAIL\|DEPENDENT-MUST-NOT-LOAD' "$TMP/log"; then exit 1; fi
[[ $(grep -c 'SERVICE-ONCE' "$TMP/log") == 1 ]]
echo 'ok - external imports, validation, shared service, contexts, theme changes, panel operations and failure containment'
echo 'LIMITATION: offscreen bars model owner coordination. Real layer-shell placement and compositor focus require a Hyprland session.'

# Malformed config suppresses external code but leaves the core harness alive.
cat >"$TMP/shell/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.plugins
ShellRoot {
    id: root
    property int failures: 0
    Registry { id: registry; onFailed: root.failures++ }
    Timer {
        interval: 50
        running: registry.ready
        onTriggered: {
            if (registry.plugins.length !== 0 || root.failures === 0) console.error("HARNESS-FAIL invalid config")
            else console.log("CONFIG-REJECTED")
            Qt.quit()
        }
    }
}
QML
for config in \
  '{"schemaVersion":2,"plugins":{}}' \
  '{"schemaVersion":1,"plugins":{"example":{"enabled":true,"placement":"left","settings":[],"commit":""}}}' \
  '{"schemaVersion":1,"plugins":{},"plugins":{}}' \
  '{"schemaVersion":1,"plugins":{"example":{"enabled":true,"placement":"left","settings":{"x":{"a":1},"x":{"b":2}},"commit":""}}}' \
  '{'; do
  printf '%s\n' "$config" >"$TMP/home/.config/hyprsimple/plugins.json"
  if ! run_harness; then cat "$TMP/log"; exit 1; fi
  grep -q 'CONFIG-REJECTED' "$TMP/log" || { cat "$TMP/log"; exit 1; }
  if grep -q 'HARNESS-FAIL\|SERVICE-ONCE\|DEPENDENT-MUST-NOT-LOAD' "$TMP/log"; then exit 1; fi
  echo 'ok - malformed or duplicate config rejects all external code with core harness alive'
done
