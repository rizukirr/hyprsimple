import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.components

// Logo, title and subtitle, with the refresh and settings buttons on the
// right. Shared by both pages.
RowLayout {
    id: root

    property string title
    property string meta
    property bool metaIsError: false
    property bool settingsOpen: false
    signal refreshClicked()
    signal settingsClicked()

    spacing: Theme.md

    Image {
        Layout.preferredWidth: Theme.logoSize
        Layout.preferredHeight: Theme.logoSize
        source: Qt.resolvedUrl("../assets/muslimtify.png")
        sourceSize: Qt.size(2 * Theme.logoSize, 2 * Theme.logoSize)
        fillMode: Image.PreserveAspectFit
        mipmap: true
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        StyledText {
            text: root.title
            font.bold: true
        }
        StyledText {
            Layout.fillWidth: true
            text: root.meta
            color: root.metaIsError ? Theme.danger : Theme.muted
            font.pixelSize: Theme.fontSizeSmall
            elide: Text.ElideRight
        }
    }

    IconButton {
        icon: Theme.icon.refresh
        onClicked: root.refreshClicked()
    }

    IconButton {
        icon: Theme.icon.settings
        filled: root.settingsOpen
        onClicked: root.settingsClicked()
    }
}
