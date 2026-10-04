import QtQuick
import Quickshell.Networking
import qs.theme

StatusButton {
    readonly property var devices: Networking.devices.values
    readonly property var wired: devices.find(d => d.type === DeviceType.Wired && d.connected) ?? null
    readonly property var wifi: devices.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wifiNetwork: wifi?.networks.values.find(n => n.connected) ?? null

    icon: wired ? Theme.icon.ethernet
        : !Networking.wifiEnabled ? Theme.icon.wifiOff
        : wifiNetwork ? Theme.wifiIcon(wifiNetwork.signalStrength)
        : Theme.icon.wifi[0]
    dim: !wired && !wifiNetwork
    tooltip: wired ? "Ethernet connected"
        : !Networking.wifiEnabled ? "Wi-Fi off"
        : wifiNetwork ? `${wifiNetwork.name}, signal ${Math.round(wifiNetwork.signalStrength * 100)}%`
        : "Wi-Fi not connected"
}
