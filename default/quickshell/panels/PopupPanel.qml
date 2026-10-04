import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.theme
import qs.components

// Card that grows out of the bar under a bar button, in the bar's own color, joined to it
// by two flared corners. It lives in a transparent window covering everything below the
// bar, so a click anywhere outside the card closes it and the bar stays clickable.
PanelWindow {
    id: panel

    required property var bar
    required property Item anchorItem
    required property string name
    property int panelWidth: Theme.panelWidth
    readonly property bool open: bar.openPanel === name
    default property alias content: box.data

    // 0 closed, 1 open. Overshoots slightly on the way in, and leaves quickly.
    //
    // Opening and closing are two separate animations, started by hand. One animation
    // whose duration and curve were bound to open changed curve while it was already
    // running: a close began on the opening curve, which is nearly finished within a
    // few frames, then switched to the closing curve, which has barely started by
    // then. The panel shut, sprang back open and shut again.
    property real progress: 0

    NumberAnimation {
        id: opening
        target: panel
        property: "progress"
        to: 1
        duration: Theme.springAnim
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.springCurve
    }

    NumberAnimation {
        id: closing
        target: panel
        property: "progress"
        to: 0
        duration: Theme.closeAnim
        easing.type: Easing.InCubic
    }

    // Exclusive focus takes the keyboard at once, but while it is held Hyprland sends every
    // pointer event to this window, the bar included. So it is held briefly, then relaxed.
    property bool focusPrimed: false
    property real leftEdge: Theme.panelRadius

    function dismiss() {
        if (open) bar.openPanel = ""
    }

    // True when both lists hold the same objects in the same order. Panels use it to
    // keep a list model stable, so rows are not rebuilt when nothing moved.
    function sameList(a, b) {
        return a.length === b.length && a.every((item, i) => item === b[i])
    }

    // The item that takes the keyboard when the panel opens. The card itself when unset.
    property Item focusTarget: null

    // Center under the anchor button, clamped so the flares stay on screen.
    function place() {
        const center = anchorItem.mapToItem(null, anchorItem.width / 2, 0).x
        const edge = Theme.panelRadius + Theme.gap
        leftEdge = Math.max(edge, Math.min(center - panelWidth / 2, screen.width - panelWidth - edge))
    }

    onPanelWidthChanged: if (open) place()
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
        place()
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

    // vibekit: covers this screen only, add a click catcher per extra monitor if a second one is attached
    MouseArea {
        anchors.fill: parent
        enabled: panel.open
        acceptedButtons: Qt.AllButtons
        onClicked: panel.dismiss()
    }

    Item {
        id: card

        readonly property real fullHeight: box.implicitHeight + 2 * Theme.lg
        readonly property real flare: Theme.panelRadius
        // The corners cannot be rounder than the card is tall while it is still growing.
        readonly property real corner: Math.min(Theme.panelRadius, height / 2)

        x: panel.leftEdge
        width: panel.panelWidth
        height: Math.max(0, fullHeight * panel.progress)
        focus: true
        Keys.onEscapePressed: panel.dismiss()

        // Outline: flare in from the bar on the left, down the side, round the two bottom
        // corners, back up, flare out to the bar on the right.
        Shape {
            x: -card.flare
            width: card.width + 2 * card.flare
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
                    x: card.flare
                    y: Math.min(card.flare, card.height)
                    radiusX: card.flare
                    radiusY: Math.min(card.flare, card.height)
                }
                PathLine { x: card.flare; y: card.height - card.corner }
                PathArc {
                    x: card.flare + card.corner
                    y: card.height
                    radiusX: card.corner
                    radiusY: card.corner
                    direction: PathArc.Counterclockwise
                }
                PathLine { x: card.flare + card.width - card.corner; y: card.height }
                PathArc {
                    x: card.flare + card.width
                    y: card.height - card.corner
                    radiusX: card.corner
                    radiusY: card.corner
                    direction: PathArc.Counterclockwise
                }
                PathLine { x: card.flare + card.width; y: Math.min(card.flare, card.height) }
                PathArc {
                    x: 2 * card.flare + card.width
                    y: 0
                    radiusX: card.flare
                    radiusY: Math.min(card.flare, card.height)
                }
            }
        }

        // Clicks inside the card must not reach the dismiss area.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        // The content keeps its full size and is revealed as the card grows.
        Item {
            anchors.fill: parent
            clip: true

            Column {
                id: box
                x: Theme.lg
                y: Theme.lg
                width: parent.width - 2 * Theme.lg
                spacing: Theme.sm
                opacity: Math.max(0, Math.min(1, panel.progress))
            }
        }
    }
}
