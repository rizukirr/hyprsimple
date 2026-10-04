import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.theme
import qs.components

// One notification. Click runs its default action and closes it, right click only
// closes it. The line along the bottom is the time it has left, held while hovered.
//
// It draws a record, a copy of what the notification said. The notification itself
// is only needed for its actions and its countdown, and a card in the history has none.
Rectangle {
    id: root

    // What to show: { appName, summary, body, picture, critical }.
    required property var record
    // The live notification, null for a card in the history.
    property Notification notification: null
    // Counts replacements of a live notification, which restart its countdown.
    property int stamp: 0
    readonly property bool critical: record.critical
    readonly property int timeout: notification ? Notifications.timeoutFor(notification) : 0
    // 1 when it appears, 0 when its time is up.
    property real remaining: 1
    readonly property string picture: record.picture
    signal dismissed()

    implicitWidth: Theme.notifyWidth
    implicitHeight: body.implicitHeight + 2 * Theme.md
    radius: Theme.radius
    color: Theme.surface
    border.width: critical ? 1 : 0
    border.color: Theme.danger
    clip: true
    Behavior on color { CAnim {} }

    NumberAnimation on remaining {
        id: countdown
        from: 1
        to: 0
        duration: Math.max(1, root.timeout)
        running: root.timeout > 0
        paused: running && hover.containsMouse
        onFinished: root.notification?.expire()
    }

    onStampChanged: if (timeout > 0) countdown.restart()

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (root.notification && mouse.button === Qt.LeftButton) {
                const action = root.notification.actions.find(a => a.identifier === "default")
                if (action) action.invoke()
            }
            root.notification?.dismiss()
            root.dismissed()
        }
    }

    Row {
        id: body
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.md }
        spacing: Theme.md

        Item {
            width: Theme.notifyIconSize
            height: Theme.notifyIconSize

            Image {
                anchors.fill: parent
                visible: root.picture !== ""
                source: root.picture
                sourceSize: Qt.size(2 * width, 2 * height)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                // Read from the file every time. A sender may reuse one path for a
                // picture that changes, and the cached one would be the old picture.
                cache: false
            }

            Icon {
                anchors.centerIn: parent
                visible: root.picture === ""
                text: Theme.icon.bell
                color: root.critical ? Theme.danger : Theme.accent
                font.pixelSize: Theme.notifyIconSize - Theme.sm
            }
        }

        Column {
            width: parent.width - Theme.notifyIconSize - Theme.md
            spacing: Theme.xs

            StyledText {
                width: parent.width
                visible: text !== ""
                text: root.record.appName
                color: Theme.muted
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight
            }

            StyledText {
                width: parent.width
                text: root.record.summary
                font.weight: Font.Medium
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            StyledText {
                width: parent.width
                visible: text !== ""
                text: root.record.body
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                maximumLineCount: Theme.notifyBodyLines
                elide: Text.ElideRight
                onLinkActivated: link => Qt.openUrlExternally(link)
            }

            Flow {
                width: parent.width
                spacing: Theme.sm
                topPadding: Theme.xs
                visible: actions.count > 0

                Repeater {
                    id: actions
                    model: root.notification?.actions.filter(a => a.identifier !== "default") ?? []

                    TextButton {
                        required property var modelData
                        text: modelData.text
                        onClicked: {
                            modelData.invoke()
                            root.notification?.dismiss()
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        anchors { left: parent.left; bottom: parent.bottom }
        visible: root.timeout > 0 && root.notification !== null
        width: parent.width * root.remaining
        height: 2
        color: root.critical ? Theme.danger : Theme.accent
    }
}
