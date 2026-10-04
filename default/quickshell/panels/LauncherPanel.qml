import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.theme
import qs.components
import "../launcher/search.js" as Search

// App launcher: a sidebar that grows out of the left screen edge, below the bar,
// with a search field over the list of apps.
PanelWindow {
    id: panel

    required property var bar
    readonly property string name: "launcher"
    readonly property bool open: bar.openPanel === name

    // 0 closed, 1 open. Overshoots slightly on the way in, and leaves quickly.
    //
    // Opening and closing are two separate animations, started by hand. One animation
    // whose duration and curve were bound to open changed curve while it was already
    // running: a close began on the opening curve, which is nearly finished within a
    // few frames, then switched to the closing curve, which has barely started by
    // then. The panel shut, sprang back open and shut again.
    property real progress: 0

    NumberAnimation {
        id: opening
        target: panel
        property: "progress"
        to: 1
        duration: Theme.springAnim
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.springCurve
    }

    NumberAnimation {
        id: closing
        target: panel
        property: "progress"
        to: 0
        duration: Theme.closeAnim
        easing.type: Easing.InCubic
    }

    // Exclusive focus takes the keyboard at once, but while it is held Hyprland sends every
    // pointer event to this window, the bar included. So it is held briefly, then relaxed.
    property bool focusPrimed: false

    // How many times each app was started from here, by desktop id. Kept so the apps
    // used most are listed first.
    property var launches: ({})
    readonly property string launchesPath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/hyprsimple/launcher.json"

    // The entry list reorders itself when an app starts, so it is always re-sorted here.
    readonly property var apps: DesktopEntries.applications.values.filter(app => !app.noDisplay && app.name !== "")
    readonly property var results: Search.results(apps, picker.text, launches)

    function dismiss() {
        if (open) bar.openPanel = ""
    }

    // Closed first, so the drawer is already leaving when the app's window arrives.
    function launch(app) {
        if (!app) return
        dismiss()
        // A new object, because a write into the existing one is not seen as a change.
        const next = Object.assign({}, launches)
        next[app.id] = (next[app.id] ?? 0) + 1
        launches = next
        launchesFile.setText(JSON.stringify(next))
        // Through uwsm, so the app runs in the session's own scope like one started by a keybinding.
        Quickshell.execDetached(["uwsm", "app", "--", app.id + ".desktop"])
    }

    onOpenChanged: {
        if (!open) {
            opening.stop()
            closing.start()
            return
        }
        closing.stop()
        opening.start()
        focusPrimed = false
        prime.restart()
        picker.reset()
        Qt.callLater(() => picker.inputItem.forceActiveFocus())
    }

    Timer {
        id: prime
        interval: Theme.focusPrime
        onTriggered: panel.focusPrimed = true
    }

    FileView {
        id: launchesFile
        path: panel.launchesPath
        printErrors: false
        onLoaded: {
            try {
                panel.launches = JSON.parse(text())
            } catch (e) {
                console.log("launcher: ignoring unreadable", path, e.message)
            }
        }
    }

    screen: bar.screen
    visible: open || closing.running
    anchors { top: true; bottom: true; left: true; right: true }
    margins.top: Theme.barHeight
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    // No input while closing, so what is underneath can be clicked at once.
    mask: open ? null : noInput
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-panel"
    WlrLayershell.keyboardFocus: !open ? WlrKeyboardFocus.None
        : focusPrimed ? WlrKeyboardFocus.OnDemand
        : WlrKeyboardFocus.Exclusive

    Region { id: noInput }

    MouseArea {
        anchors.fill: parent
        enabled: panel.open
        acceptedButtons: Qt.AllButtons
        onClicked: panel.dismiss()
    }

    // The sidebar is laid out once at its full size and slid in from beyond the left
    // edge. Moving it costs nothing per frame, where changing its width made the
    // outline and the whole list be laid out again on every frame.
    Item {
        id: card

        readonly property real flare: Theme.panelRadius
        // The outline starts this far left of the sidebar, so the overshoot on the
        // way in does not open a gap at the screen edge.
        readonly property real bleed: 2 * Theme.lg

        x: (panel.progress - 1) * (width + flare)
        width: Theme.sidebarWidth
        height: parent.height

        // Outline: the sidebar itself, with a flare at the top joining it to the bar
        // and one at the bottom joining it to the screen edge.
        Shape {
            x: -card.bleed
            width: card.bleed + card.width + card.flare
            height: card.height
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: 0
                strokeColor: "transparent"
                fillColor: Theme.bg
                Behavior on fillColor { CAnim {} }

                startX: 0
                startY: 0
                PathLine { x: card.bleed + card.width + card.flare; y: 0 }
                PathArc {
                    x: card.bleed + card.width
                    y: card.flare
                    radiusX: card.flare
                    radiusY: card.flare
                    direction: PathArc.Counterclockwise
                }
                PathLine { x: card.bleed + card.width; y: card.height - card.flare }
                PathArc {
                    x: card.bleed + card.width + card.flare
                    y: card.height
                    radiusX: card.flare
                    radiusY: card.flare
                    direction: PathArc.Counterclockwise
                }
                PathLine { x: 0; y: card.height }
            }
        }

        // Clicks inside the sidebar must not reach the dismiss area.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        Item {
            anchors.fill: parent

            ColumnLayout {
                x: Theme.lg
                y: Theme.lg
                width: Theme.sidebarWidth - 2 * Theme.lg
                height: parent.height - 2 * Theme.lg
                spacing: Theme.md
                opacity: Math.max(0, Math.min(1, panel.progress))

                PickerList {
                    id: picker

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    placeholder: "Search apps"
                    emptyText: "No apps found"
                    items: panel.results
                    // Rows, and so icons, exist only while the sidebar is on screen.
                    active: panel.visible
                    onActivated: app => panel.launch(app)
                    onDismissed: panel.dismiss()

                    delegate: Item {
                        id: row

                        required property var modelData

                        width: ListView.view.width
                        height: Theme.appRowHeight

                        RowLayout {
                            anchors { fill: parent; leftMargin: Theme.sm; rightMargin: Theme.sm }
                            spacing: Theme.md

                            // Decoded at twice the shown size, which stays sharp on a scaled screen
                            // and keeps a large vector icon from being rendered at its full size.
                            Image {
                                Layout.preferredWidth: Theme.appIconSize
                                Layout.preferredHeight: Theme.appIconSize
                                sourceSize: Qt.size(2 * Theme.appIconSize, 2 * Theme.appIconSize)
                                fillMode: Image.PreserveAspectFit
                                // Off the main thread, so opening does not wait for the icons.
                                asynchronous: true
                                source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    text: row.modelData.name
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                    text: row.modelData.comment || row.modelData.genericName
                                    color: Theme.muted
                                    font.pixelSize: Theme.fontSizeSmall
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        // Hover has its own tint and does not move the keyboard selection.
                        StateLayer {
                            radius: Theme.radius
                            onClicked: picker.activated(row.modelData)
                        }
                    }
                }
            }
        }
    }
}
