import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import qs.theme
import qs.components

PopupPanel {
    id: root

    readonly property var devices: Networking.devices.values
    readonly property var wifi: devices.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wired: devices.find(d => d.type === DeviceType.Wired) ?? null
    // Name of the expanded network row, or "".
    property string expanded: ""
    // Connected first, then known, then by signal.
    readonly property var sorted: [...(wifi?.networks.values ?? [])]
        .filter(n => n.name !== "")
        .sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength))
    // The list on screen. Follows sorted, except while a row is expanded, so the password field is not rebuilt while typing.
    property var networks: []

    function sync() {
        if (expanded === "" && !sameList(networks, sorted)) networks = sorted
    }

    onSortedChanged: sync()
    onExpandedChanged: sync()
    Component.onCompleted: sync()
    // Scan only while the panel is open.
    onOpenChanged: {
        if (wifi) wifi.scannerEnabled = open
        expanded = ""
    }

    RowLayout {
        width: parent.width

        StyledText {
            Layout.fillWidth: true
            leftPadding: Theme.sm
            text: "Wi-Fi"
            font.bold: true
        }
        Toggle {
            visible: root.wifi !== null
            checked: Networking.wifiEnabled
            onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
        }
    }

    ListRow {
        width: parent.width
        visible: root.wired !== null
        clickable: false
        icon: Theme.icon.ethernet
        active: root.wired?.connected ?? false
        title: "Ethernet"
        subtitle: root.wired?.connected ? `${root.wired.linkSpeed} Mb/s`
            : root.wired?.hasLink ? "Not connected"
            : "Cable unplugged"
    }

    StyledText {
        width: parent.width
        leftPadding: Theme.sm
        color: Theme.muted
        font.pixelSize: Theme.fontSizeSmall
        text: Networking.backend === NetworkBackendType.None ? "NetworkManager is not running"
            : root.wifi === null ? "No Wi-Fi device"
            : !Networking.wifiEnabled ? "Wi-Fi is off"
            : root.networks.length === 0 ? "Searching for networks…"
            : `${root.networks.length} networks available`
    }

    Flickable {
        width: parent.width
        height: Math.min(list.implicitHeight, Theme.listMaxHeight)
        visible: Networking.wifiEnabled && root.networks.length > 0
        contentHeight: list.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: list
            width: parent.width

            Repeater {
                model: root.networks

                WifiRow {
                    required property var modelData
                    width: list.width
                    network: modelData
                    expanded: root.expanded === modelData.name
                    onExpandRequested: expand => root.expanded = expand ? modelData.name : ""
                }
            }
        }
    }
}
