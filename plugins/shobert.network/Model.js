function parseNetworkStatus(raw) {
  var parts = String(raw || "disconnected\t\t\t").replace(/\r?\n+$/, "").split("\t")
  return {
    kind: parts[0] || "disconnected",
    label: parts[1] || "",
    signalStrength: parts[2] ? parseInt(parts[2], 10) : -1,
    frequency: parts[3] || ""
  }
}

function wifiIconFor(strength) {
  var icons = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
  var index = Math.max(0, Math.min(4, Math.ceil(strength / 20) - 1))
  return icons[index]
}

function connectionIcon(kind, signalStrength) {
  if (kind === "wifi") return wifiIconFor(signalStrength)
  if (kind === "ethernet") return "󰈀"
  return "󰤮"
}

function formatHeaderSpeed(mbps) {
  var v = parseInt(mbps, 10)
  if (!v || v < 0) return ""
  if (v >= 1000) return (v / 1000).toFixed(v % 1000 === 0 ? 0 : 1) + "gbit"
  return v + "mbit"
}

function formatHeaderFreq(mhz) {
  var v = parseFloat(mhz)
  if (!v) return ""

  if (v >= 2400 && v < 2500) return "2.4ghz"
  if (v >= 4900 && v < 5925) return "5ghz"
  if (v >= 5925 && v < 7125) return "6ghz"
  if (v >= 57000 && v < 71000) return "60ghz"

  var ghz = v / 1000
  return ghz.toFixed(ghz % 1 === 0 ? 0 : 1) + "ghz"
}

// Wi-Fi band state belongs in the selector section, not beside the hero name.
// Ethernet has no equivalent selector, so keep its negotiated link speed here.
function headerDetail(info) {
  var value = info || {}
  if (value.type === "ethernet") return formatHeaderSpeed(value.speed || "")
  return ""
}

function bandLabel(band) {
  if (band === "auto") return "Auto"
  if (!band) return ""
  return band + "ghz"
}

// Under Automatic the pills are hidden, so the header carries the live band
// instead -- "WI-FI BAND: 2.4GHZ". Once a band is pinned the pills are on
// screen and say it themselves, so the header drops back to a plain label.
function bandSectionTitle(selected, current) {
  if (selected !== "auto") return "WI-FI BAND"

  var label = bandLabel(current)
  if (label === "") return "WI-FI BAND"

  return "WI-FI BAND: " + label.toUpperCase()
}

function bandTooltip(band) {
  if (band === "auto") return "Let Wi-Fi pick the band"
  if (!band) return ""
  return "Stay on " + bandLabel(band)
}

function parseBandStatus(raw) {
  var next = parseKeyValue(raw)
  var tokens = String(next.available || "").split(" ")
  var available = []

  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i] !== "") available.push(tokens[i])
  }

  return {
    band: next.band || "",
    selected: next.selected || "auto",
    available: available
  }
}

function decodeIwSsid(value) {
  var raw = String(value || "")

  try {
    var encoded = ""

    for (var i = 0; i < raw.length; i++) {
      if (raw[i] === "\\" && raw[i + 1] === "x" && /^[0-9a-f]{2}$/i.test(raw.substring(i + 2, i + 4))) {
        var hex = raw.substring(i + 2, i + 4)
        var byte = parseInt(hex, 16)
        encoded += byte < 32 || byte === 127 ? encodeURIComponent(raw.substring(i, i + 4)) : "%" + hex
        i += 3
      } else {
        encoded += encodeURIComponent(raw[i])
      }
    }

    return decodeURIComponent(encoded)
  } catch (error) {
    return raw
  }
}

function parseKeyValue(raw) {
  var next = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (!line) continue
    var idx = line.indexOf("\t")
    if (idx === -1) continue
    var key = line.substring(0, idx)
    var value = line.substring(idx + 1)
    next[key] = key === "ssid" ? decodeIwSsid(value) : value.trim()
  }
  return next
}

