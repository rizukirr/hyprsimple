import QtQuick
import qs.theme

// A few options side by side, one selected. Options are { value, label }.
Rectangle {
    id: root

    property var options: []
    property string value
    signal changed(string value)

    implicitWidth: row.width + 2 * Theme.xs
    implicitHeight: Theme.controlSize + 2 * Theme.xs
    radius: height / 2
    color: Theme.tint(Theme.tintIdle)

    Row {
        id: row
        anchors.centerIn: parent

        Repeater {
            model: root.options

            Rectangle {
                id: option

                required property var modelData
                readonly property bool current: modelData.value === root.value

                width: label.implicitWidth + 2 * Theme.md
                height: Theme.controlSize
                radius: height / 2
                color: current ? Theme.accent : Qt.alpha(Theme.accent, 0)
                Behavior on color { CAnim {} }

                StyledText {
                    id: label
                    anchors.centerIn: parent
                    text: option.modelData.label
                    color: option.current ? Theme.onAccent : Theme.fg
                }

                StateLayer {
                    onClicked: root.changed(option.modelData.value)
                }
            }
        }
    }
}
