import QtQuick
import qs.theme

// Thin bar filled from the left. value is 0 to 1.
Rectangle {
    id: root

    property real value: 0

    implicitHeight: Theme.xs
    radius: height / 2
    color: Theme.tint(Theme.tintSelected)

    Rectangle {
        width: parent.width * Math.max(0, Math.min(1, root.value))
        height: parent.height
        radius: height / 2
        color: Theme.accent
        Behavior on width { Anim {} }
        Behavior on color { CAnim {} }
    }
}
