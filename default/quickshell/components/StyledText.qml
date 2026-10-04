import QtQuick
import qs.theme

Text {
    color: Theme.fg
    font.family: Theme.font
    font.pixelSize: Theme.fontSize
    verticalAlignment: Text.AlignVCenter
    Behavior on color { CAnim {} }
}
