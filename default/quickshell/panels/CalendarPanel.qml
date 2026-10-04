import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.theme
import qs.components

PopupPanel {
    id: root

    property int year
    property int month
    // Monday-first weeks.
    readonly property var weekLocale: Qt.locale("en_GB")
    property real wheelDelta: 0

    function showToday() {
        year = clock.date.getFullYear()
        month = clock.date.getMonth()
    }

    function apply(months) {
        const d = new Date(year, month + months, 1)
        year = d.getFullYear()
        month = d.getMonth()
    }

    panelWidth: 7 * Theme.cellSize + 2 * Theme.lg
    onOpenChanged: if (open) showToday()
    Component.onCompleted: showToday()

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    StyledText {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: Qt.formatDate(clock.date, "dddd, d MMMM yyyy")
        color: Theme.muted
        font.pixelSize: Theme.fontSizeSmall
    }

    RowLayout {
        width: parent.width

        IconButton {
            icon: Theme.icon.left
            onClicked: root.apply(-1)
        }

        // Clicking the month title jumps back to the current month.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.controlSize
            radius: height / 2
            color: "transparent"

            StyledText {
                anchors.centerIn: parent
                text: root.weekLocale.standaloneMonthName(root.month) + " " + root.year
                color: Theme.accent
                font.weight: Font.Medium
            }

            StateLayer {
                onClicked: root.showToday()
            }
        }

        IconButton {
            icon: Theme.icon.right
            onClicked: root.apply(1)
        }
    }

    DayOfWeekRow {
        width: parent.width
        locale: root.weekLocale
        spacing: 0
        padding: 0

        delegate: StyledText {
            required property string shortName
            horizontalAlignment: Text.AlignHCenter
            text: shortName
            color: Theme.muted
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    Item {
        width: parent.width
        height: days.implicitHeight
        clip: true

        WheelHandler {
            onWheel: event => {
                root.wheelDelta += event.angleDelta.y
                if (Math.abs(root.wheelDelta) < 120) return
                root.apply(root.wheelDelta > 0 ? -1 : 1)
                root.wheelDelta = 0
            }
        }

        MonthGrid {
            id: days

            width: parent.width
            month: root.month
            year: root.year
            locale: root.weekLocale
            spacing: 0
            padding: 0

            delegate: Item {
                id: cell

                required property var model
                readonly property int weekday: model.date.getUTCDay()
                readonly property bool weekend: weekday === 0 || weekday === 6

                implicitWidth: Theme.cellSize
                implicitHeight: Theme.cellSize
                opacity: model.month === root.month ? 1 : 0.4

                Rectangle {
                    anchors.centerIn: parent
                    width: Theme.cellSize - Theme.xs
                    height: width
                    radius: width / 2
                    visible: cell.model.today
                    color: Theme.accent
                    Behavior on color { CAnim {} }
                }

                StyledText {
                    anchors.centerIn: parent
                    text: cell.model.day
                    font.bold: cell.model.today
                    color: cell.model.today ? Theme.onAccent : cell.weekend ? Theme.muted : Theme.fg
                }
            }
        }
    }
}