function throughputState(previous, next, now) {
  var prev = previous || {}
  var sample = next || {}
  var iface = sample.iface || ""
  var rx = parseFloat(sample.rx_bytes || "0")
  var tx = parseFloat(sample.tx_bytes || "0")
  var previousTime = Number(prev.prevSampleTime || 0)

  if (iface !== (prev.prevIface || "") || previousTime === 0) {
    return {
      prevIface: iface,
      prevRxBytes: rx,
      prevTxBytes: tx,
      prevSampleTime: now,
      downloadRate: 0,
      uploadRate: 0
    }
  }

  var downloadRate = Number(prev.downloadRate || 0)
  var uploadRate = Number(prev.uploadRate || 0)
  var dt = now - previousTime
  if (dt > 0) {
    downloadRate = Math.max(0, (rx - Number(prev.prevRxBytes || 0)) / dt)
    uploadRate = Math.max(0, (tx - Number(prev.prevTxBytes || 0)) / dt)
  }

  return {
    prevIface: iface,
    prevRxBytes: rx,
    prevTxBytes: tx,
    prevSampleTime: now,
    downloadRate: downloadRate,
    uploadRate: uploadRate
  }
}

function pingSampleValue(raw) {
  var value = parseFloat(raw)
  if (!isFinite(value) || value < 0) return null
  return value
}

function appendPingSample(samples, raw, limit) {
  var values = Array.isArray(samples) ? samples.slice() : []

  values.push(pingSampleValue(raw))
  while (values.length > limit) values.shift()

  return values
}

function averagePingLatency(samples, limit) {
  var values = Array.isArray(samples) ? samples : []
  var sampleLimit = Math.max(1, parseInt(limit, 10) || values.length || 1)
  var total = 0
  var count = 0

  for (var i = Math.max(0, values.length - sampleLimit); i < values.length; i++) {
    var value = values[i]
    if (typeof value !== "number" || !isFinite(value) || value < 0) continue
    total += value
    count++
  }

  return count > 0 ? total / count : -1
}

function pingPacketLossPercent(samples) {
  var values = Array.isArray(samples) ? samples : []
  if (values.length === 0) return 0

  var lost = 0
  for (var i = 0; i < values.length; i++) {
    if (values[i] === null) lost++
  }

  return Math.round((lost / values.length) * 100)
}

function formatPacketLoss(percent, hasSamples) {
  if (hasSamples === false) return "--"

  var value = parseInt(percent, 10)
  if (!value || value < 0) return "0%"
  return value + "%"
}

function pingLatencyState(previous, next, limit, averageLimit) {
  var prev = previous || {}
  var sample = next || {}
  var iface = sample.iface || ""
  var window = Math.max(1, parseInt(limit, 10) || 5)
  var averageWindow = Math.max(1, parseInt(averageLimit, 10) || window)
  var reset = iface === "" || iface !== (prev.pingIface || "")
  var routerSamples = reset ? [] : prev.routerPingSamples
  var internetSamples = reset ? [] : prev.internetPingSamples

  routerSamples = sample.router_ping_ms === undefined ? [] : appendPingSample(routerSamples, sample.router_ping_ms, window)
  internetSamples = sample.internet_ping_ms === undefined ? [] : appendPingSample(internetSamples, sample.internet_ping_ms, window)

  return {
    pingIface: iface,
    routerPingSamples: routerSamples,
    internetPingSamples: internetSamples,
    routerPingLatency: averagePingLatency(routerSamples, averageWindow),
    internetPingLatency: averagePingLatency(internetSamples, averageWindow),
    internetPingPacketLoss: pingPacketLossPercent(internetSamples)
  }
}

function formatBytes(bytes) {
  var n = Number(bytes)
  if (!isFinite(n) || n < 0) n = 0
  if (n < 1024) return Math.round(n) + " B"
  if (n < 1024 * 1024) return (n / 1024).toFixed(1) + " KB"
  if (n < 1024 * 1024 * 1024) return (n / (1024 * 1024)).toFixed(1) + " MB"
  return (n / (1024 * 1024 * 1024)).toFixed(2) + " GB"
}

