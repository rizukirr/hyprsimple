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
        // Animated only in a window that is on screen. A running animation makes
        // every visible window draw, whichever window it is in, and the system
        // panel's meters get a new value every two seconds while it is closed.
        // That had the bar drawing about eleven frames a second with nothing on
        // it changing.
        Behavior on width { enabled: root.Window.window?.visible ?? false; Anim {} }
        Behavior on color { CAnim {} }
    }
}
