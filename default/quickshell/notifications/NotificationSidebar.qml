import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.theme
import qs.components

// The notification history: a sidebar that slides in from the right edge, the mirror
// of the app launcher. It lists what has been shown, newest first. Clicking one
// removes it, and Clear removes them all.
PanelWindow {
    id: panel

    required property var bar
    readonly property string name: "notifications"
    readonly property bool open: bar.openPanel === name

    // 0 closed, 1 open. Two animations started by hand, see PopupPanel.
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

    property bool focusPrimed: false

    function dismiss() {
        if (open) bar.openPanel = ""
    }

    // "now", "5 min ago", "14:02", or the date for an older one.
    function ago(time) {
        const minutes = Math.floor((clock.date - time) / 60000)
        if (minutes < 1) return "now"
        if (minutes < 60) return minutes + " min ago"
        const sameDay = time.toDateString() === clock.date.toDateString()
        return Qt.formatDateTime(time, sameDay ? "HH:mm" : "d MMM HH:mm")
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
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
        Notifications.unread = 0
        Qt.callLater(() => card.forceActiveFocus())
    }

    Timer {
        id: prime
        interval: Theme.focusPrime
        onTriggered: panel.focusPrimed = true
    }

    // One that arrives while the list is on screen has been seen.
    Connections {
        target: Notifications
        function onUnreadChanged() { if (panel.open) Notifications.unread = 0 }
    }

    screen: bar.screen
    visible: open || closing.running
    anchors { top: true; bottom: true; left: true; right: true }
    margins.top: Theme.barHeight
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
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

    Item {
        id: card

        readonly property real flare: Theme.panelRadius
        // Extra fill past the screen edge, so the overshoot never shows a gap there.
        readonly property real bleed: 2 * Theme.lg

        x: parent.width - width + (1 - panel.progress) * (width + flare)
        width: Theme.sidebarWidth
        height: parent.height
        focus: true
        Keys.onEscapePressed: panel.dismiss()

        // Outline: along the bar from the screen edge, flare down into the left side,
        // down it, flare out along the bottom edge and back.
        Shape {
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

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        ColumnLayout {
            x: Theme.lg
            y: Theme.lg
            width: parent.width - 2 * Theme.lg
            height: parent.height - 2 * Theme.lg
            spacing: Theme.md
            opacity: Math.max(0, Math.min(1, panel.progress))

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.sm

                StyledText {
                    Layout.fillWidth: true
                    text: "Notifications"
                    font.weight: Font.Medium
                }

                TextButton {
                    visible: Notifications.history.length > 0
                    text: "Clear"
                    onClicked: Notifications.clearHistory()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.sm

                Icon {
                    text: Notifications.silent ? Theme.icon.bellOff : Theme.icon.bell
                    color: Theme.muted
                }

                StyledText {
                    Layout.fillWidth: true
                    text: "Do not disturb"
                }

                Toggle {
                    checked: Notifications.silent
                    onToggled: Notifications.silent = !Notifications.silent
                }
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Theme.sm
                boundsBehavior: Flickable.StopAtBounds
                model: ScriptModel {
                    values: [...Notifications.history]
                }

                delegate: Column {
                    id: row

                    required property var modelData

                    width: list.width
                    spacing: Theme.xs

                    SectionLabel {
                        text: panel.ago(row.modelData.time)
                    }

                    NotificationCard {
                        implicitWidth: row.width
                        record: row.modelData
                        onDismissed: Notifications.forget(row.modelData)
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: "No notifications"
                    color: Theme.muted
                }
            }
        }
    }
}
