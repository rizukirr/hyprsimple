import QtQuick
import Quickshell.Services.UPower
import qs.theme

// Laptop battery. Hidden on machines without one.
StatusButton {
    readonly property var device: UPower.displayDevice
    readonly property real level: device?.percentage ?? 0
    readonly property bool charging: device?.state === UPowerDeviceState.Charging
        || device?.state === UPowerDeviceState.FullyCharged

    visible: device?.isLaptopBattery ?? false
    icon: charging ? Theme.icon.batteryCharging
        : Theme.icon.battery[Math.min(Theme.icon.battery.length - 1, Math.floor(level * Theme.icon.battery.length))]
    label: `${Math.round(level * 100)}%`
    tooltip: `Battery ${Math.round(level * 100)}%${charging ? ", charging" : ""}`
}
