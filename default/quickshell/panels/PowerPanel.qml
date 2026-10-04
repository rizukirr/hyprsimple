import QtQuick
import Quickshell
import qs.theme
import qs.components

// Session actions. The ones that end the session ask for a second click.
PopupPanel {
    id: root

    readonly property var actions: [
        { name: "Lock", icon: Theme.icon.lock, command: ["hyprlock"], confirm: false },
        { name: "Suspend", icon: Theme.icon.suspend, command: ["systemctl", "suspend"], confirm: false },
        { name: "Log out", icon: Theme.icon.logout, command: ["hypr-logout.sh"], confirm: true },
        { name: "Restart", icon: Theme.icon.restart, command: ["systemctl", "reboot"], confirm: true },
        { name: "Shut down", icon: Theme.icon.power, command: ["systemctl", "poweroff"], confirm: true }
    ]
    // Name of the action waiting for its confirming click, or "".
    property string armed: ""

    function run(action) {
        if (action.confirm && armed !== action.name) {
            armed = action.name
            return
        }
        dismiss()
        Quickshell.execDetached(action.command)
    }

    panelWidth: Theme.panelWidthNarrow
    onOpenChanged: armed = ""

    Repeater {
        model: root.actions

        ListRow {
            required property var modelData
            readonly property bool armed: root.armed === modelData.name

            width: parent.width
            icon: modelData.icon
            title: armed ? `${modelData.name}? Click again` : modelData.name
            subtitleColor: Theme.danger
            active: armed
            onClicked: root.run(modelData)
        }
    }
}
