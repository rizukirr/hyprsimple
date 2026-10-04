import QtQuick
import Quickshell
import Quickshell.Io
import qs.theme

// Keep awake. Lit while hypridle is not running, which means the screen will not
// lock or sleep on idle. Clicking it runs hyprsimple's toggle-idle.sh.
StatusButton {
    id: root

    property bool awake: false

    icon: Theme.icon.awake
    highlighted: awake
    dim: !awake
    onClicked: toggle.running = true

    Process {
        id: check
        command: ["pgrep", "-x", "hypridle"]
        onExited: exitCode => root.awake = exitCode !== 0
    }

    Process {
        id: toggle
        command: [Quickshell.env("HOME") + "/.local/bin/toggle-idle.sh"]
        onExited: check.running = true
    }

    // hypridle can also be stopped by the keybinding, so the state is re-read.
    Timer {
        interval: Theme.awakePollMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: check.running = true
    }
}
