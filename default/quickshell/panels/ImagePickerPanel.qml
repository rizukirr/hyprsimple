import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.theme
import qs.components

// A carousel of pictures to pick one from, used for themes and for wallpapers.
// The choices come from a command that prints "key<TAB>label<TAB>image" rows,
// and picking one runs another command with its key.
PopupPanel {
    id: root

    required property string title
    // Prints one row per choice. Rows are shown as they arrive.
    required property var listCommand
    // Prints the key of the choice in use now, so the carousel can start on it.
    required property var currentCommand
    // Run with the picked key added as its last argument.
    required property var applyCommand

    // One per row: key, name, picture, and the colors found in the label.
    property var entries: []
    // Rows read but not yet shown, see the batch timer.
    property var arrived: []
    property string currentKey: ""
    readonly property var results: {
        const terms = search.text.toLowerCase().split(/\s+/).filter(term => term !== "")
        if (terms.length === 0) return entries
        return entries.filter(entry => terms.every(term => entry.name.toLowerCase().includes(term)))
    }
    property int current: 0
    // Set once the carousel has been moved to the choice in use, so later rows do not move it back.
    property bool placed: false

    // A label may carry color swatches as markup, the form the list scripts print them in.
    function parse(line) {
        const [key, label, image] = line.split("\t")
        if (!key) return null
        // Each match is background='#rrggbb', and the color is what follows the first quote.
        const swatches = ((label ?? "").match(/background='#[0-9a-fA-F]{6}'/g) ?? []).map(match => match.slice(12, 19))
        const name = (label ?? key).replace(/<[^>]*>/g, "").trim()
        return { key: key, name: name, image: image ?? "", swatches: swatches }
    }

    function move(step) {
        if (results.length === 0) return
        current = Math.max(0, Math.min(results.length - 1, current + step))
    }

    function apply(entry) {
        if (!entry) return
        dismiss()
        Quickshell.execDetached([...applyCommand, entry.key])
    }

    // Start on the choice in use, once it and its row are both known.
    // Not named place: PopupPanel has a function of that name that positions the panel,
    // and a second one here would replace it.
    function startOnCurrent() {
        if (placed || currentKey === "" || search.text !== "") return
        const index = entries.findIndex(entry => entry.key === currentKey)
        if (index < 0) return
        current = index
        placed = true
    }

    panelWidth: Theme.pickerWidth
    focusTarget: search.inputItem
    onResultsChanged: if (placed || search.text !== "") current = Math.min(current, Math.max(0, results.length - 1))
    onOpenChanged: {
        if (!open) return
        search.text = ""
        entries = []
        arrived = []
        current = 0
        placed = false
        currentKey = ""
        lister.running = false
        lister.running = true
        currentReader.running = true
    }

    Process {
        id: lister
        command: root.listCommand
        stdout: SplitParser {
            onRead: line => {
                const entry = root.parse(line)
                if (!entry) return
                root.arrived.push(entry)
                batch.start()
            }
        }
    }

    // Rows arrive one at a time, and each change to the list rebuilds the carousel.
    // They are gathered and added a few times a second instead.
    Timer {
        id: batch
        interval: 120
        onTriggered: {
            root.entries = [...root.entries, ...root.arrived]
            root.arrived = []
            root.startOnCurrent()
        }
    }

    Process {
        id: currentReader
        command: root.currentCommand
        stdout: StdioCollector {
            onStreamFinished: {
                root.currentKey = text.trim()
                root.startOnCurrent()
            }
        }
    }

    RowLayout {
        width: parent.width
        spacing: Theme.md

        StyledText {
            leftPadding: Theme.sm
            text: root.title
            font.bold: true
        }
        TextField {
            id: search
            Layout.fillWidth: true
            icon: Theme.icon.search
            placeholder: "Search"
            catchEscape: true
            // The first Esc clears what was typed, the next one closes.
            onEscaped: {
                if (text !== "") text = ""
                else root.dismiss()
            }
            onAccepted: root.apply(root.results[root.current])
            // Left and Right move through the pictures, since the search text is short
            // and the pictures are what is being chosen.
            onKeyPressed: event => {
                const ctrl = event.modifiers & Qt.ControlModifier
                if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab || (ctrl && event.key === Qt.Key_N)) root.move(1)
                else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab || (ctrl && event.key === Qt.Key_P)) root.move(-1)
                else if (event.key === Qt.Key_PageDown) root.move(Theme.pickerPageStep)
                else if (event.key === Qt.Key_PageUp) root.move(-Theme.pickerPageStep)
                else return
                event.accepted = true
            }
        }
        StyledText {
            rightPadding: Theme.sm
            text: root.results.length === 0 ? "" : `${root.current + 1} of ${root.results.length}`
            color: Theme.muted
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    // The carousel. The chosen picture sits in the middle at full size, its neighbours
    // smaller and dimmer on either side.
    ListView {
        id: view

        width: parent.width
        height: Theme.pickerCardHeight + Theme.rowHeight
        orientation: ListView.Horizontal
        spacing: Theme.sm
        clip: true
        model: root.visible ? root.results : []
        // A new model sends the view back to its first item. A binding would not notice,
        // and writing the same index again moves nothing, so the view is put back on the
        // choice by hand each time the list changes.
        onCountChanged: {
            currentIndex = root.current
            Qt.callLater(() => view.positionViewAtIndex(root.current, ListView.Center))
        }
        Connections {
            target: root
            function onCurrentChanged() { view.currentIndex = root.current }
        }
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: (width - Theme.pickerCardWidth) / 2
        preferredHighlightEnd: preferredHighlightBegin + Theme.pickerCardWidth
        highlightMoveDuration: Theme.springAnim
        // Dragging or scrolling the carousel changes the choice too.
        onCurrentIndexChanged: if (moving) root.current = currentIndex

        WheelHandler {
            property real collected: 0
            onWheel: event => {
                collected += event.angleDelta.y + event.angleDelta.x
                if (Math.abs(collected) < 120) return
                root.move(collected > 0 ? -1 : 1)
                collected = 0
            }
        }

        delegate: Item {
            id: card

            required property var modelData
            required property int index
            readonly property bool chosen: index === root.current

            width: Theme.pickerCardWidth
            height: view.height

            ClippingRectangle {
                id: picture

                anchors.horizontalCenter: parent.horizontalCenter
                width: Theme.pickerCardWidth
                height: Theme.pickerCardHeight
                radius: Theme.radius
                color: Theme.surface
                border.width: card.chosen ? 2 : 0
                border.color: Theme.accent
                scale: card.chosen ? 1 : 0.86
                opacity: card.chosen ? 1 : 0.55
                Behavior on scale { Spring {} }
                Behavior on opacity { Anim {} }

                Image {
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize: Qt.size(2 * Theme.pickerCardWidth, 2 * Theme.pickerCardHeight)
                    source: card.modelData.image !== "" ? "file://" + card.modelData.image : ""
                }

                StateLayer {
                    radius: Theme.radius
                    // A click on a neighbour brings it to the middle, a click on the middle one picks it.
                    onClicked: {
                        if (card.chosen) root.apply(card.modelData)
                        else root.current = card.index
                    }
                }
            }

            Row {
                anchors { top: picture.bottom; topMargin: Theme.sm; horizontalCenter: parent.horizontalCenter }
                spacing: Theme.sm
                opacity: card.chosen ? 1 : 0.55
                Behavior on opacity { Anim {} }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Repeater {
                        model: card.modelData.swatches

                        Rectangle {
                            required property string modelData
                            width: Theme.swatchSize
                            height: Theme.swatchSize
                            radius: width / 2
                            color: modelData
                            border.width: 1
                            border.color: Theme.tint(Theme.tintBorder)
                        }
                    }
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: card.modelData.name
                    color: card.chosen ? Theme.accent : Theme.fg
                    font.weight: card.chosen ? Font.Medium : Font.Normal
                }
            }
        }

        StyledText {
            anchors.centerIn: parent
            visible: root.results.length === 0
            text: root.entries.length === 0 ? "Loading…" : "No matches"
            color: Theme.muted
        }
    }
}
