pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Every color, size, font, animation and icon name the shell uses.
// Colors come from the hyprsimple theme file and fall back to Tokyo Night Storm.
Singleton {
    id: root

    // Parsed theme file. Empty until it loads.
    property var colors: ({})

    readonly property color bg: colors.background ?? "#24283b"
    // Capsules on the bar sit on this.
    readonly property color surface: colors.surface ?? "#1d202f"
    readonly property color fg: colors.foreground ?? "#c0caf5"
    readonly property color muted: colors.muted ?? "#606683"
    readonly property color accent: colors.accent ?? "#7aa2f7"
    // Status icons.
    readonly property color secondary: colors.secondary ?? "#bb9af7"
    // Content drawn on top of the accent.
    readonly property color onAccent: bg
    readonly property color danger: colors.danger ?? "#f7768e"

    FileView {
        id: themeFile
        // QS_THEME_FILE points the shell at another file, which is how the reload test avoids the live one.
        path: Quickshell.env("QS_THEME_FILE") || Quickshell.env("HOME") + "/.config/quickshell/theme-active.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        // A missing file means the built-in colors, also when it disappears while running.
        onLoadFailed: {
            root.colors = ({})
            retry.start()
        }
        onLoaded: {
            try {
                root.colors = JSON.parse(text())
                console.log("theme: loaded", path)
            } catch (e) {
                console.log("theme: ignoring unreadable", path, e.message)
            }
        }
    }

    // A file that does not exist cannot be watched, so one created after the shell
    // started would never be seen. Until a load succeeds, look again every few seconds.
    Timer {
        id: retry
        interval: 3000
        onTriggered: themeFile.reload()
    }

    // Foreground tints draw every hover, selected and field surface, so they follow any theme.
    function tint(alpha) {
        return Qt.alpha(fg, alpha)
    }
    readonly property real tintIdle: 0.04
    readonly property real tintHover: 0.08
    readonly property real tintSelected: 0.18
    readonly property real tintPressed: 0.22
    readonly property real tintBorder: 0.25
    readonly property real tintOutline: 0.4
    readonly property real dimmed: 0.5

    // One scale for spacing and padding.
    readonly property int xs: 4
    readonly property int sm: 8
    readonly property int md: 12
    readonly property int lg: 16
    // vibekit: matches Hyprland decoration:rounding (12) by hand, read it from hyprctl if it should follow config changes
    readonly property int radius: 12

    readonly property string font: "JetBrainsMono Nerd Font"
    readonly property string iconFont: "Material Symbols Rounded"
    readonly property int fontSize: 12
    readonly property int fontSizeSmall: 10
    readonly property int fontSizeLarge: 22
    readonly property int iconSize: 16

    readonly property int barHeight: 36
    // Height of the capsule groups on the bar, their corner radius, and the radius of
    // the hover and indicator shapes that sit inside them.
    readonly property int capsule: 28
    readonly property int capsuleRadius: 8
    readonly property int capsuleInnerRadius: 5
    // How long the pointer rests on a bar item before its tooltip shows, and the
    // tooltip's distance below the item.
    readonly property int tooltipDelay: 500
    readonly property int tooltipGap: 10
    readonly property int barInset: 6
    // Panel distance from the bar and the screen edges: half of Hyprland gaps_out.
    readonly property int gap: 5
    readonly property int controlSize: 24
    readonly property int rowHeight: 32
    readonly property int cellSize: 34
    readonly property int workspaceCell: 24
    readonly property int dotSize: 8
    readonly property int statusSlot: 27
    readonly property int sliderHeight: 6
    readonly property int sliderHandle: 14
    // Room for "100%" so a slider does not resize as the number changes.
    readonly property int percentWidth: 36
    readonly property int toggleWidth: 42
    readonly property int toggleHeight: 22
    readonly property int panelWidth: 340
    readonly property int panelWidthNarrow: 220
    readonly property int panelWidthWide: 440
    readonly property int dropdownMaxHeight: 200
    readonly property int settingsMaxHeight: 520
    readonly property int logoSize: 32
    readonly property int prayerNameWidth: 90
    // The prayer item turns accent when this many minutes or fewer are left.
    readonly property int prayerSoonMinutes: 15
    readonly property int listMaxHeight: 320

    // Volume change per scroll notch, as a fraction.
    readonly property real volumeStep: 0.05

    // Short fades for everything on the bar and inside panels.
    readonly property int anim: 140
    readonly property int spin: 900
    // Things that travel overshoot slightly: the workspace indicator, and panels growing out of the bar.
    readonly property int springAnim: 400
    readonly property var springCurve: [0.38, 1.21, 0.22, 1, 1, 1]
    // Corner radius of a panel, and of the flares that join it to the bar.
    readonly property int panelRadius: 20
    // How often the keep-awake item re-reads whether hypridle is running.
    readonly property int awakePollMs: 5000
    // How long a panel holds exclusive keyboard focus before relaxing it.
    readonly property int focusPrime: 75

    // Material Symbols ligature names.
    readonly property var icon: ({
        wifi: ["signal_wifi_0_bar", "network_wifi_1_bar", "network_wifi_2_bar", "network_wifi_3_bar", "network_wifi"],
        wifiOff: "wifi_off",
        ethernet: "cable",
        bt: "bluetooth",
        btConnected: "bluetooth_connected",
        btOff: "bluetooth_disabled",
        scan: "bluetooth_searching",
        lock: "lock",
        eye: "visibility",
        eyeOff: "visibility_off",
        left: "chevron_left",
        right: "chevron_right",
        link: "link",
        unlink: "link_off",
        trash: "delete",
        loading: "progress_activity",
        battery: ["battery_0_bar", "battery_1_bar", "battery_2_bar", "battery_3_bar", "battery_4_bar", "battery_5_bar", "battery_6_bar", "battery_full"],
        batteryCharging: "battery_charging_full",
        volume: ["volume_mute", "volume_down", "volume_up"],
        volumeMuted: "volume_off",
        mic: ["mic"],
        micMuted: "mic_off",
        calendar: "calendar_month",
        bell: "notifications",
        bellOff: "notifications_off",
        refresh: "refresh",
        awake: "coffee",
        recording: "radio_button_checked",
        cpu: "memory",
        ram: "memory_alt",
        gpu: "developer_board",
        settings: "settings",
        expand: "expand_more",
        collapse: "expand_less",
        power: "power_settings_new",
        restart: "restart_alt",
        logout: "logout",
        suspend: "bedtime",
        headphones: "headphones",
        speaker: "speaker",
        keyboard: "keyboard",
        mouse: "mouse",
        gamepad: "sports_esports",
        phone: "smartphone",
        laptop: "computer",
        monitor: "tv"
    })

    // strength is 0 to 1.
    function wifiIcon(strength) {
        return icon.wifi[Math.max(0, Math.min(4, Math.floor(strength * 5)))]
    }

    // name is a freedesktop icon name reported by BlueZ.
    // fallback is used when the device type is not recognised.
    function btIcon(name, fallback) {
        name = name ?? ""
        if (name.startsWith("audio-head")) return icon.headphones
        if (name.startsWith("audio")) return icon.speaker
        if (name === "input-keyboard") return icon.keyboard
        if (name === "input-mouse") return icon.mouse
        if (name === "input-gaming") return icon.gamepad
        if (name === "phone") return icon.phone
        if (name === "computer") return icon.laptop
        if (name === "video-display") return icon.monitor
        return fallback ?? icon.bt
    }
}
