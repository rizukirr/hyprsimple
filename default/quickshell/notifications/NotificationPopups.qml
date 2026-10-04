import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.theme
import qs.components

// Notifications, in a card that grows down out of the top right corner of the focused
// monitor, in the bar's own color and joined to it by a flared corner. The card grows
// as notifications arrive and shrinks back into the bar when the last one leaves.
PanelWindow {
    id: root

    readonly property real pad: Theme.sm
    readonly property real flare: Theme.panelRadius

    screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
    // The whole height of the screen, so the window is never resized while the card
    // grows. Only the card takes input.
    anchors { top: true; right: true; bottom: true }
    // Below the bar when it is shown, and at the top edge when it is hidden.
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-panel"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"
    visible: Notifications.entries.length > 0
    implicitWidth: Theme.notifyWidth + 2 * pad + flare
    mask: Region { item: card }

    Item {
        id: card

        readonly property real corner: Math.min(Theme.panelRadius, height / 2)

        x: root.flare
        width: parent.width - root.flare
        // Each notification grows and shrinks its own slot, and the card follows.
        height: stack.height > 0 ? stack.height + 2 * root.pad - Theme.sm : 0

        // Outline: flare in from the bar on the left, down the side, round the bottom
        // left corner, along the bottom to the screen edge and back up it.
        Shape {
            x: -root.flare
            width: card.width + root.flare
            height: card.height
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: 0
                strokeColor: "transparent"
                fillColor: Theme.bg
                Behavior on fillColor { CAnim {} }

                startX: 0
                startY: 0
                PathArc {
                    x: root.flare
                    y: Math.min(root.flare, card.height)
                    radiusX: root.flare
                    radiusY: Math.min(root.flare, card.height)
                }
                PathLine { x: root.flare; y: card.height - card.corner }
                PathArc {
                    x: root.flare + card.corner
                    y: card.height
                    radiusX: card.corner
                    radiusY: card.corner
                    direction: PathArc.Counterclockwise
                }
                PathLine { x: root.flare + card.width; y: card.height }
                PathLine { x: root.flare + card.width; y: 0 }
            }
        }

        Item {
            anchors.fill: parent
            clip: true

            Column {
                id: stack
                x: root.pad
                y: root.pad
                width: Theme.notifyWidth

                Repeater {
                    model: ScriptModel {
                        values: [...Notifications.entries]
                    }

                    // The slot one notification takes, the gap under it included. It opens
                    // with a slight overshoot and closes quickly, and the card inside keeps
                    // its size and slides in from the right.
                    Item {
                        id: slot

                        required property var modelData
                        // 0 closed, 1 open.
                        property real shown: 0

                        width: stack.width
                        height: Math.max(0, (notification.implicitHeight + Theme.sm) * shown)

                        Component.onCompleted: opening.start()

                        NumberAnimation {
                            id: opening
                            target: slot
                            property: "shown"
                            to: 1
                            duration: Theme.springAnim
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.springCurve
                        }

                        NumberAnimation {
                            id: closing
                            target: slot
                            property: "shown"
                            to: 0
                            duration: Theme.closeAnim
                            easing.type: Easing.InCubic
                        }

                        Connections {
                            target: slot.modelData
                            function onClosingChanged() {
                                opening.stop()
                                closing.start()
                            }
                        }

                        NotificationCard {
                            id: notification
                            record: slot.modelData.record
                            notification: slot.modelData.closing ? null : slot.modelData.notification
                            stamp: slot.modelData.stamp
                            x: (1 - Math.min(1, slot.shown)) * Theme.notifyWidth / 2
                            opacity: Math.max(0, Math.min(1, slot.shown))
                        }
                    }
                }
            }
        }
    }
}
