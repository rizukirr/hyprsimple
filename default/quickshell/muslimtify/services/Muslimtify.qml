import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/Model.js" as Model

// The only unit that reads muslimtify's config or runs muslimtify. Views
// read these properties and call the set* methods. Nothing here updates a
// value before muslimtify saves it: the UI follows config.json.
Item {
  id: root

  property int refreshSeconds: 30

  readonly property string configPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/muslimtify/config.json"

  property bool probed: false
  property bool available: false
  readonly property bool missing: root.probed && !root.available

  property var config: Model.defaultConfig()
  property var today: null
  property var tomorrow: null
  property string scheduleError: ""
  property var methods: []
  property var timezones: []
  property var errors: ({})
  property var now: new Date()
  readonly property var next: Model.nextPrayer(root.today, root.tomorrow, Model.minutesOfDay(root.now))

  property var queue: []
  property var current: null
  property bool currentExited: false
  property bool currentStderrDone: false
  property int currentExitCode: 0
  property string currentStderr: ""
  property string todayStderr: ""
  property bool todayFailed: false

  function error(key) {
    return root.errors[key] || ""
  }

  function setError(key, message) {
    var copy = Object.assign({}, root.errors)
    if (message) copy[key] = message
    else delete copy[key]
    root.errors = copy
  }

  function applyConfig(text) {
    var parsed = Model.parseConfig(text)
    if (parsed === null) return
    root.config = parsed
    root.refresh()
  }

  function refresh() {
    if (!root.available) return
    root.scheduleError = ""
    root.todayFailed = false
    root.todayStderr = ""
    todayProcess.running = true
    tomorrowProcess.running = true
  }

  function loadTimezones() {
    if (root.timezones.length === 0 && !timezoneProcess.running) timezoneProcess.running = true
  }

  function run(key, args) {
    root.setError(key, "")
    root.queue = root.queue.concat([{ key: key, args: args }])
    root.runNext()
  }

  function runNext() {
    if (root.current !== null || root.queue.length === 0) return
    root.current = root.queue[0]
    root.queue = root.queue.slice(1)
    root.currentExited = false
    root.currentStderrDone = false
    root.currentStderr = ""
    runner.command = ["muslimtify"].concat(root.current.args)
    runner.running = true
  }

  // Exit and stderr arrive in either order, so a job finishes only once
  // both have landed.
  function finishIfDone() {
    if (root.current === null || !root.currentExited || !root.currentStderrDone) return
    if (root.currentExitCode !== 0)
      root.setError(root.current.key, Model.errorLine(root.currentStderr) || "muslimtify exited with status " + root.currentExitCode)
    root.current = null
    configFile.reload()
    Qt.callLater(root.runNext)
  }

  function setCoordinates(latitude, longitude) { root.run("location.coordinates", Model.coordinatesArgs(latitude, longitude)) }
  function setLocationField(field, value) { root.run("location." + field, Model.locationArgs(field, value)) }
  function detectLocation() { root.run("location.detect", Model.detectArgs()) }
  function setGps(on) { root.run("location.gps", Model.gpsArgs(on)) }
  function setMethod(name) { root.run("calculation.method", Model.methodArgs(name)) }
  function setMadzhab(name) { root.run("calculation.madzhab", Model.madzhabArgs(name)) }
  function setPrayerEnabled(prayer, on) { root.run(prayer + ".enabled", Model.prayerEnabledArgs(prayer, on)) }
  function setAdhan(prayer, on) { root.run(prayer + ".adhan", Model.adhanArgs(prayer, on)) }
  function setReminders(prayer, minutes) { root.run(prayer + ".reminders", Model.remindersArgs(prayer, minutes)) }
  function setOffset(prayer, minutes) { root.run(prayer + ".offset", Model.offsetArgs(prayer, minutes)) }
  function setUrgency(level) { root.run("notification.urgency", Model.urgencyArgs(level)) }
  function setSound(mode) { root.run("notification.sound", Model.soundArgs(mode)) }
  function setTimeFormat(format) { root.run("display.timeFormat", Model.timeFormatArgs(format)) }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onFileChanged: configFile.reload()
    onLoaded: root.applyConfig(configFile.text())
    onLoadFailed: root.applyConfig("")
  }

  Process {
    id: probe
    // env exits 127 when muslimtify is not on PATH.
    command: ["env", "muslimtify", "version"]
    running: true
    // qmllint disable signal-handler-parameters
    onExited: function(exitCode) {
      root.available = exitCode === 0
      root.probed = true
      if (!root.available) return
      methodsProcess.running = true
      root.refresh()
    }
    // qmllint enable signal-handler-parameters
  }

  Process {
    id: todayProcess
    command: ["muslimtify"].concat(Model.scheduleArgs(0))
    stdout: StdioCollector {
      id: todayOut
      onStreamFinished: {
        var parsed = Model.parseSchedule(todayOut.text)
        if (parsed) {
          root.today = parsed
          return
        }
        root.todayFailed = true
        var line = Model.errorLine(root.todayStderr)
        root.scheduleError = "Times out of date" + (line ? ": " + line : "")
      }
    }
    stderr: StdioCollector {
      id: todayErr
      onStreamFinished: {
        root.todayStderr = todayErr.text
        var line = Model.errorLine(todayErr.text)
        if (root.todayFailed && line) root.scheduleError = "Times out of date: " + line
      }
    }
  }

  Process {
    id: tomorrowProcess
    command: ["muslimtify"].concat(Model.scheduleArgs(1))
    stdout: StdioCollector {
      id: tomorrowOut
      onStreamFinished: {
        var parsed = Model.parseSchedule(tomorrowOut.text)
        if (parsed) root.tomorrow = parsed
      }
    }
  }

  Process {
    id: methodsProcess
    command: ["muslimtify", "method", "--list"]
    stdout: StdioCollector {
      id: methodsOut
      onStreamFinished: root.methods = Model.parseMethods(methodsOut.text)
    }
  }

  Process {
    id: timezoneProcess
    command: ["timedatectl", "list-timezones"]
    stdout: StdioCollector {
      id: timezoneOut
      onStreamFinished: root.timezones = Model.parseLines(timezoneOut.text)
    }
  }

  Process {
    id: runner
    stderr: StdioCollector {
      id: runnerErr
      onStreamFinished: {
        root.currentStderr = runnerErr.text
        root.currentStderrDone = true
        root.finishIfDone()
      }
    }
    // qmllint disable signal-handler-parameters
    onExited: function(exitCode) {
      root.currentExitCode = exitCode
      root.currentExited = true
      stderrGrace.restart()
      root.finishIfDone()
    }
    // qmllint enable signal-handler-parameters
  }

  // vibekit: a late stderr from the previous job can land after this grace period and after the next job starts. Give each job its own Process if that ever shows up.
  Timer {
    id: stderrGrace
    interval: 500
    onTriggered: {
      root.currentStderrDone = true
      root.finishIfDone()
    }
  }

  Timer {
    interval: Math.max(5, Math.min(60, root.refreshSeconds)) * 1000
    running: root.available
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 10000
    running: true
    repeat: true
    onTriggered: {
      var previous = root.now
      root.now = new Date()
      if (previous.getDate() !== root.now.getDate()) root.refresh()
    }
  }
}
