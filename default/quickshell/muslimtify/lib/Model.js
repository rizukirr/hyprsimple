// Pure logic for the muslimtify panel: parsing muslimtify's output,
// working out the next prayer, validating input and building CLI
// arguments. No QML here, so test/model-test.sh can run it under node.

var PRAYERS = ["fajr", "dhuhr", "asr", "maghrib", "isha"]

var ICONS = {
  mosque: "󱠧",
  bell: "󰂚",
  bellOff: "󰂛",
  adhan: "󰕾",
  adhanOff: "󰖁",
  github: "󰊤",
  website: "󰖟",
  refresh: "\uf021",
  settings: "\uf013"
}

var LINKS = {
  github: "https://github.com/muslimtify-org/muslimtify",
  website: "https://muslimtify.vercel.app"
}

var URGENCIES = ["low", "normal", "critical"]
var SOUNDS = ["adhan", "default", "off"]
var MADZHABS = [
  { value: "shafi", label: "Shafi'i" },
  { value: "hanafi", label: "Hanafi" }
]

var TIME_FORMATS = [
  { value: "24", label: "24 hour" },
  { value: "12", label: "12 hour" }
]

var DAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

var LOCATION_FLAGS = {
  timezone: "--timezone=",
  city: "--city=",
  country: "--country=",
  refreshInterval: "--refresh-interval="
}

function title(name) {
  var text = String(name || "")
  return text ? text.charAt(0).toUpperCase() + text.slice(1) : ""
}

function pad(value) {
  return (value < 10 ? "0" : "") + value
}

// Accepts 24-hour "HH:MM" and the 12-hour "hh:MM AM" or "hh:MM PM" that
// `muslimtify timeformat 12` prints. 12 AM is midnight and 12 PM is noon.
function toMinutes(time) {
  var match = /^(\d{1,2}):(\d{2})(?: (AM|PM))?$/.exec(String(time || ""))
  if (!match) return -1
  var hours = Number(match[1])
  var minutes = Number(match[2])
  if (minutes > 59) return -1
  if (match[3]) {
    if (hours < 1 || hours > 12) return -1
    hours = hours % 12 + (match[3] === "PM" ? 12 : 0)
  } else if (hours > 23) {
    return -1
  }
  return hours * 60 + minutes
}

function formatDuration(minutes) {
  var total = Math.max(0, Math.round(Number(minutes) || 0))
  return pad(Math.floor(total / 60)) + ":" + pad(total % 60)
}

function minutesOfDay(date) {
  return date.getHours() * 60 + date.getMinutes()
}

function formatDate(date) {
  return DAYS[date.getDay()] + " " + date.getDate() + " " + MONTHS[date.getMonth()]
}

function parseJson(text) {
  try {
    return JSON.parse(String(text))
  } catch (error) {
    return null
  }
}

function parseLines(text) {
  return String(text || "").split("\n")
    .map(function(line) { return line.trim() })
    .filter(function(line) { return line !== "" })
}

// muslimtify prints progress lines to stderr even on success, so prefer
// the line that names the error.
function errorLine(text) {
  var lines = parseLines(text)
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].indexOf("Error:") === 0) return lines[i]
  }
  return lines.length > 0 ? lines[lines.length - 1] : ""
}

function defaultConfig() {
  var prayers = {}
  for (var i = 0; i < PRAYERS.length; i++) {
    prayers[PRAYERS[i]] = { enabled: true, adhan_enabled: true, reminders: [], offset: 0 }
  }
  return {
    location: {
      latitude: 0,
      longitude: 0,
      timezone: "",
      city: "",
      country: "",
      auto_detect: true,
      use_gps: false,
      refresh_interval: 43200
    },
    calculation: { method: "", madhab: "shafi" },
    notification: { urgency: "normal", sound: "adhan" },
    display: { time_format: 24 },
    prayers: prayers
  }
}

// Copies each key the defaults know about, keeping the default when the
// source is missing the key or holds a value of another type.
function mergeSection(defaults, source) {
  var out = {}
  for (var key in defaults) {
    var value = source ? source[key] : undefined
    var usable = value !== undefined && value !== null && typeof value === typeof defaults[key]
    out[key] = usable ? value : defaults[key]
  }
  return out
}

