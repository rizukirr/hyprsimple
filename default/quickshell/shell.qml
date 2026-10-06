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

    // The installed bar does not reload itself when its files change.
    //
    // Quickshell reloads a running config as its files change, and an update
    // changes them one at a time. A reload that lands between two of them reads a
    // file using a type whose own file has not arrived, fails, and puts a red
    // "Config reload failed" window on the screen. hyprsimple-update restarts the
    // bar once everything is in place, so the reload gains nothing there.
    //
    // A bar run from anywhere else, a checkout being worked on, still reloads as
    // its files are saved.
    readonly property string installedDir: (Quickshell.env("HYPRSIMPLE_PATH") || Quickshell.env("HOME") + "/.local/share/hyprsimple") + "/default/quickshell"
    Component.onCompleted: if (Quickshell.shellDir === installedDir) Quickshell.watchFiles = false

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

    // One panel at a time across every monitor: the bar that has it open, or null.
    readonly property var panelOwner: bars.instances.find(bar => bar.openPanel !== "") ?? null

    function closeOthers(opener) {
        bars.instances.forEach(bar => { if (bar !== opener) bar.openPanel = "" })
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
            panelOwner: root.panelOwner
            onOpened: opener => root.closeOthers(opener)
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

        // Re-reads whether hypridle runs. toggle-idle.sh calls it, so the keep-awake
        // item follows the keybinding even when the bus does not say.
        function checkIdle(): void {
            idleWatch.check()
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
