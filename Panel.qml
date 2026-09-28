import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The world clock popup: the picked time in the selected zone as the hero, a
// slider across that zone's day to pick it, and every configured zone below
// in order showing the same instant on its own wall clock.
//
// Up/down (or a click) choose the zone; the selection starts on the system
// zone and is kept between opens. Left/right step 15 minutes and carry over
// into the next or previous day. The time follows the clock until it is
// moved; Escape, Enter, T, clicking the hero, or reopening the panel go back
// to now, and Escape on now closes the panel.
Panel {
  id: root
  moduleName: "seth.worldclock"
  ipcTarget: "seth.worldclock"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var host: hostWidget
  readonly property var zones: host ? host.zones : []
  readonly property bool hour12: host ? host.hour12 : false
  readonly property real nowMs: host ? host.nowMs : Date.now()
  readonly property real dayStart: host ? host.dayStart : Model.localDayStart(Date.now())
  readonly property real dayEnd: host ? host.dayEnd : Model.localDayEnd(Date.now())
  // Read so bindings below re-evaluate when a fresh offset table lands.
  readonly property var table: host ? host.table : []
  readonly property int systemIndex: host ? host.systemZoneIndex : -1

  // -1 until a zone is picked, which means "the system zone".
  property int pickedIndex: -1
  readonly property int selectedIndex: pickedIndex >= 0 && pickedIndex < zones.length
    ? pickedIndex
    : Math.max(0, systemIndex)

  readonly property int stepMinutes: 15
  property bool followNow: true
  property real pickedMs: nowMs
  readonly property real selectedMs: followNow ? nowMs : pickedMs
  readonly property int localOffset: Model.localOffset(selectedMs)
  readonly property int localDay: Model.dayNumber(selectedMs, localOffset)

  // The slider spans the selected zone's wall-clock day.
  readonly property int selectedOffset: {
    var off = offsetFor(selectedIndex)
    return off === null ? localOffset : off
  }
  readonly property real zoneDay: Model.zoneDayStart(selectedMs, selectedOffset)
  readonly property int sliderMax: 24 * 60

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  function open() {
    goToNow()
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function goToNow() {
    root.followNow = true
  }

  // Escape backs out one level: a moved time returns to now first, and only
  // then does the panel close.
  function back() {
    if (!root.followNow) root.goToNow()
    else root.close()
  }

  function selectZone(index) {
    if (!root.zones.length) return
    root.pickedIndex = Math.max(0, Math.min(root.zones.length - 1, index))
  }

  function setPicked(ms) {
    var lo = root.host ? root.host.tableStart : root.dayStart
    var hi = root.host ? root.host.tableEnd : root.dayEnd
    root.pickedMs = Math.max(lo, Math.min(hi, Model.snapMs(ms, root.stepMinutes)))
    root.followNow = false
  }

  // Minutes past midnight on the selected zone's wall clock. The instant is
  // solved with that zone's offset at the target, so it stays right on a day
  // the zone changes to or from daylight saving.
  function pickMinutes(minutes) {
    var snapped = Math.max(0, Math.min(root.sliderMax, Math.round(minutes / root.stepMinutes) * root.stepMinutes))
    var wall = root.zoneDay + (root.selectedOffset + snapped) * 60000
    var guess = wall - root.selectedOffset * 60000
    var off = root.host ? root.host.offsetAt(root.selectedIndex, guess) : null
    setPicked(off === null ? guess : wall - off * 60000)
  }

  function stepBy(minutes) {
    setPicked(root.selectedMs + minutes * 60000)
  }

  function offsetFor(index) {
    var off = root.host ? root.host.offsetAt(index, root.selectedMs) : null
    // Touching table ties the binding to reloads.
    return root.table && off !== null ? off : null
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.stepBy(dx * root.stepMinutes)
        if (dy !== 0) root.selectZone(root.selectedIndex + dy)
      }
      onActivateRequested: root.goToNow()
      onCloseRequested: root.back()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "t" || t === "T") root.goToNow()
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        // ---- Hero: the picked local time. Clicking it returns to now.
        Item {
          width: parent.width
          height: heroColumn.height

          Column {
            id: heroColumn
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(2)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              textFormat: Text.PlainText
              text: Model.formatTime(root.selectedMs, root.selectedOffset, root.hour12)
              color: heroMouse.containsMouse && !root.followNow
                ? Style.hoverStateColor(root.contentForeground, Color.accent)
                : root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: 44
              font.bold: true
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              textFormat: Text.PlainText
              text: [
                  root.zones.length ? root.zones[root.selectedIndex].label : "",
                  root.host ? root.host.abbrAt(root.selectedIndex, root.selectedMs) : "",
                  Model.formatDay(root.selectedMs, root.selectedOffset),
                  Model.fromNowLabel(root.selectedMs, root.nowMs)
                ].filter(function(p) { return p !== "" }).join("  ·  ").toUpperCase()
              color: Qt.darker(root.contentForeground, 1.5)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              font.letterSpacing: 1
            }
          }

          MouseArea {
            id: heroMouse
            x: heroColumn.x
            width: heroColumn.width
            height: heroColumn.height
            enabled: !root.followNow
            hoverEnabled: enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: root.goToNow()

            PanelToolTip {
              visible: heroMouse.containsMouse
              text: "Back to now"
              fontFamily: root.contentFontFamily
            }
          }
        }

        // ---- Slider across the selected zone's day, notched every three hours.
        Column {
          width: parent.width
          spacing: Style.space(2)

          PanelSlider {
            id: slider
            bar: root.bar
            width: parent.width
            minimum: 0
            maximum: root.sliderMax
            step: root.stepMinutes
            value: (root.selectedMs - root.zoneDay) / 60000
            tickCount: 9
            onMoved: function(v) { root.pickMinutes(v) }
          }

          Item {
            width: parent.width
            height: Style.font.caption + Style.space(4)

            Repeater {
              model: [0, 6, 12, 18, 24]

              Text {
                required property var modelData
                required property int index
                textFormat: Text.PlainText
                x: Math.max(0, Math.min(parent.width - width, parent.width * (modelData / 24) - width / 2))
                text: root.hour12
                  ? (modelData % 24 === 0 ? "12a" : modelData === 12 ? "12p" : (modelData % 12) + (modelData < 12 ? "a" : "p"))
                  : Model.pad(modelData % 24 === 0 && index > 0 ? 24 : modelData)
                color: Qt.darker(root.contentForeground, 1.9)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        PanelSeparator { width: parent.width }

        // ---- The zones, in configured order. The selected zone is filled,
        //      the system zone is bold. Hours outside 08-18 dim, and
        //      overnight hours dim further, so meeting-friendly overlap
        //      reads at a glance.
        Column {
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: root.zones

            Item {
              id: zoneRow
              required property var modelData
              required property int index

              readonly property var offset: root.offsetFor(index)
              readonly property bool ready: offset !== null
              readonly property int hour: ready ? Model.hourOf(root.selectedMs, offset) : 12
              readonly property bool isSystem: index === root.systemIndex
              readonly property bool isSelected: index === root.selectedIndex
              readonly property int dayDelta: ready ? Model.dayNumber(root.selectedMs, offset) - root.localDay : 0
              readonly property real strength: !ready ? 0.5
                : (hour >= 8 && hour < 18) ? 1.0
                : (hour >= 7 && hour < 22) ? 0.7
                : 0.45

              width: parent.width
              height: Style.space(30)

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: zoneRow.isSelected
                  ? Style.hoverFillFor(root.contentForeground, Color.accent)
                  : "transparent"
                border.width: zoneRow.isSelected ? Style.spacing.hairline : 0
                border.color: Style.normalBorderFor(root.contentForeground, Color.accent)
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectZone(zoneRow.index)
              }

              Text {
                id: zoneLabel
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(130)
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: zoneRow.modelData.label
                color: root.contentForeground
                opacity: zoneRow.strength
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.bold: zoneRow.isSystem
              }

              Text {
                anchors.left: zoneLabel.right
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(90)
                textFormat: Text.PlainText
                text: zoneRow.ready
                  ? root.host.abbrAt(zoneRow.index, root.selectedMs) + " " + Model.relativeLabel(zoneRow.offset, root.localOffset)
                  : ""
                color: Qt.darker(root.contentForeground, 1.6)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
              }

              Text {
                id: dayText
                anchors.right: timeText.left
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: zoneRow.ready
                  ? Model.formatDay(root.selectedMs, zoneRow.offset).split(" ")[0]
                    + (zoneRow.dayDelta !== 0 ? " " + Model.dayShiftLabel(zoneRow.dayDelta) : "")
                  : ""
                color: zoneRow.dayDelta !== 0
                  ? Style.selectedStateColor(root.contentForeground, Color.accent)
                  : Qt.darker(root.contentForeground, 1.6)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
              }

              Text {
                id: timeText
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: zoneRow.ready ? Model.formatTime(root.selectedMs, zoneRow.offset, root.hour12) : "…"
                color: root.contentForeground
                opacity: zoneRow.strength
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.bold: zoneRow.isSystem
              }
            }
          }
        }
      }
    }
  }
}