// Returns defaults for an empty or missing file, and null for text that is
// not a JSON object.
function parseConfig(text) {
  if (String(text || "").trim() === "") return defaultConfig()
  var data = parseJson(text)
  if (!data || typeof data !== "object") return null
  var base = defaultConfig()
  var prayers = {}
  for (var i = 0; i < PRAYERS.length; i++) {
    var name = PRAYERS[i]
    prayers[name] = mergeSection(base.prayers[name], data.prayers ? data.prayers[name] : null)
  }
  return {
    location: mergeSection(base.location, data.location),
    calculation: mergeSection(base.calculation, data.calculation),
    notification: mergeSection(base.notification, data.notification),
    display: mergeSection(base.display, data.display),
    prayers: prayers
  }
}

function parseSchedule(text) {
  var data = parseJson(text)
  if (!data || !data.prayers) return null
  var prayers = []
  for (var i = 0; i < PRAYERS.length; i++) {
    var entry = data.prayers[PRAYERS[i]]
    var minutes = entry ? toMinutes(entry.time) : -1
    if (minutes < 0) return null
    prayers.push({ name: PRAYERS[i], time: entry.time, minutes: minutes })
  }
  return { date: String(data.date || ""), prayers: prayers }
}

function parseMethods(text) {
  var methods = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var match = /^\s+([a-z0-9_-]+)\s+(\*\s+)?(\S.*?)\s*$/.exec(lines[i])
    if (match) methods.push({ value: match[1], label: match[3], current: !!match[2] })
  }
  return methods
}

function nextResult(prayer, at, previous, now, isTomorrow) {
  var span = at - previous
  var progress = span > 0 ? Math.max(0, Math.min(1, (now - previous) / span)) : 0
  return { name: prayer.name, time: prayer.time, remaining: at - now, progress: progress, isTomorrow: isTomorrow }
}

// The next prayer strictly after `now` (minutes since midnight). A prayer
// whose minute has arrived counts as passed.
function nextPrayer(today, tomorrow, now) {
  if (!today || today.prayers.length === 0) return null
  var list = today.prayers
  for (var i = 0; i < list.length; i++) {
    if (list[i].minutes > now) {
      // vibekit: before Fajr, today's Isha minus a day stands in for yesterday's Isha. Fetch --day-offset -1 if the progress bar needs to be exact.
      var previous = i > 0 ? list[i - 1].minutes : list[list.length - 1].minutes - 1440
      return nextResult(list[i], list[i].minutes, previous, now, false)
    }
  }
  if (!tomorrow || tomorrow.prayers.length === 0) return null
  var first = tomorrow.prayers[0]
  return nextResult(first, first.minutes + 1440, list[list.length - 1].minutes, now, true)
}

function prayerState(prayer, next, now) {
  if (next && !next.isTomorrow && next.name === prayer.name) return "next"
  return prayer.minutes <= now ? "past" : "upcoming"
}

// Plain text on a horizontal bar. The glyph stays only as a click target
// while no next prayer is known.
function barLabel(next, showRemaining) {
  if (!next) return ICONS.mosque
  var when = showRemaining ? "-" + formatDuration(next.remaining) : next.time
  return title(next.name) + " " + when
}

function placeName(config) {
  var location = config ? config.location : null
  if (location && location.city) return location.city
  var timezone = location ? String(location.timezone || "") : ""
  return timezone ? timezone.split("/").pop().replace(/_/g, " ") : ""
}

function subtitle(date, config) {
  var place = placeName(config)
  return formatDate(date) + (place ? " · " + place : "")
}

function parseNumber(text, integer) {
  var value = String(text === undefined || text === null ? "" : text).trim()
  var pattern = integer ? /^[-+]?\d+$/ : /^[-+]?\d+(\.\d+)?$/
  return pattern.test(value) ? Number(value) : NaN
}

function inRange(text, min, max, integer) {
  var value = parseNumber(text, integer)
  return !isNaN(value) && value >= min && value <= max
}

function validateLatitude(text) {
  return inRange(text, -90, 90, false) ? "" : "Latitude must be a number from -90 to 90"
}

function validateLongitude(text) {
  return inRange(text, -180, 180, false) ? "" : "Longitude must be a number from -180 to 180"
}

function validateOffset(text) {
  return inRange(text, -60, 60, true) ? "" : "Offset must be a whole number from -60 to 60"
}

