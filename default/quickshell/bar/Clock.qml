import QtQuick
import Quickshell
import qs.theme
import qs.components

// Clock capsule. Its background shows while the calendar is open.
Rectangle {
    id: root

    // Its panel is open.
    property bool active: false
    signal clicked()

    implicitWidth: content.implicitWidth + 2 * Theme.md
    implicitHeight: Theme.capsule
    radius: height / 2
    color: active ? Theme.surface : Qt.alpha(Theme.surface, 0)
    Behavior on color { CAnim {} }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: Theme.sm

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            text: Theme.icon.calendar
            color: Theme.secondary
            fill: root.active ? 1 : 0
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(clock.date, "dddd HH:mm")
            font.weight: Font.Medium
        }
    }

    StateLayer {
        onClicked: root.clicked()
    }
}
