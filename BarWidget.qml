import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// World clock for the bar: a short label (the zones listed in `barZones`)
// and a popup listing every zone, with a slider that picks a local time and
// shows it across the list.
//
// The shell's JS engine has no Intl, so offsets come from `date`: one run
// samples every zone on each hour from local midnight yesterday to midnight
// tomorrow (so any zone's whole day is covered), and the panel reads the
// table instead of shelling out as the slider moves. The same run reports the
// system zone, which the panel picks out in bold.
BarWidget {
  id: root
  moduleName: "seth.worldclock"

  readonly property var zones: Model.normalizedZones(setting("zones", null))
  readonly property var barZones: setting("barZones", ["UTC"])
  readonly property bool hour12: setting("hour12", false) === true

  property real nowMs: Date.now()
  property real dayStart: Model.localDayStart(nowMs)
  property real dayEnd: Model.localDayEnd(nowMs)
  property real tableStart: dayStart - Model.DAY_MS
  property real tableEnd: dayEnd + Model.DAY_MS
  property var table: []
  property string systemTz: ""

  // The configured zone the system clock is on: matched by name first, then
  // by the current offset for a system zone not in the list under that name.
  readonly property int systemZoneIndex: {
    for (var i = 0; i < zones.length; i++) if (zones[i].tz === systemTz) return i
    var local = Model.localOffset(nowMs)
    for (var j = 0; j < zones.length; j++) if (offsetAt(j, nowMs) === local) return j
    return -1
  }

  // Built from zones on every change so a shell.json edit takes effect
  // without waiting for the next hourly reload.
  readonly property string zoneKey: JSON.stringify(zones)
  onZoneKeyChanged: Qt.callLater(root.reload)

  function reload() {
    if (offsets.running) { offsets.queued = true; return }
    root.dayStart = Model.localDayStart(root.nowMs)
    root.dayEnd = Model.localDayEnd(root.nowMs)
    root.tableStart = root.dayStart - Model.DAY_MS
    root.tableEnd = root.dayEnd + Model.DAY_MS
    var samples = Math.round((root.tableEnd - root.tableStart) / Model.HOUR_MS) + 1
    var args = ["bash", "-c",
      'tz=$(readlink -f /etc/localtime); echo "${tz#*/zoneinfo/}"; ' +
      'start=$1; n=$2; shift 2; for z in "$@"; do ' +
      'for ((h=0; h<n; h++)); do echo "@$((start + h*3600))"; done | TZ="$z" date -f - "+%z %Z"; done',
      "worldclock", String(Math.floor(root.tableStart / 1000)), String(samples)]
    for (var i = 0; i < root.zones.length; i++) args.push(root.zones[i].tz)
    offsets.pendingSamples = samples
    offsets.pendingCount = root.zones.length
    offsets.command = args
    offsets.running = true
  }

  function offsetAt(zoneIndex, ms) {
    var s = Model.sampleAt(root.table, zoneIndex, root.tableStart, ms)
    return s ? s.offset : null
  }

  function abbrAt(zoneIndex, ms) {
    var s = Model.sampleAt(root.table, zoneIndex, root.tableStart, ms)
    return s ? s.abbr : ""
  }

  function zoneIndex(label) {
    for (var i = 0; i < root.zones.length; i++) if (root.zones[i].label === label) return i
    return -1
  }

  readonly property string displayText: {
    var parts = []
    for (var i = 0; i < root.barZones.length; i++) {
      var idx = zoneIndex(root.barZones[i])
      if (idx < 0) continue
      var off = offsetAt(idx, root.nowMs)
      if (off === null) continue
      parts.push(root.barZones[i] + " " + Model.formatTime(root.nowMs, off, root.hour12))
    }
    return parts.length ? parts.join("  ") : "󰥔"
  }

  // ---- Popup plumbing, the same shape as omarchy.clock: Bar.findPanelWidget
  //      requires open/close/opened on the bar-widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  Component.onCompleted: Qt.callLater(root.reload)

  // Reloads at local midnight for the new day's table, and on the hour so a
  // changed system timezone is picked up without a shell restart.
  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      root.nowMs = clock.date.getTime()
      if (root.nowMs >= root.dayEnd || clock.date.getMinutes() === 0) root.reload()
    }
  }

  Process {
    id: offsets
    property int pendingSamples: 0
    property int pendingCount: 0
    property bool queued: false
    running: false
    command: []
    stdout: StdioCollector {
      id: offsetsOut
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseTable(text, offsets.pendingCount, offsets.pendingSamples)
        if (!parsed) return
        root.systemTz = parsed.systemTz
        root.table = parsed.table
      }
    }
    onExited: {
      if (!offsets.queued) return
      offsets.queued = false
      Qt.callLater(root.reload)
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "seth.worldclock"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function reload(): void { root.reload() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "󰥔" : root.displayText
    horizontalMargin: 8.75
    verticalPadding: 8.75
    onPressed: function(b) { root.togglePanel() }
  }
}
