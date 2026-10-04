import QtQuick
import qs.theme

// Horizontal slider from 0 to 1. Emits moved and the owner writes the value it is bound to.
Item {
    id: root

    property real value: 0
    signal moved(real value)

    readonly property real level: Math.max(0, Math.min(1, value))

    implicitHeight: Theme.controlSize

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: Theme.sliderHeight
        radius: height / 2
        color: Theme.tint(Theme.tintSelected)

        Rectangle {
            width: parent.width * root.level
            height: parent.height
            radius: height / 2
            color: Theme.accent
            Behavior on color { CAnim {} }
        }
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: (root.width - width) * root.level
        width: Theme.sliderHandle
        height: width
        radius: width / 2
        color: Theme.accent
        scale: mouse.pressed ? 1.2 : 1
        Behavior on scale { Anim {} }
        Behavior on color { CAnim {} }
    }

    MouseArea {
        id: mouse

        function report(x) {
            root.moved(Math.max(0, Math.min(1, x / width)))
        }

        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: event => report(event.x)
        onPositionChanged: event => report(event.x)
    }
}
