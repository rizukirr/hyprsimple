import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.theme
import qs.components

// Clipboard history from cliphist: search it, pick an entry to copy it again,
// remove one, or clear it all. Pictures are shown as pictures.
PopupPanel {
    id: root

    // One per line of `cliphist list`: the line itself, which is how cliphist
    // names an entry, its id, its text, and whether it is a picture.
    property var entries: []
    readonly property var results: {
        const terms = picker.text.toLowerCase().split(/\s+/).filter(term => term !== "")
        if (terms.length === 0) return entries
        return entries.filter(entry => terms.every(term => entry.text.toLowerCase().includes(term)))
    }
    // Set by the first click on Clear, so wiping the history takes a second one.
    property bool wipeArmed: false
    // Where decoded pictures are kept while the session lasts.
    readonly property string thumbnails: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/hyprsimple-clipboard"

    function parse(text) {
        return text.split("\n").filter(line => line !== "").map(line => {
            const tab = line.indexOf("\t")
            const body = line.slice(tab + 1)
            return { line: line, id: line.slice(0, tab), text: body, image: /^\[\[ binary data .* (png|jpe?g|gif|bmp|webp) /.test(body) }
        })
    }

    function load() {
        if (!lister.running) lister.running = true
    }

    // The entry goes through a file, and reaches wl-copy only when it decoded
    // into something. An empty wl-copy would wipe the clipboard.
    function copy(entry) {
        dismiss()
        Quickshell.execDetached(["sh", "-c",
            'tmp=$(mktemp) && cliphist decode "$1" >"$tmp" && [ -s "$tmp" ] && wl-copy <"$tmp"; rm -f "$tmp"',
            "sh", entry.id])
    }

    function remove(entry) {
        remover.command = ["sh", "-c", 'printf "%s\\n" "$1" | cliphist delete', "sh", entry.line]
        remover.running = true
    }

    function wipe() {
        if (!wipeArmed) {
            wipeArmed = true
            return
        }
        wipeArmed = false
        wiper.running = true
    }

    panelWidth: Theme.clipboardWidth
    focusTarget: picker.inputItem
    onOpenChanged: {
        if (!open) return
        wipeArmed = false
        picker.reset()
        load()
    }

    Process {
        id: lister
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: root.entries = root.parse(text)
        }
    }

    Process {
        id: remover
        onExited: root.load()
    }

    Process {
        id: wiper
        command: ["cliphist", "wipe"]
        onExited: root.load()
    }

    RowLayout {
        width: parent.width

        StyledText {
            Layout.fillWidth: true
            leftPadding: Theme.sm
            text: "Clipboard"
            font.bold: true
        }
        StyledText {
            visible: root.entries.length > 0
            text: `${root.entries.length} entries`
            color: Theme.muted
            font.pixelSize: Theme.fontSizeSmall
        }
        TextButton {
            visible: root.entries.length > 0
            text: root.wipeArmed ? "Clear all? Click again" : "Clear"
            filled: root.wipeArmed
            onClicked: root.wipe()
        }
    }

    PickerList {
        id: picker

        width: parent.width
        placeholder: "Search clipboard"
        emptyText: root.entries.length === 0 ? "Nothing copied yet" : "No matches"
        items: root.results
        active: root.visible
        // As tall as its rows, up to a limit, with room for the empty message.
        listHeight: Math.max(2 * Theme.rowHeight, Math.min(contentHeight, Theme.clipboardMaxHeight))
        onActivated: entry => root.copy(entry)
        onDismissed: root.dismiss()
        // Shift+Delete removes the selected entry. Plain Delete belongs to the text field.
        onKeyPressed: event => {
            if (event.key === Qt.Key_Delete && (event.modifiers & Qt.ShiftModifier) && picker.currentItem) {
                root.remove(picker.currentItem)
                event.accepted = true
            }
        }

        delegate: Item {
            id: row

            required property var modelData
            readonly property string picture: root.thumbnails + "/" + modelData.id
            // Set once the picture has been decoded to a file.
            property bool pictureReady: false

            width: ListView.view.width
            height: modelData.image ? Theme.clipboardImageHeight + 2 * Theme.sm : Theme.rowHeight

            // Decodes this entry's picture once, into the session's runtime folder.
            Process {
                running: row.modelData.image
                command: ["sh", "-c", 'mkdir -p "$2" && { [ -s "$2/$1" ] || cliphist decode "$1" >"$2/$1"; }', "sh", row.modelData.id, root.thumbnails]
                onExited: exitCode => row.pictureReady = exitCode === 0
            }

            RowLayout {
                anchors { fill: parent; leftMargin: Theme.md; rightMargin: Theme.xs }
                spacing: Theme.sm

                Image {
                    visible: row.modelData.image
                    Layout.preferredHeight: Theme.clipboardImageHeight
                    Layout.preferredWidth: Math.min(implicitWidth * Theme.clipboardImageHeight / Math.max(1, implicitHeight), Theme.clipboardWidth / 2)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    source: row.pictureReady ? "file://" + row.picture : ""
                }

                StyledText {
                    Layout.fillWidth: true
                    // A picture's line is its size and type, shown dim beside the picture.
                    text: row.modelData.image ? row.modelData.text.replace(/^\[\[ binary data (.*) \]\]$/, "$1") : row.modelData.text
                    color: row.modelData.image ? Theme.muted : Theme.fg
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                IconButton {
                    visible: hover.hovered
                    icon: Theme.icon.trash
                    iconColor: Theme.danger
                    onClicked: root.remove(row.modelData)
                }
            }

            HoverHandler { id: hover }

            // Under the row's content, so the remove button still gets its clicks.
            StateLayer {
                z: -1
                radius: Theme.radius
                onClicked: picker.activated(row.modelData)
            }
        }
    }
}
