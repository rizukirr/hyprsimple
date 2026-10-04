import QtQuick
import qs.theme

// Click target with a foreground tint on hover and press. It fills the parent and takes its radius.
MouseArea {
    id: root

    property real radius: parent?.radius ?? 0

    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Theme.fg
        opacity: root.pressed ? Theme.tintPressed : root.containsMouse ? Theme.tintHover : 0
        Behavior on opacity { Anim {} }
    }
}
