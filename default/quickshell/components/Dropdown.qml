import QtQuick
import QtQuick.Layouts
import qs.theme

// Labelled choice from a list. It opens in place, pushing what is below it down,
// with a search field when searchable. Options are strings or { value, label }.
Column {
    id: root

    property string label
    property string value
    property var options: []
    property bool searchable: false
    property bool expanded: false
    signal changed(string value)

    function optionValue(option) {
        return typeof option === "string" ? option : option.value
    }

    function optionLabel(option) {
        return typeof option === "string" ? option : option.label
    }

    readonly property string currentLabel: {
        const match = options.find(o => optionValue(o) === value)
        return match ? optionLabel(match) : value
    }
    readonly property var filtered: {
        const query = search.text.trim().toLowerCase()
        return query === "" ? options : options.filter(o => optionLabel(o).toLowerCase().includes(query))
    }

    spacing: Theme.xs

    onExpandedChanged: {
        if (expanded && searchable) Qt.callLater(() => search.focusInput())
        else search.text = ""
    }

    StyledText {
        visible: text !== ""
        text: root.label
        font.pixelSize: Theme.fontSizeSmall
    }

    Rectangle {
        width: parent.width
        height: Theme.controlSize + Theme.xs
        radius: height / 2
        color: Theme.tint(Theme.tintIdle)
        border.width: 1
        border.color: root.expanded ? Theme.accent : Theme.tint(Theme.tintBorder)

        RowLayout {
            anchors { fill: parent; leftMargin: Theme.md; rightMargin: Theme.sm }

            StyledText {
                Layout.fillWidth: true
                text: root.currentLabel
                elide: Text.ElideRight
            }
            Icon {
                text: root.expanded ? Theme.icon.collapse : Theme.icon.expand
                color: Theme.muted
            }
        }

        StateLayer {
            onClicked: root.expanded = !root.expanded
        }
    }

    TextField {
        id: search
        width: parent.width
        visible: root.expanded && root.searchable
        placeholder: "Search"
        catchEscape: true
        onEscaped: root.expanded = false
    }

    ListView {
        width: parent.width
        height: Math.min(contentHeight, Theme.dropdownMaxHeight)
        visible: root.expanded
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.filtered

        delegate: Rectangle {
            id: option

            required property var modelData
            readonly property bool current: root.optionValue(modelData) === root.value

            width: ListView.view.width
            height: Theme.controlSize + Theme.xs
            radius: height / 2
            color: "transparent"

            StyledText {
                anchors { fill: parent; leftMargin: Theme.md; rightMargin: Theme.md }
                text: root.optionLabel(option.modelData)
                elide: Text.ElideRight
                color: option.current ? Theme.accent : Theme.fg
                font.weight: option.current ? Font.Medium : Font.Normal
            }

            StateLayer {
                onClicked: {
                    root.expanded = false
                    root.changed(root.optionValue(option.modelData))
                }
            }
        }
    }
}
