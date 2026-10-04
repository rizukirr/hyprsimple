import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.theme
import qs.components

// A few choices and one button, for starting a capture such as a recording.
// Each group of choices is a row of options with one selected. The button runs a
// command built from the selected values, after the panel has left the screen.
// When the choice is to capture a window, a second page asks which one first.
PopupPanel {
    id: root

    required property string title
    // [{ name, options: [{ value, label }] }]
    required property var groups
    required property string actionLabel
    // Turns the selected values, one per group in order, into the command to run.
    // When a window was chosen, its place on screen is passed as well, as "x,y wxh".
    required property var commandFor
    // The value of the first group that means "a window". Choosing it leads to the
    // page that asks which window. Leave empty for a panel with no such choice.
    property string windowValue
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
    // The page that asks which window is showing.
    property bool choosing: false
    // The windows on screen: title, app, icon and place.
    property var windows: []
    readonly property var windowResults: {
        const terms = picker.text.toLowerCase().split(/\s+/).filter(term => term !== "")
        if (terms.length === 0) return windows
        return windows.filter(w => terms.every(term => (w.title + " " + w.app).toLowerCase().includes(term)))
    }

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
        if (running) return runAfterClose(stopCommand)
        // A window has to be chosen first. The list is read fresh each time.
        if (windowValue !== "" && values[0] === windowValue) {
            if (!lister.running) lister.running = true
            return
        }
        runAfterClose(commandFor(values, ""))
    }

    function runAfterClose(command) {
        pending = command
        dismiss()
    }

    // The windows on the workspaces the monitors are showing, a special workspace
    // that is open included. Hidden and unmapped windows are left out: they still
    // report a place, and recording it would record an empty patch of screen.
    function readWindows(text) {
        const [monitors, clients] = text.split("\n---\n").map(part => JSON.parse(part))
        const shown = []
        for (const m of monitors) shown.push(m.activeWorkspace.id, m.specialWorkspace.id)
        return clients
            .filter(c => c.mapped && !c.hidden && c.workspace.id !== 0 && shown.includes(c.workspace.id))
            .map(c => ({
                title: c.title || c.class,
                app: c.class,
                icon: DesktopEntries.heuristicLookup(c.class)?.icon ?? "",
                geometry: `${c.at[0]},${c.at[1]} ${c.size[0]}x${c.size[1]}`
            }))
    }

    Process {
        id: lister
        command: ["sh", "-c", "hyprctl -j monitors && echo --- && hyprctl -j clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.windows = root.readWindows(text)
                } catch (e) {
                    console.log("capture: could not read the window list:", e)
                    root.windows = []
                }
                // With one window there is nothing to ask. With none, the command
                // runs without a place and reports that itself.
                if (root.windows.length === 1) root.runAfterClose(root.commandFor(root.values, root.windows[0].geometry))
                else if (root.windows.length === 0) root.runAfterClose(root.commandFor(root.values, ""))
                else {
                    picker.reset()
                    root.choosing = true
                    Qt.callLater(() => picker.inputItem.forceActiveFocus())
                }
            }
        }
    }

    function back() {
        choosing = false
        Qt.callLater(() => keys.forceActiveFocus())
    }

    panelWidth: Theme.captureWidth
    focusTarget: keys
    onOpenChanged: {
        if (!open) return
        focused = 0
        choosing = false
    }
    // Not started until the panel is gone, or the capture would have the panel in it.
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
        visible: !root.choosing

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

    // The page that asks which window.
    Column {
        width: parent.width
        visible: root.choosing
        spacing: Theme.md

        RowLayout {
            width: parent.width

            IconButton {
                icon: Theme.icon.left
                onClicked: root.back()
            }
            StyledText {
                Layout.fillWidth: true
                text: "Which window?"
                font.bold: true
            }
        }

        PickerList {
            id: picker

            width: parent.width
            placeholder: "Search windows"
            emptyText: "No matching window"
            items: root.windowResults
            active: root.choosing
            listHeight: items.length === 0 ? emptyHeight : Math.min(contentHeight, Theme.listMaxHeight)
            onActivated: window => root.runAfterClose(root.commandFor(root.values, window.geometry))
            // Esc with nothing typed goes back to the choices, not out of the panel.
            onDismissed: root.back()

            delegate: Item {
                id: row

                required property var modelData

                width: ListView.view.width
                height: Theme.appRowHeight

                RowLayout {
                    anchors { fill: parent; leftMargin: Theme.sm; rightMargin: Theme.sm }
                    spacing: Theme.md

                    Image {
                        Layout.preferredWidth: Theme.appIconSize
                        Layout.preferredHeight: Theme.appIconSize
                        sourceSize: Qt.size(2 * Theme.appIconSize, 2 * Theme.appIconSize)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.title
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.app
                            color: Theme.muted
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
                        }
                    }
                }

                StateLayer {
                    radius: Theme.radius
                    onClicked: picker.activated(row.modelData)
                }
            }
        }
    }
}
