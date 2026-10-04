import QtQuick
import Quickshell.Services.Pipewire
import qs.theme

// Volume of one audio node: the default output or the default microphone.
// Right click mutes, scroll changes the volume. The owner decides what a left click does.
StatusButton {
    id: root

    // Pipewire.defaultAudioSink or Pipewire.defaultAudioSource.
    required property var node
    // Icon names from quiet to loud, and the one for muted.
    required property var levels
    required property string mutedIcon
    // What the tooltip calls it: "Volume" or "Microphone".
    required property string name

    readonly property bool muted: node?.audio?.muted ?? true
    readonly property real volume: node?.audio?.volume ?? 0
    // Wheel delta collected until one notch (120), so touchpads do not jump.
    property real wheelDelta: 0

    visible: node !== null
    icon: muted ? mutedIcon : levels[Math.min(levels.length - 1, Math.floor(volume * levels.length))]
    dim: muted
    tooltip: muted ? `${name} muted` : `${name} ${Math.round(volume * 100)}%`

    // A node's volume is only readable and writable while it is tracked.
    PwObjectTracker {
        objects: [root.node]
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: if (root.node?.audio) root.node.audio.muted = !root.muted
    }

    WheelHandler {
        onWheel: event => {
            root.wheelDelta += event.angleDelta.y
            if (Math.abs(root.wheelDelta) < 120 || !root.node?.audio) return
            const step = root.wheelDelta > 0 ? Theme.volumeStep : -Theme.volumeStep
            root.node.audio.volume = Math.max(0, Math.min(1, root.volume + step))
            root.wheelDelta = 0
        }
    }
}
