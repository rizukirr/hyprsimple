import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import qs.theme
import qs.components
import qs.panels
import qs.muslimtify.services
import qs.system

// Bar flush to the top edge, a plain rectangle with capsule groups on it.
PanelWindow {
    id: bar

    required property var modelData
    // Open panel: "", "prayer", "calendar", "system", "mic", "volume", "network", "bluetooth" or "power".
    property string openPanel: ""

    // A screen recording is running. Set over ipc, see shell.qml.
    property bool recording: false

    function toggle(name) {
        openPanel = openPanel === name ? "" : name
    }

    screen: modelData
    anchors { top: true; left: true; right: true }
    exclusionMode: ExclusionMode.Auto
    implicitHeight: Theme.barHeight
    color: Theme.bg
    Behavior on color { CAnim {} }

    Muslimtify {
        id: muslimtify
    }

    Stats {
        id: stats
    }

    Row {
        anchors { left: parent.left; leftMargin: Theme.barInset; verticalCenter: parent.verticalCenter }
        spacing: Theme.sm

        Workspaces {
            monitor: Hyprland.monitorFor(bar.screen)
        }

        // Shown while recording. Clicking it stops the recording.
        Capsule {
            visible: bar.recording

            StatusButton {
                icon: Theme.icon.recording
                label: "REC"
                alert: true
                onClicked: Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/screen-record.sh", "stop"])
            }
        }

        // Hidden until muslimtify reports a next prayer.
        Capsule {
            visible: !!muslimtify.next

            PrayerButton {
                id: prayerButton
                service: muslimtify
                active: bar.openPanel === "prayer"
                onClicked: bar.toggle("prayer")
            }
        }
    }

    Clock {
        id: clock
        anchors.centerIn: parent
        active: bar.openPanel === "calendar"
        onClicked: bar.toggle("calendar")
    }

    // Status items, grouped: audio, connectivity, power.
    Row {
        anchors { right: parent.right; rightMargin: Theme.barInset; verticalCenter: parent.verticalCenter }
        spacing: Theme.sm

        Capsule {
            StatusButton {
                id: systemButton
                icon: Theme.icon.ram
                label: `${Math.round(stats.memory * 100)}%`
                active: bar.openPanel === "system"
                onClicked: bar.toggle("system")
            }
        }

        Capsule {
            AudioButton {
                id: micButton
                node: Pipewire.defaultAudioSource
                levels: Theme.icon.mic
                mutedIcon: Theme.icon.micMuted
                active: bar.openPanel === "mic"
                onClicked: bar.toggle("mic")
            }

            AudioButton {
                id: volumeButton
                node: Pipewire.defaultAudioSink
                levels: Theme.icon.volume
                mutedIcon: Theme.icon.volumeMuted
                active: bar.openPanel === "volume"
                onClicked: bar.toggle("volume")
            }
        }

        Capsule {
            NetworkButton {
                id: networkButton
                active: bar.openPanel === "network"
                onClicked: bar.toggle("network")
            }

            BluetoothButton {
                id: bluetoothButton
                active: bar.openPanel === "bluetooth"
                onClicked: bar.toggle("bluetooth")
            }
        }

        Capsule {
            AwakeButton {}

            BatteryButton {}

            StatusButton {
                id: powerButton
                icon: Theme.icon.power
                active: bar.openPanel === "power"
                onClicked: bar.toggle("power")
            }
        }
    }

    PrayerPanel {
        bar: bar
        name: "prayer"
        anchorItem: prayerButton
        service: muslimtify
    }

    CalendarPanel {
        bar: bar
        name: "calendar"
        anchorItem: clock
    }

    SystemPanel {
        bar: bar
        name: "system"
        anchorItem: systemButton
        stats: stats
    }

    AudioPanel {
        bar: bar
        name: "mic"
        anchorItem: micButton
        output: false
        title: "Microphone"
        levels: Theme.icon.mic
        mutedIcon: Theme.icon.micMuted
    }

    AudioPanel {
        bar: bar
        name: "volume"
        anchorItem: volumeButton
        output: true
        title: "Volume"
        levels: Theme.icon.volume
        mutedIcon: Theme.icon.volumeMuted
    }

    NetworkPanel {
        bar: bar
        name: "network"
        anchorItem: networkButton
    }

    BluetoothPanel {
        bar: bar
        name: "bluetooth"
        anchorItem: bluetoothButton
    }

    PowerPanel {
        bar: bar
        name: "power"
        anchorItem: powerButton
    }
}
