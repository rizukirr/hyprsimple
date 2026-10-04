import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.components
import "../lib/Model.js" as Model
import "../components"

// Next prayer on a card, today's times with per-prayer switches for the
// notification and the adhan, and the project links.
Column {
    id: root

    required property var service
    signal settingsRequested()
    signal linkRequested(string url)

    readonly property int nowMinutes: Model.minutesOfDay(service.now)
    readonly property var next: service.next

    spacing: Theme.sm

    PanelHeader {
        width: parent.width
        title: "Muslimtify"
        meta: root.service.scheduleError !== "" ? root.service.scheduleError : Model.subtitle(root.service.now, root.service.config)
        metaIsError: root.service.scheduleError !== ""
        onRefreshClicked: root.service.refresh()
        onSettingsClicked: root.settingsRequested()
    }

    StyledText {
        width: parent.width
        visible: root.service.missing
        text: "muslimtify not found. Install it from " + Model.LINKS.website
        color: Theme.muted
        wrapMode: Text.WordWrap
    }

    // Next prayer: its time, the time left, and progress since the previous prayer.
    Rectangle {
        width: parent.width
        height: card.implicitHeight + 2 * Theme.md
        visible: !root.service.missing && !!root.next
        radius: Theme.radius
        color: Theme.surface
        Behavior on color { CAnim {} }

        Column {
            id: card
            x: Theme.md
            y: Theme.md
            width: parent.width - 2 * Theme.md
            spacing: Theme.xs

            SectionLabel {
                text: root.next ? "Next · " + Model.title(root.next.name) + (root.next.isTomorrow ? " tomorrow" : "") : ""
            }

            Item {
                width: parent.width
                implicitHeight: time.implicitHeight

                StyledText {
                    id: time
                    text: root.next ? root.next.time : ""
                    font.pixelSize: Theme.fontSizeLarge
                    font.bold: true
                }
                StyledText {
                    anchors { right: parent.right; baseline: time.baseline }
                    text: root.next ? "in " + Model.formatDuration(root.next.remaining) : ""
                    color: Theme.accent
                }
            }

            Meter {
                width: parent.width
                value: root.next ? root.next.progress : 0
            }
        }
    }

    SectionLabel {
        visible: !root.service.missing && !!root.service.today
        leftPadding: Theme.sm
        topPadding: Theme.xs
        text: "Today"
    }

    Repeater {
        model: !root.service.missing && root.service.today ? root.service.today.prayers : []

        Rectangle {
            id: row

            required property var modelData
            readonly property var prayerConfig: root.service.config.prayers[modelData.name]
            readonly property string status: Model.prayerState(modelData, root.next, root.nowMinutes)
            readonly property bool isNext: status === "next"
            readonly property color textColor: isNext ? Theme.accent : status === "past" ? Theme.muted : Theme.fg

            width: parent.width
            height: Theme.rowHeight
            radius: height / 2
            color: Theme.tint(isNext ? Theme.tintHover : 0)

            RowLayout {
                anchors { fill: parent; leftMargin: Theme.md; rightMargin: Theme.xs }
                spacing: Theme.xs

                StyledText {
                    Layout.preferredWidth: Theme.prayerNameWidth
                    text: Model.title(row.modelData.name)
                    color: row.textColor
                    font.bold: row.isNext
                }
                StyledText {
                    Layout.fillWidth: true
                    text: row.modelData.time
                    color: row.textColor
                    font.bold: row.isNext
                }
                IconButton {
                    icon: row.prayerConfig.enabled ? Theme.icon.bell : Theme.icon.bellOff
                    iconColor: row.prayerConfig.enabled ? Theme.fg : Theme.muted
                    onClicked: root.service.setPrayerEnabled(row.modelData.name, !row.prayerConfig.enabled)
                }
                IconButton {
                    icon: row.prayerConfig.adhan_enabled ? Theme.icon.volume[2] : Theme.icon.volumeMuted
                    iconColor: row.prayerConfig.adhan_enabled ? Theme.fg : Theme.muted
                    onClicked: root.service.setAdhan(row.modelData.name, !row.prayerConfig.adhan_enabled)
                }
            }
        }
    }

    Rectangle {
        visible: !root.service.missing
        width: parent.width
        height: 1
        color: Theme.tint(Theme.tintSelected)
    }

    // The GitHub and website links, right-aligned.
    Row {
        visible: !root.service.missing
        anchors.right: parent.right
        spacing: Theme.md

        Repeater {
            model: [
                { icon: Model.ICONS.github, label: "Star on GitHub", url: Model.LINKS.github },
                { icon: Model.ICONS.website, label: "Website", url: Model.LINKS.website }
            ]

            StyledText {
                id: link

                required property var modelData

                text: modelData.icon + " " + modelData.label
                color: mouse.containsMouse ? Theme.accent : Theme.fg

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.linkRequested(link.modelData.url)
                }
            }
        }
    }
}
