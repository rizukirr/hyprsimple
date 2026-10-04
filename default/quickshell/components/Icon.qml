import QtQuick
import qs.theme

// Material Symbols glyph. text is the ligature name.
StyledText {
    // 0 outlined, 1 filled.
    property real fill: 0

    font.family: Theme.iconFont
    font.pixelSize: Theme.iconSize
    font.variableAxes: ({ FILL: fill, opsz: 24 })
}
