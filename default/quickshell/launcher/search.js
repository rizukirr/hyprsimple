.pragma library

// App search, kept free of QML so tests/tst_search.qml can check it.
// An app is { name, genericName, comment, keywords: [..], id }.

function lower(value) {
    return String(value ?? "").toLowerCase()
}

// First letters of the words in the name, so "vsc" finds Visual Studio Code.
function initials(name) {
    return String(name ?? "")
        .replace(/([a-z])([A-Z])/g, "$1 $2")
        .split(/[\s._:\/\\-]+/)
        .filter(word => word !== "")
        .map(word => word[0].toLowerCase())
        .join("")
}

// How well one word of the query matches, higher is better, 0 for no match.
function termScore(app, term) {
    const name = lower(app.name)
    if (name === term) return 100
    if (name.startsWith(term)) return 90
    if (name.split(/\s+/).some(word => word.startsWith(term))) return 80
    if (name.includes(term)) return 70
    const other = lower([app.genericName, (app.keywords ?? []).join(" "), app.id].join(" "))
    if (other.includes(term)) return 50
    if (term.length <= 5 && initials(app.name).startsWith(term)) return 40
    if (lower(app.comment).includes(term)) return 20
    return 0
}

// Every word of the query has to match. The score is the weakest word's, so one
// strong match cannot carry a word that barely matched.
function score(app, query) {
    const terms = lower(query).trim().split(/\s+/).filter(term => term !== "")
    if (terms.length === 0) return 0
    let weakest = Infinity
    for (const term of terms) {
        const s = termScore(app, term)
        if (s === 0) return 0
        weakest = Math.min(weakest, s)
    }
    return weakest
}

// The apps to show for a query, best first. launches maps an app id to how many
// times it was started. With an empty query every app is returned, most
// launched first. Ties fall back to the name, so the order is stable.
function results(apps, query, launches) {
    const count = app => (launches ?? {})[app.id] ?? 0
    const byName = (a, b) => lower(a.name).localeCompare(lower(b.name))
    if (lower(query).trim() === "")
        return [...apps].sort((a, b) => (count(b) - count(a)) || byName(a, b))
    return apps
        .map(app => ({ app: app, score: score(app, query) }))
        .filter(row => row.score > 0)
        .sort((a, b) => (b.score - a.score) || (count(b.app) - count(a.app)) || byName(a.app, b.app))
        .map(row => row.app)
}