function validateCountry(text) {
  return /^[A-Za-z]{2}$/.test(String(text || "").trim()) ? "" : "Country must be a two-letter code, like ID"
}

function validateRefreshInterval(text) {
  var value = parseNumber(text, true)
  return value === 0 || value >= 3600 ? "" : "Use 0 to turn refresh off, or at least 3600 seconds"
}

function parseReminders(text) {
  var parts = String(text || "").split(",")
  var minutes = []
  for (var i = 0; i < parts.length; i++) {
    var part = parts[i].trim()
    if (!/^\d+$/.test(part) || Number(part) < 1) return null
    minutes.push(Number(part))
  }
  return minutes
}

function validateReminders(text) {
  return parseReminders(text) ? "" : "Use whole minutes separated by commas, like 30, 15, 5"
}

function formatReminders(minutes) {
  return (minutes || []).join(", ")
}

function scheduleArgs(dayOffset) {
  return dayOffset ? ["show", "--json", "--day-offset", String(dayOffset)] : ["show", "--json"]
}

function coordinatesArgs(latitude, longitude) {
  return ["location", "set", "--lat=" + String(latitude).trim(), "--long=" + String(longitude).trim()]
}

function locationArgs(field, value) {
  if (!LOCATION_FLAGS[field]) throw new Error("unknown location field: " + field)
  var text = String(value).trim()
  if (field === "country") text = text.toUpperCase()
  return ["location", "set", LOCATION_FLAGS[field] + text]
}

function detectArgs() {
  return ["location", "set", "--auto"]
}

function gpsArgs(on) {
  return ["location", "gps", on ? "on" : "off"]
}

function methodArgs(name) {
  return ["method", String(name)]
}

function madzhabArgs(name) {
  return ["madzhab", String(name)]
}

function prayerEnabledArgs(prayer, on) {
  return ["notification", on ? "enable" : "disable", prayer]
}

function adhanArgs(prayer, on) {
  return ["notification", "--adhan", on ? "enable" : "disable", prayer]
}

function remindersArgs(prayer, minutes) {
  return ["notification", "--reminder", prayer].concat(minutes.map(String))
}

function offsetArgs(prayer, minutes) {
  return ["offset", prayer, String(Number(minutes))]
}

function urgencyArgs(level) {
  return ["notification", "--urgency", String(level)]
}

function soundArgs(mode) {
  return ["notification", "--sound", String(mode)]
}

function timeFormatArgs(format) {
  return ["timeformat", String(format)]
}

if (typeof module !== "undefined") {
  module.exports = {
    PRAYERS: PRAYERS,
    ICONS: ICONS,
    LINKS: LINKS,
    URGENCIES: URGENCIES,
    SOUNDS: SOUNDS,
    MADZHABS: MADZHABS,
    TIME_FORMATS: TIME_FORMATS,
    title: title,
    toMinutes: toMinutes,
    formatDuration: formatDuration,
    minutesOfDay: minutesOfDay,
    formatDate: formatDate,
    parseLines: parseLines,
    errorLine: errorLine,
    defaultConfig: defaultConfig,
    parseConfig: parseConfig,
    parseSchedule: parseSchedule,
    parseMethods: parseMethods,
    nextPrayer: nextPrayer,
    prayerState: prayerState,
    barLabel: barLabel,
    placeName: placeName,
    subtitle: subtitle,
    validateLatitude: validateLatitude,
    validateLongitude: validateLongitude,
    validateOffset: validateOffset,
    validateCountry: validateCountry,
    validateRefreshInterval: validateRefreshInterval,
    parseReminders: parseReminders,
    validateReminders: validateReminders,
    formatReminders: formatReminders,
    scheduleArgs: scheduleArgs,
    coordinatesArgs: coordinatesArgs,
    locationArgs: locationArgs,
    detectArgs: detectArgs,
    gpsArgs: gpsArgs,
    methodArgs: methodArgs,
    madzhabArgs: madzhabArgs,
    prayerEnabledArgs: prayerEnabledArgs,
    adhanArgs: adhanArgs,
    remindersArgs: remindersArgs,
    offsetArgs: offsetArgs,
    urgencyArgs: urgencyArgs,
    soundArgs: soundArgs,
    timeFormatArgs: timeFormatArgs
  }
}
