import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.theme
import qs.components

// Every keybinding with what it does, to search through. It only shows them:
// picking one closes the panel.
PopupPanel {
    id: root

    // Prints one binding per line: the keys, two or more spaces, the description.
    required property var listCommand

    property var binds: []
    readonly property var results: {
        const terms = picker.text.toLowerCase().split(/\s+/).filter(term => term !== "")
        if (terms.length === 0) return binds
        return binds.filter(bind => terms.every(term => (bind.keys + " " + bind.description).toLowerCase().includes(term)))
    }

    function parse(text) {
        return text.split("\n").filter(line => line.trim() !== "").map(line => {
            const gap = line.search(/\s{2,}/)
            if (gap < 0) return { keys: line.trim(), description: "" }
            return { keys: line.slice(0, gap).trim(), description: line.slice(gap).trim() }
        })
    }

    panelWidth: Theme.keybindsWidth
    focusTarget: picker.inputItem
    // Read on every open, since bindings change with the config.
    onOpenChanged: {
        if (!open) return
        picker.reset()
        if (!lister.running) lister.running = true
    }

    Process {
        id: lister
        command: root.listCommand
        stdout: StdioCollector {
            onStreamFinished: root.binds = root.parse(text)
        }
    }

    RowLayout {
        width: parent.width

        StyledText {
            Layout.fillWidth: true
            leftPadding: Theme.sm
            text: "Keybindings"
            font.bold: true
        }
        StyledText {
            rightPadding: Theme.sm
            visible: root.binds.length > 0
            text: `${root.results.length} of ${root.binds.length}`
            color: Theme.muted
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    PickerList {
        id: picker

        width: parent.width
        placeholder: "Search keys or actions"
        emptyText: root.binds.length === 0 ? "No keybindings found" : "No matches"
        items: root.results
        active: root.visible
        listHeight: items.length === 0 ? emptyHeight : Math.min(contentHeight, Theme.keybindsMaxHeight)
        onActivated: root.dismiss()
        onDismissed: root.dismiss()

        delegate: Item {
            id: row

            required property var modelData

            width: ListView.view.width
            height: Theme.rowHeight

            RowLayout {
                anchors { fill: parent; leftMargin: Theme.md; rightMargin: Theme.md }
                spacing: Theme.md

                StyledText {
                    Layout.preferredWidth: Theme.keybindsKeyWidth
                    text: row.modelData.keys
                    color: Theme.accent
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: row.modelData.description
                    elide: Text.ElideRight
                }
            }

            StateLayer {
                radius: Theme.radius
                onClicked: picker.activated(row.modelData)
            }
        }
    }
}
