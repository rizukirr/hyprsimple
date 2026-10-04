import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.components
import "../lib/Model.js" as Model
import "../components"

// Every muslimtify setting. Each change is saved by muslimtify itself, and the
// fields follow its config file, so a rejected value snaps back.
Column {
    id: root

    required property var service
    signal closeRequested()

    readonly property var location: service.config.location
    readonly property var calculation: service.config.calculation
    readonly property var notification: service.config.notification
    readonly property string timeFormat: String(service.config.display.time_format)

    spacing: Theme.sm

    PanelHeader {
        width: parent.width
        title: "Settings"
        meta: "Saved by muslimtify"
        settingsOpen: true
        onRefreshClicked: root.service.refresh()
        onSettingsClicked: root.closeRequested()
    }

    Flickable {
        width: parent.width
        height: Math.min(sections.implicitHeight, Theme.settingsMaxHeight)
        contentHeight: sections.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: sections
            width: parent.width
            spacing: Theme.sm

            SectionLabel { text: "Time format" }

            Segmented {
                options: Model.TIME_FORMATS
                value: root.timeFormat
                onChanged: value => {
                    if (value !== root.timeFormat) root.service.setTimeFormat(value)
                }
            }
            ErrorLine {
                width: parent.width
                text: root.service.error("display.timeFormat")
            }

            SectionLabel { topPadding: Theme.sm; text: "Location" }

            RowLayout {
                width: parent.width

                StyledText {
                    Layout.fillWidth: true
                    text: root.location.auto_detect ? "Auto-detected" : "Set manually"
                    color: Theme.muted
                }
                TextButton {
                    text: "Detect from IP"
                    onClicked: root.service.detectLocation()
                }
            }
            ErrorLine {
                width: parent.width
                text: root.service.error("location.detect")
            }

            Row {
                width: parent.width
                spacing: Theme.md

                SettingField {
                    width: (parent.width - parent.spacing) / 2
                    label: "Latitude"
                    value: String(root.location.latitude)
                    error: root.service.error("location.coordinates")
                    validate: Model.validateLatitude
                    onSubmitted: text => root.service.setCoordinates(text, String(root.location.longitude))
                }
                SettingField {
                    width: (parent.width - parent.spacing) / 2
                    label: "Longitude"
                    value: String(root.location.longitude)
                    validate: Model.validateLongitude
                    onSubmitted: text => root.service.setCoordinates(String(root.location.latitude), text)
                }
            }

            StyledText {
                width: parent.width
                text: "Changing coordinates clears the city and country and sets the timezone from them."
                color: Theme.muted
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            Dropdown {
                width: parent.width
                label: "Timezone"
                searchable: true
                value: root.location.timezone
                options: root.service.timezones.length > 0 ? root.service.timezones : [root.location.timezone]
                onChanged: value => {
                    if (value !== root.location.timezone) root.service.setLocationField("timezone", value)
                }
            }
            ErrorLine {
                width: parent.width
                text: root.service.error("location.timezone")
            }

            Row {
                width: parent.width
                spacing: Theme.md

                SettingField {
                    width: (parent.width - parent.spacing) * 2 / 3
                    label: "City"
                    value: root.location.city
                    error: root.service.error("location.city")
                    onSubmitted: text => root.service.setLocationField("city", text)
                }
                SettingField {
                    width: (parent.width - parent.spacing) / 3
                    label: "Country"
                    value: root.location.country
                    error: root.service.error("location.country")
                    validate: Model.validateCountry
                    onSubmitted: text => root.service.setLocationField("country", text)
                }
            }

            SettingField {
                width: parent.width
                label: "Refresh interval (seconds, 0 turns it off)"
                value: String(root.location.refresh_interval)
                error: root.service.error("location.refreshInterval")
                validate: Model.validateRefreshInterval
                onSubmitted: text => root.service.setLocationField("refreshInterval", text)
            }

            RowLayout {
                width: parent.width

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText { text: "Use GPS" }
                    StyledText {
                        text: "Read the location from gpsd"
                        color: Theme.muted
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
                Toggle {
                    checked: root.location.use_gps
                    onToggled: root.service.setGps(!root.location.use_gps)
                }
            }
            ErrorLine {
                width: parent.width
                text: root.service.error("location.gps")
            }

            SectionLabel { topPadding: Theme.sm; text: "Calculation" }

            Dropdown {
                width: parent.width
                label: "Method"
                searchable: true
                value: root.calculation.method
                options: root.service.methods.length > 0 ? root.service.methods : [root.calculation.method]
                onChanged: value => {
                    if (value !== root.calculation.method) root.service.setMethod(value)
                }
            }
            ErrorLine {
                width: parent.width
                text: root.service.error("calculation.method")
            }

            Dropdown {
                width: parent.width
                label: "Madzhab"
                value: root.calculation.madhab
                options: Model.MADZHABS
                onChanged: value => {
                    if (value !== root.calculation.madhab) root.service.setMadzhab(value)
                }
            }
            ErrorLine {
                width: parent.width
                text: root.service.error("calculation.madzhab")
            }

            // One prayer's reminders and offset. Notification and adhan are toggled from the Today rows.
            Repeater {
                model: Model.PRAYERS

                Column {
                    id: prayer

                    required property string modelData
                    readonly property var prayerConfig: root.service.config.prayers[modelData]

                    width: sections.width
                    spacing: Theme.sm

                    SectionLabel { topPadding: Theme.sm; text: Model.title(prayer.modelData) }

                    Row {
                        width: parent.width
                        spacing: Theme.md

                        SettingField {
                            width: (parent.width - parent.spacing) * 2 / 3
                            label: "Reminders (minutes before)"
                            value: Model.formatReminders(prayer.prayerConfig.reminders)
                            placeholder: "30, 15, 5"
                            error: root.service.error(prayer.modelData + ".reminders")
                            validate: Model.validateReminders
                            onSubmitted: text => root.service.setReminders(prayer.modelData, Model.parseReminders(text))
                        }
                        SettingField {
                            width: (parent.width - parent.spacing) / 3
                            label: "Offset (minutes)"
                            value: String(prayer.prayerConfig.offset)
                            error: root.service.error(prayer.modelData + ".offset")
                            validate: Model.validateOffset
                            onSubmitted: text => root.service.setOffset(prayer.modelData, text)
                        }
                    }
                }
            }

            SectionLabel { topPadding: Theme.sm; text: "Notifications" }

            Dropdown {
                width: parent.width
                label: "Urgency"
                value: root.notification.urgency
                options: Model.URGENCIES
                onChanged: value => {
                    if (value !== root.notification.urgency) root.service.setUrgency(value)
                }
            }
            ErrorLine {
                width: parent.width
                text: root.service.error("notification.urgency")
            }

            Dropdown {
                width: parent.width
                label: "Sound"
                value: root.notification.sound
                options: Model.SOUNDS
                onChanged: value => {
                    if (value !== root.notification.sound) root.service.setSound(value)
                }
            }
            ErrorLine {
                width: parent.width
                text: root.service.error("notification.sound")
            }
        }
    }
}
