import QtQuick
import qs.theme

// The one number animation: a short ease-out.
NumberAnimation {
    duration: Theme.anim
    easing.type: Easing.OutCubic
}