function formatRate(bytesPerSec) {
  return formatBytes(bytesPerSec) + "/s"
}

// `hasSamples` false means no probe has come back yet, which is different from
// a probe that timed out. The rows stay mounted through that gap and read "--"
// so the grid doesn't reflow a second after the panel opens.
function formatPingLatency(ms, hasSamples) {
  if (hasSamples === false) return "--"

  var value = parseFloat(ms)
  if (!isFinite(value) || value < 0) return "Timeout"
  return value.toFixed(value > 0 && value < 10 ? 1 : 0) + " ms"
}

function wifiRow(network) {
  if (!network) return null
  // Primitives only: rows become list-model data, so a WifiNetwork here puts a
  // live QObject wrapper in every delegate's var property. NetworkManager churn
  // (scans, AP removals) can destroy the object while a delegate is still
  // incubating, which segfaults quickshell in wrap_slowPath on the dangling
  // wrapper. Callers that need the object resolve it via networkForSsid().
  return {
    connected: !!network.connected,
    known: !!network.known,
    ssid: network.name || "",
    signal: Math.round((network.signalStrength || 0) * 100),
    security: network.security
  }
}

function sortWifiRows(rows) {
  var nets = Array.isArray(rows) ? rows.slice() : []
  nets.sort(function(a, b) {
    if (a.connected !== b.connected) return a.connected ? -1 : 1
    if (a.known !== b.known) return a.known ? -1 : 1
    return b.signal - a.signal
  })
  return nets
}

function wifiSectionTitle(wifiNetworks, index) {
  var networks = Array.isArray(wifiNetworks) ? wifiNetworks : []
  if (index < 0 || index >= networks.length) return ""

  var net = networks[index]
  if (!net) return ""

  if (net.known && index === 0) return "KNOWN NETWORKS"
  if (!net.known && (index === 0 || (networks[index - 1] && networks[index - 1].known))) return "OTHER NETWORKS"
  return ""
}

function isProtected(security, openSecurity) {
  return security !== openSecurity
}

// The password arrives on stdin and reaches nmcli through the scriptable
// `connection edit` editor -- argv is world-readable in /proc, so the secret
// must never be an argument (printf is a bash builtin, so no process spawns
// with it either).
var enterpriseConnectScript =
  "u=$(uuidgen); IFS= read -r pw;" +
  " nmcli connection add type wifi con-name \"$1\" ssid \"$1\" connection.uuid \"$u\"" +
  " wifi-sec.key-mgmt wpa-eap 802-1x.eap peap 802-1x.phase2-auth mschapv2" +
  " 802-1x.identity \"$2\" 802-1x.auth-timeout 8 >/dev/null" +
  " && printf 'set 802-1x.password %s\\nsave\\nquit\\n' \"$pw\" | nmcli connection edit uuid \"$u\" >/dev/null" +
  " && nmcli connection up uuid \"$u\"" +
  " || { nmcli connection delete uuid \"$u\" >/dev/null 2>&1; false; }"

function networkFailureReason(reason, reasons) {
  var r = reasons || {}
  if (reason === r.NoSecrets) return "Passphrase required"
  if (reason === r.WifiAuthTimeout) return "Wrong password"
  if (reason === r.WifiNetworkLost) return "Network lost"
  if (reason === r.WifiClientDisconnected) return "Disconnected"
  if (reason === r.WifiClientFailed) return "Connection failed"
  return "Failed to connect"
}

// Whether a failed connect should reopen the passphrase prompt. NoSecrets
// always means credentials are missing. An auth timeout on a protected
// network means the saved passphrase is wrong (the same profile a first
// failed attempt leaves behind as "known"), so the user needs a chance to
// re-enter it -- connectWithPsk overwrites the stored PSK on submit.
function shouldRepromptPassphrase(reason, isProtected, reasons) {
  var r = reasons || {}
  if (reason === r.NoSecrets) return true
  return !!isProtected && reason === r.WifiAuthTimeout
}


