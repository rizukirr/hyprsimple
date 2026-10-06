import QtQuick
import qs.theme
import qs.system

// Keep awake. Lit while hypridle is not running, which means the screen will not
// lock or sleep on idle. Clicking it runs hyprsimple's toggle-idle.sh.
StatusButton {
    id: root

    required property Idle idle

    icon: Theme.icon.awake
    highlighted: idle.awake
    dim: !idle.awake
    tooltip: idle.awake ? "Staying awake. Click to lock when idle again" : "Locks when idle. Click to stay awake"
    onClicked: idle.toggle()
}
