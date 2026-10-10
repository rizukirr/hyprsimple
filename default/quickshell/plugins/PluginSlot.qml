import QtQuick
import Hyprsimple

Row {
    id: root
    required property var registry
    required property var bar
    required property string placement
    spacing: Theme.sm

    Repeater {
        model: root.registry.plugins.filter(p => p.placement === root.placement)
        delegate: Item {
            id: host
            required property var modelData
            property var widget: null
            property var panel: null
            implicitWidth: widget && widget.visible ? widget.implicitWidth : 0
            implicitHeight: widget ? widget.implicitHeight : 0
            width: implicitWidth
            height: implicitHeight

            PluginContext {
                id: context
                pluginId: host.modelData.id
                settings: host.modelData.settings
                service: root.registry.services[pluginId] || null
                screen: root.bar.screen
                bar: root.bar
                anchorItem: host
            }
            Component.onCompleted: {
                const entries = modelData.manifest.entryPoints
                if (entries.widget) widget = root.registry.create(modelData.dir + "/" + entries.widget, host, context, modelData.id)
                if (entries.panel) panel = root.registry.create(modelData.dir + "/" + entries.panel, host, context, modelData.id)
            }
            Component.onDestruction: {
                if (context.panelOpen) context.closePanel()
                if (panel) panel.destroy()
                if (widget) widget.destroy()
            }
        }
    }
}