// ------------------------------------------------------------- hotspot --

// The three ways omarchy-network-hotspot can bridge this machine's two
// radios. Labels read upstream-first -- what is being shared, then how
// clients reach it -- because that is the choice being made.
var hotspotModes = [
  { id: "lan-wifi", label: "LAN → WI-FI", detail: "Share the wired connection over Wi-Fi" },
  { id: "wifi-repeat", label: "WI-FI → WI-FI", detail: "Repeat the Wi-Fi link on a second access point" },
  { id: "wifi-lan", label: "WI-FI → LAN", detail: "Share the Wi-Fi link out the wired port" }
]

function hotspotModeAt(index) {
  if (index < 0 || index >= hotspotModes.length) return null
  return hotspotModes[index]
}

function hotspotModeIndex(id) {
  for (var i = 0; i < hotspotModes.length; i++) {
    if (hotspotModes[i].id === id) return i
  }
  return -1
}

function hotspotModeLabel(id) {
  var index = hotspotModeIndex(id)
  return index < 0 ? "" : hotspotModes[index].label
}

function parseHotspotStatus(raw) {
  var next = parseKeyValue(raw)
  var tokens = String(next.available || "").split(" ")
  var available = []
  var reasons = {}

  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i] !== "") available.push(tokens[i])
  }

  for (var m = 0; m < hotspotModes.length; m++) {
    var reason = next["reason." + hotspotModes[m].id]
    if (reason) reasons[hotspotModes[m].id] = reason
  }

  return {
    // An empty read means the command has not answered yet, which is not the
    // same as a machine that cannot run a hotspot -- the section stays
    // unmounted until `loaded` turns true rather than flashing "not set up".
    loaded: next.setup !== undefined,
    setup: next.setup === "1",
    setupMissing: next.setupMissing || "",
    active: next.active === "1",
    mode: next.mode || "lan-wifi",
    available: available,
    reasons: reasons,
    name: next.name || "",
    station: next.station || "",
    wifiDevice: next.wifiDevice || "",
    ethernetDevice: next.ethernetDevice || "",
    iface: next.iface || "",
    upstream: next.upstream || "",
    clients: parseInt(next.clients || "0", 10) || 0,
    address: next.address || "",
    band: next.band || "",
    channel: next.channel || ""
  }
}

function hotspotModeAvailable(status, id) {
  var available = (status && status.available) || []
  return available.indexOf(id) !== -1
}

// A mode that cannot be picked says why in place of what it does: the reason
// is the only thing the user can act on.
function hotspotModeTooltip(status, id) {
  var reasons = (status && status.reasons) || {}
  if (reasons[id]) return reasons[id]

  var index = hotspotModeIndex(id)
  return index < 0 ? "" : hotspotModes[index].detail
}

// The client count rides in the header while the hotspot is up: it is the one
// number worth reading at a glance, and it saves a row in the grid below.
function hotspotSectionTitle(status) {
  if (!status || !status.active) return "HOTSPOT"

  var clients = status.clients || 0
  if (clients === 0) return "HOTSPOT: NO CLIENTS"
  if (clients === 1) return "HOTSPOT: 1 CLIENT"
  return "HOTSPOT: " + clients + " CLIENTS"
}

function hotspotUpstreamLabel(status) {
  if (!status || !status.active) return "--"
  if (status.mode === "lan-wifi") return status.upstream ? "Ethernet (" + status.upstream + ")" : "Ethernet"
  return status.station ? "Wi-Fi (" + status.station + ")" : "Wi-Fi"
}

// Only the wireless modes have one; the wired hotspot's row reads "--".
function hotspotChannelLabel(status) {
  if (!status || !status.active || status.mode === "wifi-lan") return "--"
  if (!status.channel) return "--"

  var band = status.band ? status.band + "ghz · " : ""
  return band + "ch " + status.channel
}

