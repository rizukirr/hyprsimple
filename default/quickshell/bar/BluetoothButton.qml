import QtQuick
import Quickshell.Bluetooth
import qs.theme

// Bluetooth state. With a device connected it shows that device's icon,
// and its battery level when the device reports one.
StatusButton {
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var connected: adapter?.devices.values.filter(d => d.connected) ?? []
    // A device that reports its battery wins, so a headset is preferred over a mouse that does not.
    readonly property var device: connected.find(d => d.batteryAvailable) ?? connected[0] ?? null

    visible: adapter !== null
    icon: !adapter?.enabled ? Theme.icon.btOff
        : device ? Theme.btIcon(device.icon, Theme.icon.btConnected)
        : Theme.icon.bt
    label: device?.batteryAvailable ? `${Math.round(device.battery * 100)}%` : ""
    dim: !device
}
