import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property string pluginRoot: Quickshell.env("HYPRSIMPLE_PLUGIN_ROOT") || Quickshell.env("HOME") + "/.local/share/hyprsimple-plugins"
    property string configPath: Quickshell.env("HOME") + "/.config/hyprsimple/plugins.json"
    property var plugins: []
    property var aliases: ({})
    property var services: ({})
    property bool ready: false
    property var owned: []
    signal failed(string pluginId, string reason)
    onFailed: (pluginId, reason) => console.warn("plugin " + pluginId + ": " + reason)

    function resolvePanel(name) { return Object.prototype.hasOwnProperty.call(aliases, name) ? aliases[name] : name }

    function create(path, parent, context, pluginId) {
        let component = null
        try {
            component = Qt.createComponent("file://" + path.split("/").map(encodeURIComponent).join("/"), Component.PreferSynchronous, root)
            if (component.status !== Component.Ready) throw Error(component.errorString())
            const instance = component.createObject(parent, {context: context})
            if (!instance) throw Error(component.errorString() || "object creation failed")
            if (instance.context !== context) { instance.destroy(); throw Error("entry point must declare a context property") }
            return instance
        } catch (e) {
            failed(pluginId, e.message)
            return null
        } finally {
            if (component) component.destroy()
        }
    }

    // hyprsimple-plugin validated every manifest when it installed or enabled the
    // plugin, so this only reads. One plugin that fails to load leaves the rest alone.
    function accept(data) {
        const files = Object.create(null)
        data.split("\x1e\n").forEach(block => {
            const end = block.indexOf("\n")
            if (end > 0) files[block.slice(0, end)] = block.slice(end + 1)
        })
        let config = {}
        try { if (files[configPath]) config = JSON.parse(files[configPath]).plugins } catch (e) { failed("registry", "invalid plugin config: " + e.message) }
        const enabled = []
        const names = Object.create(null)
        const shared = Object.create(null)
        Object.keys(config).forEach(id => {
            const c = config[id]
            if (!c.enabled) return
            const dir = pluginRoot + "/" + id
            try {
                if (!files[dir + "/manifest.json"]) throw Error("enabled plugin is missing")
                const m = JSON.parse(files[dir + "/manifest.json"])
                const settings = c.settings || {}
                if (m.entryPoints.service) {
                    const context = contextComponent.createObject(root, {pluginId: id, settings: settings})
                    const service = create(dir + "/" + m.entryPoints.service, root, context, id)
                    if (!service) { context.destroy(); return }
                    context.service = service
                    owned.push(context, service)
                    shared[id] = service
                }
                enabled.push({id: id, dir: dir, manifest: m, settings: settings, placement: c.placement || m.placement || "left"})
                const panelAliases = m.panelAliases || []
                panelAliases.forEach(alias => names[alias] = "plugin:" + id)
            } catch (e) { failed(id, e.message) }
        })
        services = shared
        aliases = names
        plugins = enabled
        ready = true
    }

    Component { id: contextComponent; PluginContext {} }
    // One shell and no other process: each file is printed after its own path and
    // ended by a record separator, using builtins only.
    Process {
        command: ["sh", "-c", 'for f in "$1" "$2"/*/manifest.json; do [ -f "$f" ] || continue; printf "%s\\n" "$f"; while IFS= read -r line || [ -n "$line" ]; do printf "%s\\n" "$line"; done <"$f"; printf "\\036\\n"; done', "sh", root.configPath, root.pluginRoot]
        running: true
        stdout: StdioCollector { onStreamFinished: root.accept(text) }
    }
}
