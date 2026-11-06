.pragma library

// Turns `fortivpn status --json` into what the bar and its panel draw. Kept
// out of the QML so it can be read — and exercised — without starting the
// shell.

var MAX_PROFILES = 50
var MAX_TEXT = 300

var DISCONNECTED = {
  state: "disconnected",
  profile: "",
  ip: "",
  uptime: 0,
  connected: false,
  connecting: false,
  defaultProfile: "",
  profiles: [],
  error: "",
  errorKind: "",
  errorProfile: "",
  errorAt: 0
}

// Everything here is shown on screen, and some of it (a gateway host, a
// gateway's error message) is not the plugin's own text: bound it.
function text(value) {
  return value === undefined || value === null ? "" : String(value).slice(0, MAX_TEXT)
}

function count(value) {
  var n = Math.floor(Number(value))
  return isFinite(n) && n > 0 ? n : 0
}

function profiles(list) {
  if (!(list instanceof Array)) return []
  var result = []
  for (var i = 0; i < list.length && result.length < MAX_PROFILES; i++) {
    var p = list[i]
    if (!p || !p.name) continue
    result.push({
      name: text(p.name),
      host: text(p.host),
      isDefault: p["default"] === true,
      pinned: p.pinned === true
    })
  }
  return result
}

// An unreadable or malformed payload is reported as "disconnected" rather than
// as an error state: the CLI only fails to answer when there is nothing to
// answer about, and a widget stuck on an error glyph helps nobody.
function parse(raw) {
  if (!raw) return DISCONNECTED

  var data
  try {
    data = JSON.parse(String(raw).trim())
  } catch (e) {
    return DISCONNECTED
  }
  if (!data || !data.state) return DISCONNECTED

  var kind = data.errorKind === "dropped" || data.errorKind === "failed" ? data.errorKind : ""
  return {
    state: text(data.state),
    profile: text(data.profile),
    ip: text(data.ip),
    uptime: count(data.uptime),
    connected: data.state === "connected",
    connecting: data.state === "connecting",
    defaultProfile: text(data["default"]),
    profiles: profiles(data.profiles),
    error: kind ? text(data.error) : "",
    errorKind: kind,
    errorProfile: kind ? text(data.errorProfile) : "",
    errorAt: kind ? count(data.errorAt) : 0
  }
}

// A tunnel that was up a poll ago and is gone now with a drop in its log went
// away on its own. A clean disconnect leaves no error behind, and a failed
// handshake never reached "connected", so neither of those reads as a drop.
function dropped(previous, current) {
  return previous.connected && !current.connected && !current.connecting
    && current.errorKind === "dropped"
}

// Sub-minute uptimes are noise on a tunnel that just came up, so they read as
// no duration at all rather than as a number that changes every second.
function formatUptime(seconds) {
  seconds = count(seconds)
  if (seconds < 60) return ""

  var hours = Math.floor(seconds / 3600)
  var minutes = Math.floor((seconds % 3600) / 60)
  if (hours === 0) return minutes + "m"
  return hours + "h" + (minutes < 10 ? "0" : "") + minutes
}

// How long ago `epoch` was, as a catalog key and the count to fill it with.
function ago(epoch, nowMs) {
  var seconds = Math.max(0, Math.floor(nowMs / 1000) - count(epoch))
  if (seconds < 60) return { key: "time.justNow", n: 0 }
  if (seconds < 3600) return { key: "time.minutesAgo", n: Math.floor(seconds / 60) }
  if (seconds < 86400) return { key: "time.hoursAgo", n: Math.floor(seconds / 3600) }
  return { key: "time.daysAgo", n: Math.floor(seconds / 86400) }
}

// The notification daemon may read a body as markup.
function escapeMarkup(value) {
  return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

// The bar hands commands to `bash -lc`, so any path that reaches it has to
// survive word splitting. Single quotes with the standard '\'' escape are the
// only form bash treats as fully literal.
function quote(value) {
  return "'" + String(value).replace(/'/g, "'\\''") + "'"
}
