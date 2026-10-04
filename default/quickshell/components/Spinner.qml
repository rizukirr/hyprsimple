import QtQuick
import qs.theme

Icon {
    id: root

    text: Theme.icon.loading

    RotationAnimator on rotation {
        from: 0
        to: 360
        duration: Theme.spin
        loops: Animation.Infinite
        running: root.visible
    }
}
