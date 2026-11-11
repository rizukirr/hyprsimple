import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.theme
import qs.components
import qs.launcher
import "../launcher/search.js" as Search

// App launcher: a sidebar that grows out of the left screen edge, below the bar,
// with a search field over the list of apps.
SidePanel {
    id: panel

    name: "launcher"
    edge: "left"
    focusTarget: picker.inputItem

    // The entry list reorders itself when an app starts, so it is always re-sorted here.
    readonly property var apps: DesktopEntries.applications.values.filter(app => !app.noDisplay && app.name !== "")
    readonly property var results: Search.results(apps, picker.text, Launches.launches)

    // Closed first, so the drawer is already leaving when the app's window arrives.
    function launch(app) {
        if (!app) return
        dismiss()
        Launches.record(app.id)
        // Through uwsm, so the app runs in the session's own scope like one started by a keybinding.
        Quickshell.execDetached(["uwsm", "app", "--", app.id + ".desktop"])
    }

    onOpenChanged: if (open) picker.reset()

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.md
        opacity: Math.max(0, Math.min(1, panel.progress))

        PickerList {
            id: picker

            Layout.fillWidth: true
            Layout.fillHeight: true
            placeholder: "Search apps"
            emptyText: "No apps found"
            items: panel.results
            // Rows, and so icons, exist only while the sidebar is on screen.
            active: panel.visible
            onActivated: app => panel.launch(app)
            onDismissed: panel.dismiss()

            delegate: Item {
                id: row

                required property var modelData

                width: ListView.view.width
                height: Theme.appRowHeight

                RowLayout {
                    anchors { fill: parent; leftMargin: Theme.sm; rightMargin: Theme.sm }
                    spacing: Theme.md

                    // Decoded at twice the shown size, which stays sharp on a scaled screen
                    // and keeps a large vector icon from being rendered at its full size.
                    Image {
                        Layout.preferredWidth: Theme.appIconSize
                        Layout.preferredHeight: Theme.appIconSize
                        sourceSize: Qt.size(2 * Theme.appIconSize, 2 * Theme.appIconSize)
                        fillMode: Image.PreserveAspectFit
                        // Off the main thread, so opening does not wait for the icons.
                        asynchronous: true
                        source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.name
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: row.modelData.comment || row.modelData.genericName
                            color: Theme.muted
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
                        }
                    }
                }

                // Hover has its own tint and does not move the keyboard selection.
                StateLayer {
                    radius: Theme.radius
                    onClicked: picker.activated(row.modelData)
                }
            }
        }
    }
}