// NetworkManager reports the shared address with its prefix ("10.42.0.1/24");
// clients only ever need the address itself.
function hotspotAddress(status) {
  var address = (status && status.address) || ""
  var slash = address.indexOf("/")
  return slash === -1 ? address : address.substring(0, slash)
}

// Turns the setup command's token list into something that reads as a
// sentence, so the prompt says what is missing rather than that something is.
function hotspotSetupSummary(status) {
  var phrases = { dnsmasq: "dnsmasq", helper: "a privileged helper", sudoers: "a sudoers rule" }
  var tokens = String((status && status.setupMissing) || "").split(" ")
  var missing = []

  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i] !== "") missing.push(phrases[tokens[i]] || tokens[i])
  }

  if (missing.length === 0) return ""
  if (missing.length === 1) return "Needs " + missing[0]
  return "Needs " + missing.slice(0, -1).join(", ") + " and " + missing[missing.length - 1]
}

// $1 is the new name ("" leaves it alone), $2 whether a passphrase is waiting
// on stdin. One invocation so a rename and a new passphrase cannot half-apply,
// and the secret stays off argv, which is world-readable in /proc.
var hotspotSaveScript =
  "set -e;" +
  " if [ -n \"$1\" ]; then omarchy-network-hotspot name \"$1\"; fi;" +
  " if [ \"$2\" = 1 ]; then omarchy-network-hotspot password; fi"

// Command failures arrive as "omarchy-network-hotspot: could not ...". Inside
// a panel that is already about the hotspot, the prefix is noise, and only the
// last line carries the reason.
function hotspotErrorText(raw) {
  var lines = String(raw || "").split("\n")
  var message = ""

  for (var i = lines.length - 1; i >= 0; i--) {
    if (lines[i].trim() !== "") { message = lines[i].trim(); break }
  }

  if (message === "") return "Something went wrong"

  message = message.replace(/^[a-z0-9-]+:\s*/, "")
  return message.charAt(0).toUpperCase() + message.slice(1)
}

if (typeof module !== "undefined") {
  module.exports = {
    parseNetworkStatus: parseNetworkStatus,
    wifiIconFor: wifiIconFor,
    connectionIcon: connectionIcon,
    formatHeaderSpeed: formatHeaderSpeed,
    formatHeaderFreq: formatHeaderFreq,
    headerDetail: headerDetail,
    bandLabel: bandLabel,
    bandSectionTitle: bandSectionTitle,
    bandTooltip: bandTooltip,
    parseBandStatus: parseBandStatus,
    decodeIwSsid: decodeIwSsid,
    parseKeyValue: parseKeyValue,
    throughputState: throughputState,
    pingLatencyState: pingLatencyState,
    pingPacketLossPercent: pingPacketLossPercent,
    formatPacketLoss: formatPacketLoss,
    formatBytes: formatBytes,
    formatRate: formatRate,
    formatPingLatency: formatPingLatency,
    wifiRow: wifiRow,
    sortWifiRows: sortWifiRows,
    wifiSectionTitle: wifiSectionTitle,
    isProtected: isProtected,
    enterpriseConnectScript: enterpriseConnectScript,
    networkFailureReason: networkFailureReason,
    shouldRepromptPassphrase: shouldRepromptPassphrase,
    hotspotModes: hotspotModes,
    hotspotModeAt: hotspotModeAt,
    hotspotModeIndex: hotspotModeIndex,
    hotspotModeLabel: hotspotModeLabel,
    parseHotspotStatus: parseHotspotStatus,
    hotspotModeAvailable: hotspotModeAvailable,
    hotspotModeTooltip: hotspotModeTooltip,
    hotspotSectionTitle: hotspotSectionTitle,
    hotspotUpstreamLabel: hotspotUpstreamLabel,
    hotspotChannelLabel: hotspotChannelLabel,
    hotspotAddress: hotspotAddress,
    hotspotSetupSummary: hotspotSetupSummary,
    hotspotSaveScript: hotspotSaveScript,
    hotspotErrorText: hotspotErrorText
  }
}
