import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.theme

// A panel open on another monitor's bar closes when this screen is clicked, as it
// does when its own screen is clicked. Each panel's own catcher covers only the
// screen the panel is on.
PanelWindow {
    id: catcher

    required property var bar
    readonly property var owner: bar.panelOwner

    screen: bar.screen
    visible: owner !== null && owner !== bar
    anchors { top: true; bottom: true; left: true; right: true }
    margins.top: Theme.barHeight
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-panel"

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: catcher.owner.openPanel = ""
    }
}
