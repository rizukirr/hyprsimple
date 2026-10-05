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
import qs.notifications

// Bar flush to the top edge, a plain rectangle with capsule groups on it.
PanelWindow {
    id: bar

    required property var modelData
    // Open panel: "", "notifications", "launcher", "clipboard", "themes", "wallpapers", "record", "keybinds", "prayer", "calendar", "system", "mic", "volume", "network", "bluetooth" or "power".
    property string openPanel: ""
    // The bar with a panel open, on any monitor, or null. Opening one here closes it there.
    required property var panelOwner
    signal opened(var opener)
    onOpenPanelChanged: if (openPanel !== "") opened(bar)

    // A screen recording is running. Set over ipc and checked in shell.qml.
    required property bool recording

    function toggle(name) {
        openPanel = openPanel === name ? "" : name
    }

    screen: modelData
    anchors { top: true; left: true; right: true }
    exclusionMode: ExclusionMode.Auto
    implicitHeight: Theme.barHeight
    color: Theme.bg
    Behavior on color { CAnim {} }

    // One of each for every bar, made in shell.qml.
    required property Muslimtify muslimtify
    required property Stats stats
    required property Idle idle

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
            // Lit while there are notifications not yet looked at.
            StatusButton {
                icon: Notifications.silent ? Theme.icon.bellOff : Theme.icon.bell
                label: Notifications.unread > 0 ? String(Notifications.unread) : ""
                tooltip: Notifications.silent ? "Notifications, do not disturb is on" : "Notifications"
                active: bar.openPanel === "notifications"
                highlighted: Notifications.unread > 0
                dim: Notifications.silent
                onClicked: bar.toggle("notifications")
            }

            AwakeButton { idle: bar.idle }

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

    NotificationSidebar {
        bar: bar
    }

    // Anchored to the clock, which is what puts it at the top centre.
    ClipboardPanel {
        bar: bar
        name: "clipboard"
        anchorItem: clock
    }

    OtherScreenCatcher { bar: bar }

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

    // The list comes from hyprsimple's own script, which reads it from Hyprland.
    KeybindsPanel {
        bar: bar
        name: "keybinds"
        anchorItem: clock
        listCommand: [Quickshell.env("HOME") + "/.local/bin/show-keybindings.sh", "--list"]
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
        stats: bar.stats
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
