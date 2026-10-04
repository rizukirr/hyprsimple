import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import qs.theme
import qs.components

// One wifi network. Expands to show a password field when one is needed.
ListRow {
    id: row

    required property var network
    required property bool expanded
    signal expandRequested(bool expand)

    readonly property bool secured: network.security !== WifiSecurityType.Open && network.security !== WifiSecurityType.Owe
    property string error: ""

    function activate() {
        error = ""
        if (network.connected) network.disconnect()
        else if (secured && !network.known) expandRequested(!expanded)
        else network.connect()
    }

    function submit() {
        if (password.text === "") return
        error = ""
        network.connectWithPsk(password.text)
    }

    function failureText(reason) {
        switch (reason) {
        case ConnectionFailReason.NoSecrets: return "Wrong password"
        case ConnectionFailReason.WifiAuthTimeout: return "Authentication timed out"
        case ConnectionFailReason.WifiNetworkLost: return "Network lost"
        default: return "Could not connect"
        }
    }

    icon: Theme.wifiIcon(network.signalStrength)
    title: network.name
    active: network.connected
    subtitle: error !== "" ? error
        : network.state === ConnectionState.Connecting ? "Connecting…"
        : network.state === ConnectionState.Disconnecting ? "Disconnecting…"
        : ""
    subtitleColor: error !== "" ? Theme.danger : Theme.muted

    onClicked: activate()

    onExpandedChanged: {
        if (!expanded) password.text = ""
        else Qt.callLater(() => password.focusInput())
    }

    Connections {
        target: row.network

        // A saved network whose password changed fails too, so the field opens for it as well.
        function onConnectionFailed(reason) {
            row.error = row.failureText(reason)
            if (row.secured) row.expandRequested(true)
        }

        function onConnectedChanged() {
            if (row.network.connected && row.expanded) row.expandRequested(false)
        }
    }

    trailing: [
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: row.secured
            text: Theme.icon.lock
            color: Theme.muted
            font.pixelSize: Theme.fontSize
        },
        IconButton {
            visible: row.hovered && row.network.known && !row.network.stateChanging
            icon: Theme.icon.trash
            iconColor: Theme.danger
            onClicked: row.network.forget()
        },
        IconButton {
            icon: row.network.connected ? Theme.icon.unlink : Theme.icon.link
            filled: row.network.connected
            busy: row.network.stateChanging
            onClicked: row.activate()
        }
    ]

    RowLayout {
        width: parent.width
        visible: row.expanded && !row.network.connected && row.secured
        spacing: Theme.sm

        TextField {
            id: password
            Layout.fillWidth: true
            placeholder: "Password"
            password: !reveal.shown
            invalid: row.error !== ""
            catchEscape: true
            onAccepted: row.submit()
            onEscaped: row.expandRequested(false)
        }

        IconButton {
            id: reveal
            property bool shown: false
            icon: shown ? Theme.icon.eyeOff : Theme.icon.eye
            onClicked: shown = !shown
        }

        TextButton {
            text: "Connect"
            filled: true
            onClicked: row.submit()
        }
    }
}
