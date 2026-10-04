import QtQuick
import qs.theme
import qs.components

// One item in a bar capsule: an icon, a short label such as a percentage, or both.
Item {
    id: root

    property alias icon: glyph.text
    property alias label: caption.text
    // Its panel is open.
    property bool active: false
    // Accent without an open panel, to draw attention.
    property bool highlighted: false
    // Danger color, for something that needs stopping.
    property bool alert: false
    // Off, muted or nothing connected.
    property bool dim: false
    property real radius: Theme.capsuleInnerRadius
    // Shown under the item after the pointer rests on it.
    property string tooltip
    signal clicked()

    implicitWidth: content.implicitWidth + Theme.statusSlot - Theme.iconSize
    visible: glyph.text !== "" || caption.text !== ""
    implicitHeight: Theme.capsule

    Row {
        id: content
        anchors.centerIn: parent
        spacing: Theme.xs
        opacity: root.dim ? Theme.dimmed : 1
        Behavior on opacity { Anim {} }

        Icon {
            id: glyph
            anchors.verticalCenter: parent.verticalCenter
            visible: text !== ""
            color: root.alert ? Theme.danger : root.active || root.highlighted ? Theme.accent : Theme.secondary
            fill: root.active ? 1 : 0
        }

        StyledText {
            id: caption
            anchors.verticalCenter: parent.verticalCenter
            visible: text !== ""
            color: root.alert ? Theme.danger : root.active || root.highlighted ? Theme.accent : Theme.fg
        }
    }

    // Inset like the capsule's side padding, so the hover shape sits evenly inside the capsule.
    StateLayer {
        id: layer
        anchors.topMargin: Theme.xs
        anchors.bottomMargin: Theme.xs
        onClicked: root.clicked()
    }

    Tooltip {
        target: root
        text: root.tooltip
        hovered: layer.containsMouse && !root.active
    }
}
