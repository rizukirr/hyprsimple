import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.bar

ShellRoot {
    Variants {
        id: bars
        model: Quickshell.screens

        Bar {}
    }

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
        function setRecording(active: bool): void {
            bars.instances.forEach(bar => bar.recording = active)
        }
    }
}
