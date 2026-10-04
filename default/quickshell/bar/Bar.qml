import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
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
    // Open panel: "", "launcher", "clipboard", "themes", "wallpapers", "record", "prayer", "calendar", "system", "mic", "volume", "network", "bluetooth" or "power".
    property string openPanel: ""

    // A screen recording is running. Set over ipc, see shell.qml.
    property bool recording: false

    // The indicator shows what the bar was last told, and whatever told it can be
    // wrong or never call back: a test once reported a recording that did not exist.
    // So while it is lit the bar looks for a recorder itself and clears it when there is none.
    Timer {
        interval: Theme.recordingPollMs
        running: bar.recording
        repeat: true
        onTriggered: recorderCheck.running = true
    }

    Process {
        id: recorderCheck
        command: ["sh", "-c", "pgrep -x wf-recorder >/dev/null || pgrep -x wl-screenrec >/dev/null"]
        onExited: exitCode => {
            if (exitCode !== 0) bar.recording = false
        }
    }

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
                tooltip: "Recording. Click to stop"
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
                tooltip: `CPU ${Math.round(stats.cpu * 100)}%, memory ${stats.memoryUsedGiB.toFixed(1)} of ${stats.memoryTotalGiB.toFixed(1)} GiB`
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
                name: "Microphone"
                active: bar.openPanel === "mic"
                onClicked: bar.toggle("mic")
            }

            AudioButton {
                id: volumeButton
                node: Pipewire.defaultAudioSink
                levels: Theme.icon.volume
                mutedIcon: Theme.icon.volumeMuted
                name: "Volume"
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
                tooltip: "Power menu"
                active: bar.openPanel === "power"
                onClicked: bar.toggle("power")
            }
        }
    }

    LauncherPanel {
        bar: bar
    }

    // Anchored to the clock, which is what puts it at the top centre.
    ClipboardPanel {
        bar: bar
        name: "clipboard"
        anchorItem: clock
    }

    // The theme and wallpaper pickers list their choices and apply the picked one
    // through hyprsimple's own scripts.
    ImagePickerPanel {
        bar: bar
        name: "themes"
        anchorItem: clock
        title: "Theme"
        listCommand: ["sh", "-c", '"$HOME/.local/bin/hyprsimple-theme-picker.sh" | "$HOME/.local/bin/hyprsimple-thumbnails.sh"']
        currentCommand: ["sh", "-c", 'basename "$(dirname "$(dirname "$(readlink "$HOME/.config/hypr/theme-active.lua")")")"']
        applyCommand: [Quickshell.env("HOME") + "/.local/bin/theme-switcher.sh"]
    }

    ImagePickerPanel {
        bar: bar
        name: "wallpapers"
        anchorItem: clock
        title: "Wallpaper"
        listCommand: ["sh", "-c", '"$HOME/.local/bin/hyprsimple-wallpaper-picker.sh" | "$HOME/.local/bin/hyprsimple-thumbnails.sh"']
        currentCommand: ["cat", Quickshell.env("HOME") + "/.cache/current_wallpaper_path"]
        applyCommand: [Quickshell.env("HOME") + "/.local/bin/wallpaper-switcher.sh", "apply"]
    }

    // Recordings are made by hyprsimple's own script. The panel only chooses what
    // to record. Screenshots have no panel: Print goes straight to picking an area.
    CapturePanel {
        bar: bar
        name: "record"
        anchorItem: clock
        title: bar.recording ? "Recording" : "Record"
        actionLabel: "Start recording"
        running: bar.recording
        stopLabel: "Stop recording"
        stopCommand: [Quickshell.env("HOME") + "/.local/bin/screen-record.sh", "stop"]
        groups: [
            { name: "Area", options: [{ value: "region", label: "Region" }, { value: "window", label: "Window" }, { value: "output", label: "Screen" }] },
            { name: "Audio", options: [{ value: "mic", label: "Microphone" }, { value: "internal", label: "System" }, { value: "none", label: "None" }] }
        ]
        windowValue: "window"
        // The window's place, when one was chosen, goes last. Without it the recorder asks on screen.
        commandFor: (values, geometry) => [Quickshell.env("HOME") + "/.local/bin/screen-record.sh", ...values, ...(geometry !== "" ? [geometry] : [])]
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
