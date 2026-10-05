pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// How many times each app was started from the launcher, by desktop id, so the
// apps used most are listed first. One for every bar: each kept its own copy and
// wrote the whole file, so a launch from one monitor undid one from another.
Singleton {
    id: root

    property var launches: ({})
    readonly property string path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/hyprsimple/launcher.json"

    function record(appId) {
        // A new object, because a write into the existing one is not seen as a change.
        const next = Object.assign({}, launches)
        next[appId] = (next[appId] ?? 0) + 1
        launches = next
        file.setText(JSON.stringify(next))
    }

    FileView {
        id: file
        path: root.path
        printErrors: false
        onLoaded: {
            try {
                root.launches = JSON.parse(text())
            } catch (e) {
                console.log("launcher: ignoring unreadable", path, e.message)
            }
        }
    }
}
