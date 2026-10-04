import QtQuick
import qs.theme

// Single-line text field.
Rectangle {
    id: root

    property alias text: input.text
    property string placeholder
    // Material Symbols name shown at the left, or "" for none.
    property string icon
    property bool password: false
    // Danger outline, for a rejected value.
    property bool invalid: false
    // When set, Esc emits escaped and stops there. Otherwise Esc carries on to whatever contains the field.
    property bool catchEscape: false
    readonly property bool editing: input.activeFocus
    // The item that actually holds the keyboard focus.
    readonly property Item inputItem: input
    signal accepted()
    signal editingFinished()
    signal escaped()
    // Every key press, before the field handles it. Set event.accepted to keep it from the field.
    signal keyPressed(var event)

    function focusInput() {
        input.forceActiveFocus()
    }

    implicitHeight: Theme.controlSize + Theme.xs
    radius: height / 2
    color: Theme.tint(input.activeFocus ? Theme.tintHover : Theme.tintIdle)
    border.width: 1
    border.color: invalid ? Theme.danger : input.activeFocus ? Theme.accent : Theme.tint(Theme.tintBorder)
    Behavior on color { CAnim {} }

    Icon {
        id: glyph
        anchors { left: parent.left; leftMargin: Theme.md; verticalCenter: parent.verticalCenter }
        visible: text !== ""
        text: root.icon
        color: Theme.muted
    }

    TextInput {
        id: input
        anchors { fill: parent; leftMargin: glyph.visible ? glyph.width + Theme.md + Theme.sm : Theme.md; rightMargin: Theme.md }
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
        Keys.onPressed: event => root.keyPressed(event)
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
