import QtQuick
import qs.theme

// Pill button with a label. filled uses the accent, otherwise it is a faint tint.
Rectangle {
    id: root

    property alias text: label.text
    property bool filled: false
    signal clicked()

    implicitWidth: label.implicitWidth + 2 * Theme.md
    implicitHeight: Theme.controlSize + Theme.xs
    radius: height / 2
    color: filled ? Theme.accent : Theme.tint(Theme.tintHover)
    Behavior on color { CAnim {} }

    StyledText {
        id: label
        anchors.centerIn: parent
        color: root.filled ? Theme.onAccent : Theme.fg
        font.weight: Font.Medium
    }

    StateLayer {
        onClicked: root.clicked()
    }
}
