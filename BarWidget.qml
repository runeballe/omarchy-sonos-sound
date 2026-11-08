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

  readonly property var rows: [
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
    if (data.ok) { levels = data; error = "" }
    else error = String(data.error || "Ukjent feil").slice(0, 120)
  }

  function refresh() {
    if (host === "") { error = "Sett soundbar-IP: omarchy bar set rune.sonos-sound host <ip>"; return }
    if (!readProc.running && !writeProc.running) readProc.running = true
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
      if (!root.queued) return
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
      if (wheel.steps !== 0)
        root.setLevel("volume", Math.max(0, Math.min(100, root.levels.volume + wheel.steps * 2)))
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
          color: root.bar.foreground
          font.family: root.bar.fontFamily
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
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: root.rows

          Item {
            id: row
            required property var modelData
            readonly property var current: root.levels[modelData.key]
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
              color: root.bar.foreground
              font.family: root.bar.fontFamily
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
              onMoved: function(v) { root.setLevel(row.modelData.key, v) }
              onReleased: function(v) { root.setLevel(row.modelData.key, v) }
              // Right-click puts an EQ level back to 0; volume is left alone.
              onRightClicked: if (row.modelData.key !== "volume") root.setLevel(row.modelData.key, 0)
            }

            Text {
              id: number
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(28)
              horizontalAlignment: Text.AlignRight
              textFormat: Text.PlainText
              readonly property int v: Math.round(slider.dragging ? slider.liveValue : (row.current || 0))
              text: (row.modelData.min < 0 && v > 0 ? "+" : "") + v
              color: root.dim
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        Text {
          width: parent.width
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: "Høyreklikk en EQ-slider for å nullstille den."
          color: root.dim
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
