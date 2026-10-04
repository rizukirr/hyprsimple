import QtQuick
import QtQuick.Layouts
import qs.theme

// A search field over a list with one moving selection. The shared body of the
// launcher and of the other menus. The owner filters and orders the
// items, and supplies the delegate that draws one.
ColumnLayout {
    id: root

    property alias text: search.text
    property alias placeholder: search.placeholder
    // What the list shows, already filtered and ordered.
    property var items: []
    // Rows are created only while this is set, so nothing is built for a closed panel.
    property bool active: true
    // Draws one item. It gets modelData and index, and calls activated when clicked.
    property alias delegate: list.delegate
    // Height of the list, or -1 to take whatever height is left.
    property real listHeight: -1
    readonly property real contentHeight: list.contentHeight
    // The least height the list needs to show its empty message whole.
    readonly property real emptyHeight: empty.implicitHeight + 2 * Theme.lg
    property string emptyText: "Nothing found"
    property int current: 0
    readonly property var currentItem: items[current] ?? null
    // The item that should take the keyboard when the owner opens.
    readonly property Item inputItem: search.inputItem
    signal activated(var item)
    signal dismissed()
    // A key the list did not use to move the selection. Set event.accepted to keep it from the field.
    signal keyPressed(var event)

    function move(step) {
        if (items.length === 0) return
        current = Math.max(0, Math.min(items.length - 1, current + step))
        list.positionViewAtIndex(current, ListView.Contain)
    }

    function reset() {
        search.text = ""
        current = 0
    }

    spacing: Theme.md

    onItemsChanged: {
        current = 0
        list.positionViewAtBeginning()
    }

    TextField {
        id: search
        Layout.fillWidth: true
        icon: Theme.icon.search
        catchEscape: true
        // The first Esc clears what was typed, the next one closes.
        onEscaped: {
            if (text !== "") text = ""
            else root.dismissed()
        }
        onAccepted: if (root.currentItem) root.activated(root.currentItem)
        onKeyPressed: event => {
            const ctrl = event.modifiers & Qt.ControlModifier
            if (event.key === Qt.Key_Down || (ctrl && (event.key === Qt.Key_N || event.key === Qt.Key_J))) root.move(1)
            else if (event.key === Qt.Key_Up || (ctrl && (event.key === Qt.Key_P || event.key === Qt.Key_K))) root.move(-1)
            else if (event.key === Qt.Key_PageDown) root.move(Theme.pageStep)
            else if (event.key === Qt.Key_PageUp) root.move(-Theme.pageStep)
            else {
                root.keyPressed(event)
                return
            }
            event.accepted = true
        }
    }

    ListView {
        id: list

        Layout.fillWidth: true
        Layout.fillHeight: root.listHeight < 0
        Layout.preferredHeight: root.listHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.active ? root.items : []
        currentIndex: root.current
        // One tint that glides between rows, where each row drawing its own would jump.
        highlightFollowsCurrentItem: false
        highlight: Rectangle {
            width: list.width
            height: list.currentItem?.height ?? 0
            y: list.currentItem?.y ?? 0
            radius: Theme.radius
            color: Theme.tint(Theme.tintSelected)
            Behavior on y { Spring {} }
        }

        // Shown when nothing matches.
        Column {
            id: empty
            anchors.centerIn: parent
            visible: root.items.length === 0
            spacing: Theme.sm

            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Theme.icon.noResults
                color: Theme.muted
                font.pixelSize: Theme.fontSizeLarge * 2
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.emptyText
                color: Theme.muted
            }
        }
    }
}
