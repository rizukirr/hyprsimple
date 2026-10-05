import QtQuick
import Quickshell
import Quickshell.Io

// Whether the screen locks when idle, which is whether hypridle runs.
//
// hypridle owns org.freedesktop.ScreenSaver on the session bus while it runs, so
// one dbus-monitor waiting for that name to change hands tells us when it starts
// or stops, from the button, the keybinding or a crash alike. A poll did the same
// with a pgrep every few seconds on every monitor.
Item {
    id: root

    // hypridle is not running, so the screen stays on.
    property bool awake: false

    function toggle() {
        toggleProcess.running = true
    }

    function check() {
        checkProcess.running = true
    }

    Process {
        id: checkProcess
        command: ["pgrep", "-x", "hypridle"]
        running: true
        onExited: exitCode => root.awake = exitCode !== 0
    }

    Process {
        id: toggleProcess
        command: [Quickshell.env("HOME") + "/.local/bin/toggle-idle.sh"]
        onExited: root.check()
    }

    Process {
        id: watcher
        command: ["dbus-monitor", "--session",
            "type='signal',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='org.freedesktop.ScreenSaver'"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                if (line.includes("member=NameOwnerChanged")) root.check()
            }
        }
        // Started again if it ever dies, after a pause so a missing dbus-monitor
        // does not spin.
        onExited: restart.start()
    }

    Timer {
        id: restart
        interval: 5000
        onTriggered: {
            root.check()
            watcher.running = true
        }
    }
}
