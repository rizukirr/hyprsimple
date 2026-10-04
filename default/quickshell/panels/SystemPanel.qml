import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.components

// CPU, memory and GPU usage. The GPU is polled only while this panel is open.
PopupPanel {
    id: root

    required property var stats

    function percent(value) {
        return `${Math.round(value * 100)}%`
    }

    panelWidth: Theme.panelWidth
    onOpenChanged: stats.watchGpu = open

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
