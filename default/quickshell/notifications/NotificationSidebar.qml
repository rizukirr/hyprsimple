import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.theme
import qs.components
import qs.panels

// The notification history: a sidebar that slides in from the right edge, the mirror
// of the app launcher. It lists what has been shown, newest first. Clicking one
// removes it, and Clear removes them all.
SidePanel {
    id: panel

    name: "notifications"
    edge: "right"

    // "now", "5 min ago", "14:02", or the date for an older one.
    function ago(time) {
        const minutes = Math.floor((clock.date - time) / 60000)
        if (minutes < 1) return "now"
        if (minutes < 60) return minutes + " min ago"
        const sameDay = time.toDateString() === clock.date.toDateString()
        return Qt.formatDateTime(time, sameDay ? "HH:mm" : "d MMM HH:mm")
    }

    onOpenChanged: if (open) Notifications.unread = 0

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // One that arrives while the list is on screen has been seen.
    Connections {
        target: Notifications
        function onUnreadChanged() { if (panel.open) Notifications.unread = 0 }
    }

    ColumnLayout {
        anchors.fill: parent
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
