import QtQuick
import qs.theme
import "../muslimtify/lib/Model.js" as Model

// Next prayer from muslimtify. Left click opens the panel, right click switches
// between the prayer's time and the time left until it.
StatusButton {
    id: root

    required property var service
    property bool showRemaining: false

    readonly property bool soon: !!service.next && service.next.remaining <= Theme.prayerSoonMinutes

    label: service.next ? Model.barLabel(service.next, showRemaining) : ""
    // Accent when its panel is open, and when the prayer is close.
    highlighted: soon

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: root.showRemaining = !root.showRemaining
    }
}
