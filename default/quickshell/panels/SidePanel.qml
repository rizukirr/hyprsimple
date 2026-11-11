import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.theme
import qs.components

// A drawer the full height of the screen below the bar, sliding in from the left or
// the right edge. The launcher and the notification history are built on it, and
// plugins get it from the Hyprsimple module.
PanelWindow {
    id: panel

    required property var bar
    required property string name
    // "left" or "right". Anything else is treated as "left".
    property string edge: "left"
    property int panelWidth: Theme.sidebarWidth
    readonly property bool open: bar.openPanel === name
    readonly property bool fromRight: edge === "right"
    // 0 closed, 1 open. Overshoots slightly on the way in, and leaves quickly.
    readonly property real progress: motion.progress
    // The item that takes the keyboard when the drawer opens. The drawer itself when unset.
    property Item focusTarget: null
    default property alias content: box.data

    // Opening and closing are two separate animations, started by hand. One animation
    // whose duration and curve were bound to open changed curve while it was already
    // running: a close began on the opening curve, which is nearly finished within a
    // few frames, then switched to the closing curve, which has barely started by
    // then. The panel shut, sprang back open and shut again.
    QtObject {
        id: motion
        property real progress: 0
    }

    NumberAnimation {
        id: opening
        target: motion
        property: "progress"
        to: 1
        duration: Theme.springAnim
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.springCurve
    }

    NumberAnimation {
        id: closing
        target: motion
        property: "progress"
        to: 0
        duration: Theme.closeAnim
        easing.type: Easing.InCubic
    }

    // Exclusive focus takes the keyboard at once, but while it is held Hyprland sends every
    // pointer event to this window, the bar included. So it is held briefly, then relaxed.
    property bool focusPrimed: false

    function dismiss() {
        if (open) bar.openPanel = ""
    }

    onOpenChanged: {
        if (!open) {
            opening.stop()
            closing.start()
            return
        }
        closing.stop()
        opening.start()
        focusPrimed = false
        prime.restart()
        Qt.callLater(() => (focusTarget ?? card).forceActiveFocus())
    }

    Timer {
        id: prime
        interval: Theme.focusPrime
        onTriggered: panel.focusPrimed = true
    }

    screen: bar.screen
    visible: open || closing.running
    anchors { top: true; bottom: true; left: true; right: true }
    margins.top: Theme.barHeight
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    // No input while closing, so what is underneath can be clicked at once.
    mask: open ? null : noInput
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-panel"
    WlrLayershell.keyboardFocus: !open ? WlrKeyboardFocus.None
        : focusPrimed ? WlrKeyboardFocus.OnDemand
        : WlrKeyboardFocus.Exclusive

    Region { id: noInput }

    MouseArea {
        anchors.fill: parent
        enabled: panel.open
        acceptedButtons: Qt.AllButtons
        onClicked: panel.dismiss()
    }

    // The drawer is laid out once at its full size and slid in from beyond the edge.
    // Moving it costs nothing per frame, where changing its width made the outline
    // and the whole content be laid out again on every frame.
    Item {
        id: card

        readonly property real flare: Theme.panelRadius
        // Extra fill past the screen edge, so the overshoot on the way in never
        // opens a gap there.
        readonly property real bleed: 2 * Theme.lg

        x: panel.fromRight
            ? parent.width - width + (1 - panel.progress) * (width + flare)
            : (panel.progress - 1) * (width + flare)
        width: panel.panelWidth
        height: parent.height
        focus: true
        Keys.onEscapePressed: panel.dismiss()

        // Left edge: the drawer itself, with a flare at the top joining it to the bar
        // and one at the bottom joining it to the screen edge.
        Shape {
            visible: !panel.fromRight
            x: -card.bleed
            width: card.bleed + card.width + card.flare
            height: card.height
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: 0
                strokeColor: "transparent"
                fillColor: Theme.bg
                Behavior on fillColor { CAnim {} }

                startX: 0
                startY: 0
                PathLine { x: card.bleed + card.width + card.flare; y: 0 }
                PathArc {
                    x: card.bleed + card.width
                    y: card.flare
                    radiusX: card.flare
                    radiusY: card.flare
                    direction: PathArc.Counterclockwise
                }
                PathLine { x: card.bleed + card.width; y: card.height - card.flare }
                PathArc {
                    x: card.bleed + card.width + card.flare
                    y: card.height
                    radiusX: card.flare
                    radiusY: card.flare
                    direction: PathArc.Counterclockwise
                }
                PathLine { x: 0; y: card.height }
            }
        }

        // Right edge: along the bar from the screen edge, flare down into the left side,
        // down it, flare out along the bottom edge and back.
        Shape {
            visible: panel.fromRight
            x: -card.flare
            width: card.flare + card.width + card.bleed
            height: card.height
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: 0
                strokeColor: "transparent"
                fillColor: Theme.bg
                Behavior on fillColor { CAnim {} }

                startX: card.flare + card.width + card.bleed
                startY: 0
                PathLine { x: 0; y: 0 }
                PathArc {
                    x: card.flare
                    y: card.flare
                    radiusX: card.flare
                    radiusY: card.flare
                }
                PathLine { x: card.flare; y: card.height - card.flare }
                PathArc {
                    x: 0
                    y: card.height
                    radiusX: card.flare
                    radiusY: card.flare
                }
                PathLine { x: card.flare + card.width + card.bleed; y: card.height }
            }
        }

        // Clicks inside the drawer must not reach the dismiss area.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        Item {
            id: box
            x: Theme.lg
            y: Theme.lg
            width: parent.width - 2 * Theme.lg
            height: parent.height - 2 * Theme.lg
        }
    }
}
