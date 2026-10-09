import QtQuick
import Quickshell
import Quickshell.Io
import "Manifest.js" as Manifest

Scope {
    id: root
    property string pluginRoot: Quickshell.env("HYPRSIMPLE_PLUGIN_ROOT") || Quickshell.env("HOME") + "/.local/share/hyprsimple-plugins"
    property string configPath: Quickshell.env("HOME") + "/.config/hyprsimple/plugins.json"
    property string corePath: Quickshell.env("HYPRSIMPLE_PATH") || Quickshell.env("HOME") + "/.local/share/hyprsimple"
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
            component = Qt.createComponent(Manifest.url(path), Component.PreferSynchronous, root)
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

    function accept(data) {
        try {
            const lines = data.trim().split("\n").map(line => JSON.parse(line))
            const config = Manifest.config(lines[0].config)
            const records = lines.slice(1)
            const valid = []
            const counts = Object.create(null)
            const ids = Object.create(null)
            records.forEach(record => {
                try {
                    const manifest = Manifest.validate(record)
                    ids[manifest.id] = (ids[manifest.id] || 0) + 1
                    const declaredAliases = manifest.panelAliases || []
                    declaredAliases.forEach(alias => counts[alias] = (counts[alias] || 0) + 1)
                    valid.push(record)
                } catch (e) { failed(record.id, e.message) }
            })
            Object.keys(config).forEach(id => {
                if (config[id].enabled && !records.some(record => record.id === id)) failed(id, "enabled plugin is missing")
            })
            const enabled = []
            const names = Object.create(null)
            const shared = Object.create(null)
            valid.forEach(record => {
                const m = record.manifest
                if (ids[m.id] !== 1 || (m.panelAliases || []).some(alias => counts[alias] !== 1)) { failed(m.id, "duplicate ID or panel alias"); return }
                const c = config[m.id]
                if (!c?.enabled) return
                const plugin = {id: m.id, manifest: m, paths: record.paths, settings: c.settings, placement: c.placement}
                if (m.entryPoints.service) {
                    const context = contextComponent.createObject(root, {pluginId:m.id, settings:c.settings})
                    const service = create(record.paths[m.entryPoints.service], root, context, m.id)
                    if (!service) { context.destroy(); return }
                    context.service = service
                    owned.push(context, service)
                    shared[m.id] = service
                }
                enabled.push(plugin)
                const panelAliases = m.panelAliases || []
                panelAliases.forEach(alias => names[alias] = "plugin:" + m.id)
            })
            services = shared
            aliases = names
            plugins = enabled
        } catch (e) { failed("registry", e.message) }
        ready = true
    }

    property string catalog: ""
    property bool collected: false
    property int catalogExit: -1
    function finishCatalog() {
        if (!collected || catalogExit === -1) return
        if (catalogExit === 0) accept(catalog)
        else { failed("registry", "catalog failed: " + catalogExit); ready = true }
    }

    Component { id: contextComponent; PluginContext {} }
    Process {
        command: Manifest.catalogCommand(root.pluginRoot, root.configPath, root.corePath)
        running: true
        stdout: StdioCollector { onStreamFinished: { root.catalog = text; root.collected = true; root.finishCatalog() } }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) root.failed("registry", text.trim()) }
        onExited: exitCode => { root.catalogExit = exitCode; root.finishCatalog() }
    }
}
