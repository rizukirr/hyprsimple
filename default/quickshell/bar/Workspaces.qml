import QtQuick
import Quickshell.Hyprland
import qs.theme
import qs.components

// Workspace capsule. 1 to 5 are always shown, higher ones while they exist.
// Each is a dot, small and dim when empty, and an accent pill slides to the focused one.
Rectangle {
    id: root

    required property var monitor
    readonly property var ids: {
        const existing = Hyprland.workspaces.values.map(w => w.id).filter(id => id > 0)
        return [...new Set([1, 2, 3, 4, 5, ...existing])].sort((a, b) => a - b)
    }
    readonly property int activeId: monitor?.activeWorkspace?.id ?? 1
    readonly property int activeIndex: Math.max(0, ids.indexOf(activeId))
    // Wheel delta collected until one notch (120), so touchpads do not skip workspaces.
    property real wheelDelta: 0

    function switchTo(target) {
        Hyprland.dispatch(`hl.dsp.focus({ workspace = "${target}" })`)
    }

    implicitWidth: ids.length * Theme.workspaceCell + 2 * Theme.xs
    implicitHeight: Theme.capsule
    radius: height / 2
    color: Theme.surface
    Behavior on color { CAnim {} }
    Behavior on implicitWidth { Anim {} }

    WheelHandler {
        onWheel: event => {
            root.wheelDelta += event.angleDelta.y
            if (Math.abs(root.wheelDelta) < 120) return
            root.switchTo(root.wheelDelta > 0 ? "e-1" : "e+1")
            root.wheelDelta = 0
        }
    }

    // Accent pill under the focused workspace. The edge facing the direction of travel
    // moves first and the other edge catches up, so the pill stretches and then snaps.
    Rectangle {
        id: indicator

        readonly property real target: Theme.xs + root.activeIndex * Theme.workspaceCell
        property bool forward: true
        property real start: target
        property real end: target + Theme.workspaceCell

        onTargetChanged: {
            forward = target > start
            start = target
            end = target + Theme.workspaceCell
        }

        x: start
        width: end - start
        height: parent.height - 2 * Theme.xs
        anchors.verticalCenter: parent.verticalCenter
        radius: height / 2
        color: Theme.accent
        Behavior on start { Spring { duration: indicator.forward ? Theme.springAnim * 1.5 : Theme.springAnim } }
        Behavior on end { Spring { duration: indicator.forward ? Theme.springAnim : Theme.springAnim * 1.5 } }
        Behavior on color { CAnim {} }
    }

    Row {
        x: Theme.xs
        height: parent.height

        Repeater {
            model: root.ids

            Item {
                id: cell

                required property int modelData
                readonly property var workspace: Hyprland.workspaces.values.find(w => w.id === modelData) ?? null
                readonly property bool focused: root.activeId === modelData
                readonly property bool occupied: (workspace?.toplevels.values.length ?? 0) > 0

                width: Theme.workspaceCell
                height: parent.height

                Rectangle {
                    anchors.centerIn: parent
                    width: Theme.dotSize
                    height: Theme.dotSize
                    radius: width / 2
                    color: cell.focused ? Theme.onAccent : cell.occupied ? Theme.fg : Theme.muted
                    scale: cell.focused || cell.occupied ? 1 : 0.6
                    Behavior on color { CAnim {} }
                    Behavior on scale { Anim {} }
                }

                // Same height as the accent pill.
                StateLayer {
                    anchors.topMargin: Theme.xs
                    anchors.bottomMargin: Theme.xs
                    radius: height / 2
                    onClicked: root.switchTo(cell.modelData)
                }
            }
        }
    }
}
