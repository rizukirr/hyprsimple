pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.theme

// The notification daemon. It owns org.freedesktop.Notifications while the shell runs,
// and keeps the notifications that are on screen and the ones that have been, newest
// first.
Singleton {
    id: root

    // One entry per notification on screen: { notification, record, stamp, closing }.
    property list<QtObject> entries

    // What has been shown, as plain records: { appName, summary, body, picture, critical, time }.
    // vibekit: kept in memory, so a restarted shell starts with none. Write it to a file if it should outlive that.
    property var history: []
    // How many arrived since the history was last looked at.
    property int unread: 0
    // Do not disturb: nothing pops up except a critical one. Everything still reaches the history.
    property bool silent: false

    function clearHistory() {
        release(history)
        history = []
        unread = 0
    }

    function forget(record) {
        release([record])
        history = history.filter(r => r !== record)
    }

    function remember(record) {
        const kept = [record, ...history]
        release(kept.slice(Theme.notifyHistoryMax))
        history = kept.slice(0, Theme.notifyHistoryMax)
        unread++
    }

    // A picture sent as bytes is served from the notification itself, so one is kept
    // alive, closed, for as long as its record is in the history.
    function release(records) {
        records.forEach(record => record.lock?.destroy())
    }

    Component {
        id: lockComp
        RetainableLock { locked: true }
    }

    // An image the sender attached wins over its icon. An icon is a path or a theme name.
    function pictureOf(notification) {
        if (notification.image) return notification.image
        const icon = notification.appIcon
        if (!icon) return ""
        return icon.startsWith("/") || icon.includes("://") ? icon : Quickshell.iconPath(icon, true)
    }

    // What a card shows, copied out of the notification, which is gone as soon as it closes.
    function recordOf(notification) {
        const picture = pictureOf(notification)
        return {
            appName: notification.appName,
            summary: notification.summary,
            body: notification.body,
            picture: picture,
            critical: notification.urgency === NotificationUrgency.Critical,
            time: new Date(),
            lock: picture.startsWith("image://") ? lockComp.createObject(root, { object: notification }) : null
        }
    }

    // How long one stays up, in milliseconds. 0 stays until dismissed, which is
    // also what a sender asking for 0 means. -1 leaves it to us.
    function timeoutFor(notification) {
        if (notification.expireTimeout >= 0) return notification.expireTimeout
        return notification.urgency === NotificationUrgency.Critical ? 0 : Theme.notifyTimeout
    }

    function tagOf(notification) {
        return notification?.hints["x-canonical-private-synchronous"] ?? ""
    }

    function dismissAll() {
        live.forEach(entry => entry.notification.dismiss())
    }

    function drop(entry) {
        entries = entries.filter(e => e !== entry)
        entry.destroy()
    }

    // Entries still on their way in or staying. The ones closing no longer count
    // towards the limit, and are not matched by a replacement.
    readonly property list<QtObject> live: entries.filter(e => !e.closing)

    NotificationServer {
        keepOnReload: false
        actionsSupported: true
        bodyMarkupSupported: true
        imageSupported: true

        onNotification: notification => {
            notification.tracked = true
            // Notifications that name the same thing take one place on screen instead
            // of stacking: volume and brightness, one per key press. The sender says so
            // with a hint, since the id it asks to replace is not one this server gave.
            const tag = root.tagOf(notification)
            const record = root.recordOf(notification)
            // A level that is replaced on every key press, and one the sender marked as
            // passing, are not worth keeping.
            if (!tag && !notification.transient) root.remember(record)
            else root.release([record])
            if (root.silent && !record.critical) {
                notification.dismiss()
                return
            }
            const existing = tag ? root.live.find(e => root.tagOf(e.notification) === tag) : null
            if (existing) {
                const old = existing.notification
                existing.notification = notification
                existing.record = record
                existing.stamp++
                old.dismiss()
                return
            }
            root.entries = [entryComp.createObject(root, { notification, record }), ...root.entries]
            // The oldest leave when there are too many.
            root.live.slice(Theme.notifyMax).forEach(e => e.notification.dismiss())
        }
    }

    Component {
        id: entryComp

        QtObject {
            id: entry

            required property Notification notification
            // What the card shows. It outlives the notification, so a card that is leaving
            // still has its text.
            required property var record
            // Counts replacements, so a card restarts its countdown on each one.
            property int stamp: 0
            // Closed, and still on screen while its card leaves.
            property bool closing: false

            readonly property Connections conn: Connections {
                target: entry.notification
                function onClosed() {
                    entry.closing = true
                    leave.start()
                }
            }

            readonly property Timer leave: Timer {
                interval: Theme.closeAnim
                onTriggered: root.drop(entry)
            }
        }
    }
}
