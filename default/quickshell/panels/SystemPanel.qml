import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Services.UPower
import qs.theme
import qs.components

// The power mode, and CPU, memory and GPU usage. The GPU is polled only while
// this panel is open.
PopupPanel {
    id: root

    required property var stats

    // power-profiles-daemon does the switching and remembers the choice. The
    // selector shows what the daemon reports, never what was last clicked, so
    // it cannot show a mode that did not take effect.
    readonly property var powerModes: [
        { value: "saver", label: "Power saver", profile: PowerProfile.PowerSaver },
        { value: "balanced", label: "Balanced", profile: PowerProfile.Balanced },
        { value: "performance", label: "Performance", profile: PowerProfile.Performance }
    ].filter(mode => mode.profile !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile)
    // The service reports Balanced when there is no daemon to ask, so whether
    // one answers is found out separately, the first time the panel opens.
    property bool hasPowerModes: false
    readonly property string throttled: PowerProfiles.degradationReason === PerformanceDegradationReason.LapDetected ? "Performance is limited while the laptop is on a lap."
        : PowerProfiles.degradationReason === PerformanceDegradationReason.HighTemperature ? "Performance is limited while the machine is hot."
        : ""

    function percent(value) {
        return `${Math.round(value * 100)}%`
    }

    panelWidth: Theme.panelWidth
    onOpenChanged: {
        stats.watchGpu = open
        if (open && !hasPowerModes) daemon.running = true
    }

    Process {
        id: daemon
        command: ["busctl", "--system", "--timeout=2", "get-property", "org.freedesktop.UPower.PowerProfiles", "/org/freedesktop/UPower/PowerProfiles", "org.freedesktop.UPower.PowerProfiles", "ActiveProfile"]
        onExited: exitCode => root.hasPowerModes = exitCode === 0
    }

    component Stat: Column {
        id: stat

        property alias icon: glyph.text
        property string title
        property string detail
        property real value: 0

        width: parent.width
        spacing: Theme.xs

        RowLayout {
            width: parent.width
            spacing: Theme.sm

            Icon {
                id: glyph
                color: Theme.secondary
            }
            StyledText {
                Layout.fillWidth: true
                text: stat.title
                elide: Text.ElideRight
            }
            StyledText {
                text: stat.detail
                color: Theme.muted
                font.pixelSize: Theme.fontSizeSmall
            }
            StyledText {
                Layout.preferredWidth: Theme.percentWidth
                horizontalAlignment: Text.AlignRight
                text: root.percent(stat.value)
                font.weight: Font.Medium
            }
        }

        Meter {
            width: parent.width
            value: stat.value
        }
    }

    StyledText {
        leftPadding: Theme.sm
        text: "System"
        font.bold: true
    }

    SectionLabel {
        visible: root.hasPowerModes
        leftPadding: Theme.sm
        text: "Power mode"
    }

    Segmented {
        visible: root.hasPowerModes
        anchors.horizontalCenter: parent.horizontalCenter
        options: root.powerModes
        value: root.powerModes.find(mode => mode.profile === PowerProfiles.profile)?.value ?? ""
        onChanged: value => PowerProfiles.profile = root.powerModes.find(mode => mode.value === value).profile
    }

    StyledText {
        visible: root.hasPowerModes && root.throttled !== ""
        width: parent.width
        leftPadding: Theme.sm
        text: root.throttled
        color: Theme.muted
        font.pixelSize: Theme.fontSizeSmall
        wrapMode: Text.WordWrap
    }

    Stat {
        icon: Theme.icon.cpu
        title: "CPU"
        value: root.stats.cpu
    }

    Stat {
        icon: Theme.icon.ram
        title: "Memory"
        detail: `${root.stats.memoryUsedGiB.toFixed(1)} / ${root.stats.memoryTotalGiB.toFixed(1)} GiB`
        value: root.stats.memory
    }

    SectionLabel {
        visible: root.stats.gpu !== null
        leftPadding: Theme.sm
        topPadding: Theme.xs
        text: root.stats.gpu?.name ?? ""
    }

    Stat {
        visible: root.stats.gpu !== null
        icon: Theme.icon.gpu
        title: "GPU"
        detail: `${root.stats.gpu?.temperature ?? 0}°C`
        value: root.stats.gpu?.usage ?? 0
    }

    Stat {
        visible: root.stats.gpu !== null
        icon: Theme.icon.ram
        title: "GPU memory"
        detail: `${root.stats.gpu?.memoryUsedMiB ?? 0} / ${root.stats.gpu?.memoryTotalMiB ?? 0} MiB`
        value: root.stats.gpu ? root.stats.gpu.memoryUsedMiB / root.stats.gpu.memoryTotalMiB : 0
    }
}
