import QtQuick
import Quickshell
import qs.theme
import qs.components
import "../muslimtify/views"

// The muslimtify panel: today's prayer times, or every setting.
// Keys: s switches between the two pages, r refreshes, Esc leaves settings and then closes.
PopupPanel {
    id: root

    required property var service
    property bool settingsOpen: false

    function setSettingsOpen(value) {
        settingsOpen = value
        if (value) service.loadTimezones()
        keys.forceActiveFocus()
    }

    function openLink(url) {
        Quickshell.execDetached(["xdg-open", url])
        dismiss()
    }

    panelWidth: settingsOpen ? Theme.panelWidthWide : Theme.panelWidth
    focusTarget: keys
    onOpenChanged: if (!open) settingsOpen = false

    Item {
        id: keys

        width: parent.width
        height: page.item ? page.item.implicitHeight : 0

        // Keys typed into a text field never get here. Anything not handled carries on to the panel, which closes on Esc.
        Keys.onPressed: event => {
            const key = event.text.toLowerCase()
            if (event.key === Qt.Key_Escape && root.settingsOpen) root.setSettingsOpen(false)
            else if (key === "s") root.setSettingsOpen(!root.settingsOpen)
            else if (key === "r") root.service.refresh()
            else return
            event.accepted = true
        }

        Loader {
            id: page
            width: parent.width
            sourceComponent: root.settingsOpen ? settingsPage : todayPage
        }
    }

    Component {
        id: todayPage

        TodayView {
            service: root.service
            onSettingsRequested: root.setSettingsOpen(true)
            onLinkRequested: url => root.openLink(url)
        }
    }

    Component {
        id: settingsPage

        SettingsView {
            service: root.service
            onCloseRequested: root.setSettingsOpen(false)
        }
    }
}
