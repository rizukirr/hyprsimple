import QtQuick
import QtQuick.Layouts
import qs.theme

// Row with a leading icon, title, optional subtitle and trailing items.
// Child items go below the header and grow the row while visible.
Item {
    id: root

    property alias icon: glyph.text
    property string title
    property string subtitle
    property color subtitleColor: Theme.muted
    // Accent icon and title, for the connected item.
    property bool active: false
    property bool clickable: true
    readonly property bool hovered: hover.hovered
    property alias trailing: trailingBox.data
    default property alias extra: extraBox.data
    signal clicked()

    implicitHeight: header.height + (extraBox.implicitHeight > 0 ? extraBox.implicitHeight + 2 * Theme.sm : 0)
    clip: true
    Behavior on implicitHeight { Anim {} }

    HoverHandler { id: hover }

    Rectangle {
        id: header

        width: parent.width
        height: Theme.rowHeight
        radius: height / 2
        color: "transparent"

        StateLayer {
            enabled: root.clickable
            onClicked: root.clicked()
        }

        RowLayout {
            anchors { fill: parent; leftMargin: Theme.md; rightMargin: Theme.xs }
            spacing: Theme.sm

            Icon {
                id: glyph
                color: root.active ? Theme.accent : Theme.muted
                fill: root.active ? 1 : 0
            }

            StyledText {
                Layout.fillWidth: true
                text: root.title
                elide: Text.ElideRight
                color: root.active ? Theme.accent : Theme.fg
                font.weight: root.active ? Font.Medium : Font.Normal
            }

            StyledText {
                visible: text !== ""
                text: root.subtitle
                color: root.subtitleColor
                font.pixelSize: Theme.fontSizeSmall
            }

            Row {
                id: trailingBox
                spacing: Theme.xs
            }
        }
    }

    Column {
        id: extraBox
        anchors { top: header.bottom; topMargin: Theme.sm; left: parent.left; right: parent.right }
        spacing: Theme.sm
    }
}
