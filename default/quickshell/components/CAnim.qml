import QtQuick
import qs.theme

// Color animation. Every themed color uses it, which makes a theme switch cross-fade.
ColorAnimation {
    duration: Theme.anim
    easing.type: Easing.OutCubic
}
