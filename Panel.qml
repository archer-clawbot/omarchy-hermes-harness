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
  property var status: ({ installed: false, version: "", gatewayState: "unknown", activeModel: "", currentSessionId: "", currentSessionTitle: "", nodesOnline: 0, nodesTotal: 0, nodes: {} })
  property string lastError: ""
  readonly property var barIdentity: hostWidget || root
  readonly property bool gatewayActive: status.gatewayState === "active"
  readonly property int refreshSeconds: Math.max(10, parseInt(setting("refreshIntervalSec", 15), 10) || 15)
  readonly property string barLabel: status.installed ? (gatewayActive ? "⚕" : "⚕·") : "⚕×"
  readonly property string tooltipText: !status.installed ? "Hermes not found" : "Hermes · gateway " + status.gatewayState

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
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              width: parent.width
              text: root.status.installed ? root.display(root.status.version, "Installed") : "NOT INSTALLED"
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
              Text { text: root.status.nodes[modelData].online ? "●" : "○"; color: root.bar.foreground; font.pixelSize: Style.font.body }
              Text { text: String(modelData); color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
              Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[1].implicitWidth - parent.children[3].implicitWidth - parent.spacing * 3); height: 1 }
              Text { text: root.status.nodes[modelData].online ? "online" : "offline"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
            }
          }
        }

        Text {
          visible: root.lastError !== ""
          text: root.lastError
          color: root.bar.urgent
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Button {
          width: parent.width
          text: "Open Hermes"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          bordered: true
          onClicked: {
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
    Text { text: label; color: Qt.darker(root.bar.foreground, 1.35); font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    Text { text: value; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; elide: Text.ElideLeft; width: Math.min(implicitWidth, parent.width * 0.65) }
  }
}
