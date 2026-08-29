import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.archer-clawbot.hermes-harness"
  ipcTarget: "io.github.archer-clawbot.hermes-harness"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var status: ({ installed: false, version: "", gatewayState: "unknown", activeModel: "", currentSessionId: "", currentSessionTitle: "", hermesNodeAvailable: false, nodesOnline: 0, nodesTotal: 0, nodes: {}, remote: false, remoteStale: false })
  property string lastError: ""
  readonly property var barIdentity: hostWidget || root
  readonly property bool gatewayActive: status.gatewayState === "active"
  // A remote record describes a Hermes on another host. There is no local
  // executable to launch there, so the local launch actions are withheld
  // rather than left to fail against a command that does not exist.
  readonly property bool remote: status.remote === true
  readonly property bool remoteStale: status.remoteStale === true
  readonly property bool canLaunchLocally: !remote
  readonly property int refreshSeconds: Math.max(10, parseInt(setting("refreshIntervalSec", 15), 10) || 15)
  readonly property string barLabel: status.installed ? (gatewayActive ? "⚕" : "⚕·") : "⚕×"

  function display(value, fallback) {
    var text = String(value === undefined || value === null ? "" : value)
    return text === "" ? fallback : text
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function open() {
    root.controller.show()
    refresh()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) close()
    else open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function acceptStatus(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      if (!parsed || typeof parsed !== "object") throw new Error("status is not an object")
      status = parsed
      lastError = ""
    } catch (error) {
      lastError = "Status refresh failed"
    }
  }

  Process {
    id: statusProc
    command: ["bash", Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.archer-clawbot.hermes-harness/scripts/hermes-status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.acceptStatus(text) }
    onExited: function(exitCode) { if (exitCode !== 0) root.lastError = "Status command exited " + exitCode }
  }

  Timer {
    interval: root.refreshSeconds * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        Row {
          width: parent.width
          spacing: Style.space(14)

          Text {
            text: root.barLabel
            textFormat: Text.PlainText
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
          }

          Column {
            width: parent.width - parent.children[0].implicitWidth - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.labelGap
            Text {
              text: "Hermes Harness"
              textFormat: Text.PlainText
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              width: parent.width
              text: root.status.installed ? root.display(root.status.version, "Installed") : "NOT INSTALLED"
              textFormat: Text.PlainText
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        Column {
          width: parent.width
          spacing: Style.space(8)
          InfoPair { label: "Hermes host"; value: root.remote ? (root.remoteStale ? "remote (record expired)" : "remote (published record)") : "local" }
          InfoPair { label: "Gateway"; value: root.display(root.status.gatewayState, "unknown") }
          InfoPair { label: "Active model"; value: root.display(root.status.activeModel, "unknown") }
          InfoPair { label: "Session"; value: root.display(root.status.currentSessionTitle, root.display(root.status.currentSessionId, "none")) }
          InfoPair { label: "Federated nodes"; value: root.status.hermesNodeAvailable ? (Number(root.status.nodesOnline || 0) + "/" + Number(root.status.nodesTotal || 0) + " online") : "hermes-node unavailable" }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)
          PanelSectionHeader { text: "NODES"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }
          Repeater {
            model: Object.keys(root.status.nodes || {}).sort()
            Row {
              required property var modelData
              width: parent.width
              spacing: Style.space(8)
              Text { text: root.status.nodes[modelData].online ? "●" : "○"; textFormat: Text.PlainText; color: root.bar.foreground; font.pixelSize: Style.font.body }
              Text { text: String(modelData); textFormat: Text.PlainText; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
              Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[1].implicitWidth - parent.children[3].implicitWidth - parent.spacing * 3); height: 1 }
              Text { text: root.status.nodes[modelData].online ? "online" : "offline"; textFormat: Text.PlainText; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
            }
          }
        }

        Text {
          visible: root.lastError !== ""
          text: root.lastError
          textFormat: Text.PlainText
          color: root.bar.urgent
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          visible: root.remote
          width: parent.width
          text: "Hermes runs on another host. Local launch is unavailable in remote mode."
          textFormat: Text.PlainText
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Button {
          visible: root.canLaunchLocally
          width: parent.width
          text: "Open Hermes"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          bordered: true
          onClicked: {
            if (!root.canLaunchLocally) return
            if (root.bar) root.bar.run("hermes")
            root.close()
          }
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""
    width: parent.width
    spacing: Style.space(8)
    Text { text: label; textFormat: Text.PlainText; color: Qt.darker(root.bar.foreground, 1.35); font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    Text { text: value; textFormat: Text.PlainText; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; elide: Text.ElideLeft; width: Math.min(implicitWidth, parent.width * 0.65) }
  }
}
