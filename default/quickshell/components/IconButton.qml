import QtQuick
import qs.theme

// Round icon button. filled marks the "on" state, busy swaps the icon for a spinner.
Rectangle {
    id: root

    property alias icon: glyph.text
    property color iconColor: Theme.fg
    property bool filled: false
    property bool busy: false
    signal clicked()

    implicitWidth: Theme.controlSize
    implicitHeight: Theme.controlSize
    radius: height / 2
    color: filled ? Theme.accent : Qt.alpha(Theme.accent, 0)
    Behavior on color { CAnim {} }

    Icon {
        id: glyph
        anchors.centerIn: parent
        visible: !root.busy
        color: root.filled ? Theme.onAccent : root.iconColor
        fill: root.filled ? 1 : 0
    }

    Spinner {
        anchors.centerIn: parent
        visible: root.busy
        color: root.filled ? Theme.onAccent : Theme.accent
    }

    StateLayer {
        enabled: !root.busy
        onClicked: root.clicked()
    }
}
