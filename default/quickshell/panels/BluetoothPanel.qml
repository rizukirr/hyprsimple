import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs.theme
import qs.components

PopupPanel {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool powered: adapter?.enabled ?? false
    readonly property var devices: [...(adapter?.devices.values ?? [])]
    readonly property var pairedNow: devices.filter(d => d.paired || d.bonded).sort((a, b) => b.connected - a.connected)
    readonly property var availableNow: devices.filter(d => !d.paired && !d.bonded && d.deviceName !== "")
    // The lists on screen. Replaced only when membership or order changes, so rows are not rebuilt on every property change.
    property var paired: []
    property var available: []
    // Device being paired from this panel. It is trusted and connected once pairing completes.
    property var pairing: null

    function sync() {
        if (!sameList(paired, pairedNow)) paired = pairedNow
        if (!sameList(available, availableNow)) available = availableNow
    }

    function activate(device) {
        if (device.paired || device.bonded) {
            if (device.connected) device.disconnect()
            else device.connect()
        } else {
            pairing = device
            device.pair()
        }
    }

    onPairedNowChanged: sync()
    onAvailableNowChanged: sync()
    Component.onCompleted: sync()
    // Discovery drains battery, so it never outlives the panel.
    onOpenChanged: if (!open && adapter) adapter.discovering = false

    Connections {
        target: root.pairing

        function onPairedChanged() {
            if (!root.pairing.paired) return
            root.pairing.trusted = true
            root.pairing.connect()
            root.pairing = null
        }
    }

    RowLayout {
        width: parent.width
        spacing: Theme.sm

        StyledText {
            Layout.fillWidth: true
            leftPadding: Theme.sm
            text: "Bluetooth"
            font.bold: true
        }
        // Filled while scanning for new devices.
        IconButton {
            visible: root.powered
            icon: Theme.icon.scan
            filled: root.adapter?.discovering ?? false
            onClicked: root.adapter.discovering = !root.adapter.discovering
        }
        Toggle {
            visible: root.adapter !== null
            checked: root.powered
            onToggled: root.adapter.enabled = !root.adapter.enabled
        }
    }

    StyledText {
        width: parent.width
        visible: text !== ""
        leftPadding: Theme.sm
        color: Theme.muted
        font.pixelSize: Theme.fontSizeSmall
        text: root.adapter === null ? "No Bluetooth adapter"
            : !root.powered ? "Bluetooth is off"
            : root.paired.length > 0 || root.available.length > 0 ? ""
            : root.adapter.discovering ? "Searching for devices…"
            : "No paired devices"
    }

    Flickable {
        width: parent.width
        height: Math.min(list.implicitHeight, Theme.listMaxHeight)
        visible: root.powered && (root.paired.length > 0 || root.available.length > 0)
        contentHeight: list.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: list
            width: parent.width

            StyledText {
                visible: root.paired.length > 0
                leftPadding: Theme.sm
                text: "Paired"
                color: Theme.muted
                font.pixelSize: Theme.fontSizeSmall
            }

            Repeater {
                model: root.paired

                DeviceRow {
                    required property var modelData
                    width: list.width
                    device: modelData
                    onClicked: root.activate(modelData)
                }
            }

            StyledText {
                visible: root.available.length > 0
                leftPadding: Theme.sm
                topPadding: Theme.sm
                text: "Available"
                color: Theme.muted
                font.pixelSize: Theme.fontSizeSmall
            }

            Repeater {
                model: root.available

                DeviceRow {
                    required property var modelData
                    width: list.width
                    device: modelData
                    onClicked: root.activate(modelData)
                }
            }
        }
    }
}
