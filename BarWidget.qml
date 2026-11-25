import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar icon with a popup of four sliders for a Sonos home-theater setup:
// volume, EQ bass, sub level, and surround level for TV and for music.
// All network work happens in the `sonos-sound` helper next to this file.
Panel {
  id: root
  moduleName: "rune.sonos-sound"
  ipcTarget: "rune.sonos-sound"

  readonly property string helper: Qt.resolvedUrl("sonos-sound").toString().replace(/^file:\/\//, "")
  readonly property string host: String(setting("host", ""))
  readonly property color dim: Qt.darker(bar ? bar.foreground : Color.foreground, 1.4)

  property var levels: ({})
  property string error: ""
  property var queued: null           // { key, value } waiting for the running write to finish
  property real wheelAccumulator: 0
  property int volumeTarget: -1      // where the volume slider wants to go; -1 = nowhere
  property int volumeLimit: 100      // highest volume allowed, 1..100; kept on this PC only

  readonly property var rows: [
    { key: "limit", label: "Volumgrense", min: 1, max: 100 },
    { key: "volume", label: "Volum", min: 0, max: 100 },
    { key: "bass", label: "Bass", min: -10, max: 10 },
    { key: "sub", label: "Sub", min: -15, max: 15 },
    { key: "tv", label: "Surround TV", min: -15, max: 15 },
    { key: "music", label: "Surround musikk", min: -15, max: 15 }
  ]

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function apply(text) {
    var data
    try { data = JSON.parse(text) } catch (e) { error = "Ingen svar fra hjelperen"; return }
    if (data.ok) {
      levels = data; error = ""
      // Turned up past the limit somewhere else (Sonos app, TV remote): bring it back down.
      if (data.volume !== undefined && data.volume > volumeLimit && volumeTarget < 0) rampVolume(volumeLimit)
    }
    else error = String(data.error || "Ukjent feil").slice(0, 120)
  }

  function refresh() {
    if (host === "") { error = "Sett soundbar-IP: omarchy bar set rune.sonos-sound host <ip>"; return }
    if (!readProc.running && !writeProc.running) readProc.running = true
  }

  // The volume never jumps: the slider sets a target and the speaker walks
  // there one step (1 of 100) per write, so a click far along the track
  // cannot blast the room.
  function rampVolume(value) {
    volumeTarget = Math.max(0, Math.min(volumeLimit, Math.round(value)))
    stepVolume()
  }

  function stepVolume() {
    if (volumeTarget < 0 || writeProc.running) return
    var current = levels.volume
    if (current === undefined || current === volumeTarget) { volumeTarget = -1; return }
    setLevel("volume", current + (volumeTarget > current ? 1 : -1))
  }

  function changed(key, value) {
    if (key === "limit") setLimit(value)
    else if (key === "volume") rampVolume(value)
    else setLevel(key, value)
  }

  // The limit is ours, not the speaker's: it caps every volume change made
  // here and pulls the volume down if it is above the new limit.
  function setLimit(value) {
    var limit = Math.max(1, Math.min(100, Math.round(value)))
    if (limit === volumeLimit) return
    volumeLimit = limit
    limitFile.setText(String(limit) + "\n")
    if (levels.volume !== undefined && levels.volume > limit) rampVolume(limit)
  }

  FileView {
    id: limitFile
    path: (Quickshell.env("HOME") || "") + "/.local/state/omarchy/sonos-sound-volume-limit"
    printErrors: false
    onLoaded: {
      var n = parseInt(text(), 10)
      if (n >= 1 && n <= 100) root.volumeLimit = n
    }
  }

  // Dragging fires many values; send one at a time and keep only the newest.
  function setLevel(key, value) {
    var next = Object.assign({}, levels)
    next[key] = Math.round(value)
    levels = next
    if (host === "") return
    if (writeProc.running) { queued = { key: key, value: Math.round(value) }; return }
    writeProc.command = [helper, host, "set", key, String(Math.round(value))]
    writeProc.running = true
  }

  onOpenedChanged: if (opened) refresh()

  Process {
    id: readProc
    command: [root.helper, root.host, "get"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.apply(text) }
  }

  Process {
    id: writeProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: if (!root.queued) root.apply(text) }
    onExited: {
      if (!root.queued) { root.stepVolume(); return }
      var q = root.queued
      root.queued = null
      root.setLevel(q.key, q.value)
    }
  }

  // Keep the popup in step with changes made in the Sonos app.
  Timer { interval: 3000; repeat: true; running: root.opened; onTriggered: root.refresh() }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: String.fromCodePoint(0xF066A)
    tooltipText: root.levels.volume !== undefined ? "Sonos lyd · volum " + root.levels.volume : "Sonos lyd"
    onPressed: function(b) { root.toggle() }
    onWheelMoved: function(delta) {
      if (root.levels.volume === undefined) { root.refresh(); return }
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      // One volume step (the smallest Sonos has, 1 of 100) per wheel event,
      // however fast the wheel or touchpad spins.
      if (wheel.steps !== 0) root.volumeTarget = -1
      if (wheel.steps !== 0)
        root.setLevel("volume", Math.max(0, Math.min(root.volumeLimit, root.levels.volume + (wheel.steps > 0 ? 1 : -1))))
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(400))

    PanelKeyCatcher {
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        Text {
          textFormat: Text.PlainText
          text: "Sonos lyd"
          color: root.bar ? root.bar.foreground : Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Text {
          visible: root.error !== ""
          width: parent.width
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: root.error
          color: Color.urgent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: root.rows

          Item {
            id: row
            required property var modelData
            readonly property var current: modelData.key === "limit" ? root.volumeLimit : root.levels[modelData.key]
            visible: current !== null && current !== undefined
            width: content.width
            height: visible ? slider.implicitHeight : 0

            Text {
              id: label
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(104)
              textFormat: Text.PlainText
              text: row.modelData.label
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }

            PanelSlider {
              id: slider
              anchors.left: label.right
              anchors.right: number.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              bar: root.bar
              minimum: row.modelData.min
              maximum: row.modelData.max
              step: 1
              integer: true
              value: row.current || 0
              onMoved: function(v) { root.changed(row.modelData.key, v) }
              onReleased: function(v) { root.changed(row.modelData.key, v) }
              // Right-click puts an EQ level back to 0; volume is left alone.
              // Right-click resets: an EQ level to 0, the limit to 100%; volume is left alone.
              onRightClicked: {
                if (row.modelData.key === "limit") root.setLimit(100)
                else if (row.modelData.key !== "volume") root.setLevel(row.modelData.key, 0)
              }
            }

            Text {
              id: number
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(36)
              horizontalAlignment: Text.AlignRight
              textFormat: Text.PlainText
              readonly property int v: Math.round(slider.dragging ? slider.liveValue : (row.current || 0))
              text: (row.modelData.min < 0 && v > 0 ? "+" : "") + v + (row.modelData.key === "limit" ? "%" : "")
              color: root.dim
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }

        Text {
          width: parent.width
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: "Høyreklikk en EQ-slider for å nullstille den, eller volumgrensen for å sette den til 100 %."
          color: root.dim
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
