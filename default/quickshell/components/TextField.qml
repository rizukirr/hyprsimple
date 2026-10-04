import QtQuick
import qs.theme

// Single-line text field.
Rectangle {
    id: root

    property alias text: input.text
    property string placeholder
    property bool password: false
    // Danger outline, for a rejected value.
    property bool invalid: false
    // When set, Esc emits escaped and stops there. Otherwise Esc carries on to whatever contains the field.
    property bool catchEscape: false
    readonly property bool editing: input.activeFocus
    signal accepted()
    signal editingFinished()
    signal escaped()

    function focusInput() {
        input.forceActiveFocus()
    }

    implicitHeight: Theme.controlSize + Theme.xs
    radius: height / 2
    color: Theme.tint(input.activeFocus ? Theme.tintHover : Theme.tintIdle)
    border.width: 1
    border.color: invalid ? Theme.danger : input.activeFocus ? Theme.accent : Theme.tint(Theme.tintBorder)
    Behavior on color { CAnim {} }

    TextInput {
        id: input
        anchors { fill: parent; leftMargin: Theme.md; rightMargin: Theme.md }
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        color: Theme.fg
        selectionColor: Theme.tint(Theme.tintSelected)
        selectedTextColor: Theme.fg
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        echoMode: root.password ? TextInput.Password : TextInput.Normal
        onAccepted: root.accepted()
        onEditingFinished: root.editingFinished()
        Keys.onEscapePressed: event => {
            if (root.catchEscape) root.escaped()
            else event.accepted = false
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            opacity: input.text === "" ? 1 : 0
            text: root.placeholder
            color: Theme.muted
            Behavior on opacity { Anim {} }
        }
    }
}
