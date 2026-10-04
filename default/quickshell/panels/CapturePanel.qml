import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.theme
import qs.components

// A few choices and one button, for taking a screenshot or starting a recording.
// Each group of choices is a row of options with one selected. The button runs a
// command built from the selected values, after the panel has left the screen.
PopupPanel {
    id: root

    required property string title
    // [{ name, options: [{ value, label }] }]
    required property var groups
    required property string actionLabel
    // Turns the selected values, one per group in order, into the command to run.
    required property var commandFor
    // Something is already running. The panel then offers only to stop it.
    property bool running: false
    property string stopLabel
    property var stopCommand: []

    // The selected value of each group. Kept between opens, so the last choice is the default.
    property var values: groups.map(group => group.options[0].value)
    // The group the arrow keys act on.
    property int focused: 0
    // The command to run once the panel is off the screen.
    property var pending: null

    function choose(group, value) {
        const next = [...values]
        next[group] = value
        values = next
    }

    function step(delta) {
        const options = groups[focused].options
        const index = options.findIndex(option => option.value === values[focused])
        choose(focused, options[Math.max(0, Math.min(options.length - 1, index + delta))].value)
    }

    function go() {
        pending = running ? stopCommand : commandFor(values)
        dismiss()
    }

    panelWidth: Theme.captureWidth
    focusTarget: keys
    onOpenChanged: if (open) focused = 0
    // Not started until the panel is gone, or a screenshot would have the panel in it.
    onVisibleChanged: if (!visible && pending) afterClose.restart()

    Timer {
        id: afterClose
        interval: Theme.captureDelay
        onTriggered: {
            Quickshell.execDetached(root.pending)
            root.pending = null
        }
    }

    Item {
        id: keys

        width: parent.width
        height: body.implicitHeight

        // Left and Right change the choice, Up, Down and Tab move between the rows,
        // Enter runs. Anything else carries on to the panel, which closes on Esc.
        Keys.onPressed: event => {
            const rows = root.groups.length
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.go()
            else if (root.running) return
            else if (event.key === Qt.Key_Left) root.step(-1)
            else if (event.key === Qt.Key_Right) root.step(1)
            else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) root.focused = (root.focused + 1) % rows
            else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) root.focused = (root.focused + rows - 1) % rows
            else return
            event.accepted = true
        }

        Column {
            id: body
            width: parent.width
            spacing: Theme.md

            StyledText {
                leftPadding: Theme.sm
                text: root.title
                font.bold: true
            }

            Repeater {
                model: root.running ? [] : root.groups

                RowLayout {
                    id: group

                    required property var modelData
                    required property int index

                    width: body.width
                    spacing: Theme.md

                    // Accent on the row the arrow keys act on.
                    StyledText {
                        Layout.preferredWidth: Theme.captureLabelWidth
                        leftPadding: Theme.sm
                        text: group.modelData.name
                        color: root.focused === group.index ? Theme.accent : Theme.muted
                    }
                    Segmented {
                        options: group.modelData.options
                        value: root.values[group.index]
                        onChanged: value => {
                            root.focused = group.index
                            root.choose(group.index, value)
                        }
                    }
                    Item { Layout.fillWidth: true }
                }
            }

            RowLayout {
                width: parent.width

                Item { Layout.fillWidth: true }
                TextButton {
                    text: root.running ? root.stopLabel : root.actionLabel
                    filled: true
                    onClicked: root.go()
                }
            }
        }
    }
}
