import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs.theme
import qs.components

// Volume, mute and device choice for one direction: output, or microphone input.
PopupPanel {
    id: root

    // true for output devices, false for inputs.
    required property bool output
    required property string title
    // Icon names from quiet to loud, and the one for muted.
    required property var levels
    required property string mutedIcon

    readonly property var node: output ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource
    readonly property bool muted: node?.audio?.muted ?? true
    readonly property real volume: node?.audio?.volume ?? 0
    readonly property var devicesNow: Pipewire.nodes.values.filter(n => !n.isStream && n.audio && n.isSink === output)
    // The list on screen. Replaced only when membership changes, so rows are not rebuilt on every volume change.
    property var devices: []

    function sync() {
        if (!sameList(devices, devicesNow)) devices = devicesNow
    }

    function choose(device) {
        if (output) Pipewire.preferredDefaultAudioSink = device
        else Pipewire.preferredDefaultAudioSource = device
    }

    onDevicesNowChanged: sync()
    Component.onCompleted: sync()

    // A node's volume is only readable and writable while it is tracked.
    PwObjectTracker {
        objects: [root.node]
    }

    RowLayout {
        width: parent.width

        StyledText {
            Layout.fillWidth: true
            leftPadding: Theme.sm
            text: root.title
            font.bold: true
        }
        // On means audible.
        Toggle {
            visible: root.node !== null
            checked: !root.muted
            onToggled: root.node.audio.muted = !root.muted
        }
    }

    RowLayout {
        width: parent.width
        visible: root.node !== null
        spacing: Theme.sm
        opacity: root.muted ? Theme.dimmed : 1
        Behavior on opacity { Anim {} }

        Icon {
            Layout.leftMargin: Theme.sm
            text: root.muted ? root.mutedIcon
                : root.levels[Math.min(root.levels.length - 1, Math.floor(root.volume * root.levels.length))]
        }
        Slider {
            Layout.fillWidth: true
            value: root.volume
            onMoved: value => root.node.audio.volume = value
        }
        StyledText {
            Layout.preferredWidth: Theme.percentWidth
            horizontalAlignment: Text.AlignRight
            text: `${Math.round(root.volume * 100)}%`
        }
    }

    StyledText {
        width: parent.width
        leftPadding: Theme.sm
        topPadding: Theme.xs
        color: Theme.muted
        font.pixelSize: Theme.fontSizeSmall
        text: root.devices.length === 0 ? "No devices" : "Devices"
    }

    Flickable {
        width: parent.width
        height: Math.min(list.implicitHeight, Theme.listMaxHeight)
        visible: root.devices.length > 0
        contentHeight: list.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: list
            width: parent.width

            Repeater {
                model: root.devices

                ListRow {
                    required property var modelData
                    width: list.width
                    icon: root.output ? Theme.icon.speaker : Theme.icon.mic[0]
                    title: modelData.description || modelData.nickname || modelData.name
                    active: modelData === root.node
                    onClicked: root.choose(modelData)
                }
            }
        }
    }
}
