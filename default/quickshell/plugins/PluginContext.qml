import QtQuick
import Hyprsimple

QtObject {
    required property string pluginId
    property var settings: ({})
    readonly property var theme: Theme
    property var service: null
    property var screen: null
    // The bar supplies the same owner and toggle behavior as built-in panels.
    property var bar: null
    property var anchorItem: null
    readonly property string panelId: "plugin:" + pluginId
    readonly property bool panelOpen: bar !== null && bar.openPanel === panelId

    function togglePanel() { if (bar) bar.toggle(panelId) }
    function closePanel() { if (panelOpen) bar.openPanel = "" }
}
