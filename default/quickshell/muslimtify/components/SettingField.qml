import QtQuick
import qs.theme
import qs.components

// A labelled text field that shows the saved value, validates on Enter or
// when focus leaves, and emits submitted only for a new, valid value.
// It returns to the saved value when muslimtify rejects a change.
Column {
    id: root

    property string label
    property string value
    property string error
    property string placeholder
    property var validate: null
    signal submitted(string text)

    property string localError: ""
    readonly property string shownError: localError !== "" ? localError : error

    function submit() {
        const text = input.text.trim()
        if (text === value) {
            localError = ""
            return
        }
        localError = validate ? validate(text) : ""
        if (localError === "") submitted(text)
    }

    spacing: Theme.xs

    onValueChanged: if (!input.editing) input.text = value
    onErrorChanged: if (error !== "") input.text = value
    Component.onCompleted: input.text = value

    StyledText {
        visible: text !== ""
        text: root.label
        font.pixelSize: Theme.fontSizeSmall
    }

    TextField {
        id: input
        width: parent.width
        placeholder: root.placeholder
        invalid: root.shownError !== ""
        onEditingFinished: root.submit()
    }

    ErrorLine {
        width: parent.width
        text: root.shownError
    }
}
