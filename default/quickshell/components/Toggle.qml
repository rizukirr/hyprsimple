import QtQuick
import qs.theme

// Switch. Emits toggled and the owner flips the state it is bound to.
Rectangle {
    id: root

    property bool checked: false
    signal toggled()

    implicitWidth: Theme.toggleWidth
    implicitHeight: Theme.toggleHeight
    radius: height / 2
    color: checked ? Theme.accent : Theme.tint(Theme.tintSelected)
    Behavior on color { CAnim {} }

    Rectangle {
        readonly property real inset: 3

        height: parent.height - 2 * inset
        // Widens while pressed, like the Material switch.
        width: mouse.pressed ? height * 1.3 : height
        radius: height / 2
        y: inset
        x: root.checked ? root.width - width - inset : inset
        color: root.checked ? Theme.onAccent : Theme.muted
        Behavior on x { Anim {} }
        Behavior on width { Anim {} }
        Behavior on color { CAnim {} }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
