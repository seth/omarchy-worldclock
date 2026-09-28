.pragma library

// Pure helpers for the world clock. The shell's JS engine has no Intl, so
// zone offsets come from `date` (see BarWidget.qml) as an hourly table from
// yesterday to tomorrow; everything here is arithmetic on that table.

var DEFAULT_ZONES = [
  { label: "San Francisco", tz: "America/Los_Angeles" },
  { label: "Denver",        tz: "America/Denver" },
  { label: "Minneapolis",   tz: "America/Chicago" },
  { label: "UTC",           tz: "UTC" },
  { label: "UK",            tz: "Europe/London" },
  { label: "Paris",         tz: "Europe/Paris" }
]

var HOUR_MS = 3600000
var DAY_MS = 86400000

function normalizedZones(value) {
  if (!value || !value.length) return DEFAULT_ZONES
  var out = []
  for (var i = 0; i < value.length; i++) {
    var z = value[i]
    if (z && z.tz) out.push({ label: String(z.label || z.tz), tz: String(z.tz) })
  }
  return out.length ? out : DEFAULT_ZONES
}

// Local midnight bounding the day that contains `ms`. The span is not always
// 24h: DST days are 23h or 25h long.
function localDayStart(ms) {
  var d = new Date(ms)
  return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
}

function localDayEnd(ms) {
  var d = new Date(ms)
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1).getTime()
}

// "+0530" -> 330, "-0700" -> -420
function parseOffset(s) {
  var m = /^([+-])(\d\d)(\d\d)$/.exec(String(s))
  if (!m) return 0
  var mins = parseInt(m[2], 10) * 60 + parseInt(m[3], 10)
  return m[1] === "-" ? -mins : mins
}

// Helper output: the system zone name on the first line, then
// `date -f - '+%z %Z'` output, `samples` lines per zone, zones in order.
function parseTable(text, zoneCount, samples) {
  var lines = String(text).split("\n").filter(function(l) { return l.trim() !== "" })
  if (lines.length < 1 + zoneCount * samples) return null
  var table = []
  for (var z = 0; z < zoneCount; z++) {
    var row = []
    for (var h = 0; h < samples; h++) {
      var parts = lines[1 + z * samples + h].trim().split(/\s+/)
      row.push({ offset: parseOffset(parts[0]), abbr: parts[1] || "" })
    }
    table.push(row)
  }
  return { systemTz: lines[0].trim(), table: table }
}

// The table is sampled on each hour from `tableStart`; DST switches land on
// the hour, so an offset holds for the whole hour it was sampled at.
function sampleAt(table, zoneIndex, tableStart, ms) {
  var row = table[zoneIndex]
  if (!row || !row.length) return null
  var h = Math.floor((ms - tableStart) / HOUR_MS)
  return row[Math.max(0, Math.min(row.length - 1, h))]
}

// Midnight on the wall clock of a zone at `offsetMin`, as an epoch instant.
function zoneDayStart(ms, offsetMin) {
  return dayNumber(ms, offsetMin) * DAY_MS - offsetMin * 60000
}

// Snaps an instant to the step grid. Offsets are whole quarter hours, so a
// quarter-hour grid in UTC is the same grid on every wall clock.
function snapMs(ms, stepMinutes) {
  var step = stepMinutes * 60000
  return Math.round(ms / step) * step
}

function localOffset(ms) {
  return -new Date(ms).getTimezoneOffset()
}

// Days since the epoch as seen on a wall clock at `offsetMin`, so two zones'
// dates can be compared without building Date objects in either zone.
function dayNumber(ms, offsetMin) {
  return Math.floor((ms + offsetMin * 60000) / DAY_MS)
}

function pad(n) { return n < 10 ? "0" + n : String(n) }

function formatTime(ms, offsetMin, hour12) {
  var d = new Date(ms + offsetMin * 60000)
  var h = d.getUTCHours(), m = d.getUTCMinutes()
  if (!hour12) return pad(h) + ":" + pad(m)
  var suffix = h < 12 ? "am" : "pm"
  var h12 = h % 12 === 0 ? 12 : h % 12
  return h12 + ":" + pad(m) + suffix
}

var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function formatDay(ms, offsetMin) {
  var d = new Date(ms + offsetMin * 60000)
  return WEEKDAYS[d.getUTCDay()] + " " + d.getUTCDate() + " " + MONTHS[d.getUTCMonth()]
}

function hourOf(ms, offsetMin) {
  return new Date(ms + offsetMin * 60000).getUTCHours()
}

// Hours a zone sits ahead of (+) or behind (-) local time, e.g. "+7h", "-1h30".
function relativeLabel(offsetMin, localOffsetMin) {
  var diff = offsetMin - localOffsetMin
  if (diff === 0) return "local"
  var sign = diff > 0 ? "+" : "−"
  var a = Math.abs(diff)
  var h = Math.floor(a / 60), m = a % 60
  return sign + h + "h" + (m ? pad(m) : "")
}

function dayShiftLabel(delta) {
  if (delta === 0) return ""
  return delta > 0 ? "+" + delta + "d" : "−" + (-delta) + "d"
}

// "in 2h 15m" / "3h ago" / "now", for the hero under the picked time.
function fromNowLabel(ms, nowMs) {
  var diff = Math.round((ms - nowMs) / 60000)
  if (Math.abs(diff) < 1) return "now"
  var a = Math.abs(diff)
  var h = Math.floor(a / 60), m = a % 60
  var span = (h ? h + "h" : "") + (h && m ? " " : "") + (m ? m + "m" : "")
  return diff > 0 ? "in " + span : span + " ago"
}
