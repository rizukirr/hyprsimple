import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.bar
import qs.muslimtify.services
import qs.system
import qs.theme
import qs.notifications

ShellRoot {
    id: root

    // The bars are hidden, with the shell still running. Notifications need it running.
    property bool barsHidden: false

    // A screen recording is running, as told over ipc. Whatever told it can be
    // wrong or never call back: a test once reported a recording that did not exist.
    // So while it is lit the shell looks for a recorder itself and clears it when there is none.
    property bool recording: false

    Timer {
        interval: Theme.recordingPollMs
        running: root.recording
        repeat: true
        onTriggered: recorderCheck.running = true
    }

    Process {
        id: recorderCheck
        command: ["sh", "-c", "pgrep -x wf-recorder >/dev/null || pgrep -x wl-screenrec >/dev/null"]
        onExited: exitCode => {
            if (exitCode !== 0) root.recording = false
        }
    }

    // Read once and shown by every bar.
    Muslimtify {
        id: prayers
    }

    Stats {
        id: systemStats
    }

    Idle {
        id: idleWatch
    }

    Variants {
        id: bars
        model: Quickshell.screens

        Bar {
            visible: !root.barsHidden
            recording: root.recording
            muslimtify: prayers
            stats: systemStats
            idle: idleWatch
        }
    }

    NotificationPopups {}

    // Lets a keybinding open a panel: qs -p <this directory> ipc call bar toggle power
    IpcHandler {
        target: "bar"

        // Toggles a panel on the bar of the focused monitor.
        function toggle(panel: string): void {
            const focused = Hyprland.focusedMonitor?.name
            const bar = bars.instances.find(b => b.screen?.name === focused) ?? bars.instances[0]
            if (bar) bar.toggle(panel)
        }

        // Shows or hides the recording indicator. hyprsimple's screen-record.sh calls it
        // when a recording starts and after it has stopped.
        // vibekit: the state lives in the running shell, so a bar restarted mid-recording shows nothing until the next call
        // A bar told true with no recorder running clears itself, see Bar.qml.
        function setRecording(active: bool): void {
            root.recording = active
        }

        // Hides the bars, or shows them again.
        function toggleVisible(): void {
            root.barsHidden = !root.barsHidden
        }

        // Closes every notification on screen.
        function dismissNotifications(): void {
            Notifications.dismissAll()
        }
    }
}
