import QtQuick
import Quickshell
import qs.theme
import qs.components

// Small label under a bar item, shown after the pointer has rested on it.
PopupWindow {
    id: root

    required property Item target
    property string text
    // Whether the owner is hovered right now.
    property bool hovered: false
    // Set once the pointer has stayed for the delay.
    property bool ready: false

    onHoveredChanged: {
        ready = false
        if (hovered) delay.restart()
        else delay.stop()
    }

    Timer {
        id: delay
        interval: Theme.tooltipDelay
        onTriggered: root.ready = true
    }

    anchor.item: target
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    visible: ready && hovered && text !== ""
    implicitWidth: label.implicitWidth + 2 * Theme.sm
    // The space above the label clears the bar's bottom edge.
    implicitHeight: label.implicitHeight + Theme.sm + Theme.tooltipGap
    color: "transparent"

    Rectangle {
        anchors { fill: parent; topMargin: Theme.tooltipGap }
        radius: Theme.capsuleRadius
        color: Theme.surface
        border.width: 1
        border.color: Theme.tint(Theme.tintBorder)

        StyledText {
            id: label
            anchors.centerIn: parent
            text: root.text
            font.pixelSize: Theme.fontSizeSmall
        }
    }
}
