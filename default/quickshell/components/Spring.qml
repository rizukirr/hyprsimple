import QtQuick
import qs.theme

// Geometry animation with a slight overshoot, for things that travel: the workspace
// indicator and panels growing out of the bar.
NumberAnimation {
    duration: Theme.springAnim
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Theme.springCurve
}
