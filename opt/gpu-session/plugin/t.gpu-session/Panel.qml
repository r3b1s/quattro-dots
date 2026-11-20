import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "t.gpu-session"
  ipcTarget: root.moduleName === "preview" ? "" : "t.gpu-session"
  manageIpc: false

  property string configuredTarget: "rx580"
  property string activeGpu: "rx580"
  property bool pendingReboot: false
  property bool aquamarineIsolated: false

  property string rxPci: "04:00.0"
  property bool rxBootVga: true
  property var rxOutputs: []

  property string rtxPci: "2b:00.0"
  property bool rtxBootVga: false
  property var rtxOutputs: []
  property int vramUsedMiB: 0
  property int vramTotalMiB: 0
  property int tempC: 0
  property string powerW: "0"
  property int computeProcesses: 0
  property var desktopHolderNames: []
  property bool rtxIsolated: false

  property string lastError: ""
  property bool busy: false
  property int targetIndex: 0
  property bool cursorActive: false

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color accent: Commons.Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property real openPanelIndicatorWidth: !vertical && button ? button.labelWidth : 0

  readonly property string cliPath: (Quickshell.env("HOME") || "") + "/.local/bin/gpu-session"
  readonly property var targets: [
    { id: "rx580", icon: "󰍹", labelKey: "modeRx580" },
    { id: "rtx3070", icon: "󰢮", labelKey: "modeRtx3070" }
  ]

  readonly property int vramFreeMiB: Math.max(0, vramTotalMiB - vramUsedMiB)
  readonly property real vramFraction: vramTotalMiB > 0
    ? Math.max(0, Math.min(1, vramUsedMiB / vramTotalMiB))
    : 0
  readonly property bool needsAttention: pendingReboot || (activeGpu === "rx580" && !rtxIsolated)

  function sanitizeText(value) {
    return String(value === undefined || value === null ? "" : value)
      .replace(/[<>&]/g, "")
      .trim()
  }

  function formatOutputs(list) {
    if (!list || list.length === 0) return strings.t("none")
    var out = []
    for (var i = 0; i < list.length; i++) {
      var cleaned = sanitizeText(list[i])
      if (cleaned !== "") out.push(cleaned)
    }
    return out.length > 0 ? out.join(", ") : strings.t("none")
  }

  function formatHolders(list) {
    if (!list || list.length === 0) return ""
    var out = []
    for (var i = 0; i < list.length; i++) {
      var cleaned = sanitizeText(list[i])
      if (cleaned !== "" && out.indexOf(cleaned) === -1) out.push(cleaned)
    }
    return out.join(", ")
  }

  function gpuShortName(id) {
    if (id === "rtx3070") return "RTX 3070"
    if (id === "rx580") return "RX 580"
    return "?"
  }

  readonly property string barText: {
    var activeShort = activeGpu === "rtx3070" ? "3070" : (activeGpu === "rx580" ? "580" : "GPU")
    var targetShort = configuredTarget === "rtx3070" ? "3070" : "580"
    if (vertical) return "󰢮"
    if (configuredTarget !== activeGpu && activeGpu !== "unknown") {
      return "󰢮 " + activeShort + "→" + targetShort
    }
    return "󰢮 " + activeShort
  }

  readonly property string barTooltip: {
    if (configuredTarget !== activeGpu && activeGpu !== "unknown") {
      return strings.t("tooltipPending").arg(gpuShortName(configuredTarget))
    }
    var used = Commons.I18n.formatNumber(vramUsedMiB)
    var total = Commons.I18n.formatNumber(vramTotalMiB)
    if (activeGpu === "rtx3070") {
      return strings.t("tooltipRtx3070").arg(used).arg(total)
    }
    if (!rtxIsolated) {
      var holders = formatHolders(desktopHolderNames) || "Hyprland"
      return strings.t("tooltipRx580Attached").arg(holders)
    }
    return strings.t("tooltipRx580Isolated").arg(used).arg(total)
  }

  readonly property string heroTitle: {
    if (activeGpu === "rtx3070") return strings.t("titleRtx3070")
    if (activeGpu === "rx580") return strings.t("titleRx580")
    return strings.t("titleUnknown")
  }

  readonly property string heroSubtitle: {
    if (pendingReboot) return strings.t("subtitleRebootPending")
    if (activeGpu === "rtx3070") return strings.t("subtitleNvidiaDesktop")
    if (rtxIsolated) return strings.t("subtitleIsolated")
    return strings.t("subtitleAttached")
  }

  readonly property string pendingNoticeText: {
    if (!pendingReboot) return ""
    if (configuredTarget !== activeGpu) {
      return strings.t("rebootNoticeSwap").arg(gpuShortName(configuredTarget))
    }
    return strings.t("rebootNoticeIsolate")
  }

  function syncTargetIndex() {
    targetIndex = configuredTarget === "rtx3070" ? 1 : 0
  }

  function refresh() {
    if (root.moduleName === "preview") return
    if (!statusProc.running) statusProc.running = true
  }

  function selectTargetByDelta(delta) {
    var next = (targetIndex + delta) % targets.length
    if (next < 0) next += targets.length
    targetIndex = next
  }

  function activateSelectedTarget() {
    if (targetIndex < 0 || targetIndex >= targets.length) return
    setGpuTarget(targets[targetIndex].id)
  }

  function setGpuTarget(targetId) {
    if (root.moduleName === "preview" || !targetId || switchProc.running) return
    busy = true
    lastError = ""
    switchProc.command = [cliPath, targetId]
    switchProc.running = true
  }

  function toggleGpuTarget() {
    setGpuTarget(configuredTarget === "rx580" ? "rtx3070" : "rx580")
  }

  function applyStatusJson(raw) {
    var trimmed = String(raw || "").trim()
    if (trimmed === "") return
    try {
      var data = JSON.parse(trimmed)
      configuredTarget = sanitizeText(data.configuredTarget) || "rx580"
      activeGpu = sanitizeText(data.activeGpu) || "unknown"
      pendingReboot = data.pendingReboot === true
      aquamarineIsolated = data.aquamarineIsolated === true

      var rx = data.rx580 || {}
      rxPci = sanitizeText(rx.pci) || "04:00.0"
      rxBootVga = rx.bootVga === true
      rxOutputs = Array.isArray(rx.outputs) ? rx.outputs : []

      var rtx = data.rtx3070 || {}
      rtxPci = sanitizeText(rtx.pci) || "2b:00.0"
      rtxBootVga = rtx.bootVga === true
      rtxOutputs = Array.isArray(rtx.outputs) ? rtx.outputs : []
      vramUsedMiB = Math.max(0, Number(rtx.vramUsedMiB) || 0)
      vramTotalMiB = Math.max(0, Number(rtx.vramTotalMiB) || 0)
      tempC = Number(rtx.tempC) || 0
      powerW = sanitizeText(rtx.powerW) || "0"
      computeProcesses = Math.max(0, Number(rtx.computeProcesses) || 0)
      desktopHolderNames = Array.isArray(rtx.desktopHolderNames) ? rtx.desktopHolderNames : []
      rtxIsolated = rtx.isolated === true

      lastError = ""
      if (!cursorActive) syncTargetIndex()
    } catch (e) {
      lastError = strings.t("errorRunningCli").arg(sanitizeText(e))
    }
  }

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  ShellIpc {
    target: root.moduleName === "preview" ? "" : "t.gpu-session"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function switchRx580(): string { root.setGpuTarget("rx580"); return "ok" }
    function switchRtx3070(): string { root.setGpuTarget("rtx3070"); return "ok" }
  }

  Process {
    id: statusProc
    command: [root.cliPath, "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatusJson(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var msg = root.sanitizeText(text)
        if (msg !== "") root.lastError = msg
      }
    }
  }

  Process {
    id: switchProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var msg = root.sanitizeText(text)
        if (msg !== "") root.lastError = msg
      }
    }
    onExited: {
      root.busy = false
      root.refresh()
    }
  }

  Timer {
    interval: 5000
    running: root.opened && root.moduleName !== "preview"
    repeat: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: {
    if (root.moduleName !== "preview") root.refresh()
  }

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      syncTargetIndex()
      refresh()
      Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    active: root.needsAttention
    tooltipText: root.barTooltip
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.toggleGpuTarget()
      else if (mouseButton === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      implicitHeight: column.implicitHeight

      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) {
          root.cursorActive = true
          return
        }
        if (dx !== 0) root.selectTargetByDelta(dx)
        else if (dy !== 0) root.selectTargetByDelta(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateSelectedTarget()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "1" || t === "a" || t === "A") {
          root.cursorActive = true
          root.targetIndex = 0
          root.setGpuTarget("rx580")
        } else if (t === "2" || t === "n" || t === "N") {
          root.cursorActive = true
          root.targetIndex = 1
          root.setGpuTarget("rtx3070")
        } else if (t === "r" || t === "R") {
          root.refresh()
        }
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: root.heroTitle
          meta: root.heroSubtitle
          detail: root.vramTotalMiB > 0
            ? strings.t("vramFreePill").arg(Commons.I18n.formatNumber(root.vramFreeMiB))
            : ""
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: root.activeGpu === "rtx3070" ? "󰢮" : "󰍹"
              color: root.needsAttention ? root.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        // RTX 3070 VRAM utilization bar
        Item {
          visible: root.vramTotalMiB > 0
          width: parent.width
          implicitHeight: Style.space(8)

          Rectangle {
            id: vramTrack
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
          }

          Rectangle {
            anchors.left: vramTrack.left
            anchors.verticalCenter: vramTrack.verticalCenter
            height: vramTrack.height
            radius: vramTrack.radius
            color: root.activeGpu === "rx580" && !root.rtxIsolated ? root.urgent : root.foreground
            width: Math.max(vramTrack.height, vramTrack.width * root.vramFraction)

            Behavior on width {
              NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic }
            }
            Behavior on color {
              ColorAnimation { duration: Style.duration(180) }
            }
          }
        }

        BorderSurface {
          visible: root.pendingNoticeText !== "" || root.lastError !== ""
          width: parent.width
          implicitHeight: noticeText.implicitHeight + Style.space(16)
          radius: Style.cornerRadius
          color: Style.hoverFillFor(root.foreground, root.urgent)
          borderSpec: Border.controlSpec("normal", root.urgent, root.urgent)

          Text {
            id: noticeText
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(8)
            text: root.lastError !== "" ? root.lastError : root.pendingNoticeText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }

        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: strings.t("sectionTarget")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            id: targetRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: root.targets.length > 0
              ? (width - spacing * (root.targets.length - 1)) / root.targets.length
              : 0

            Repeater {
              model: root.targets

              Button {
                required property var modelData
                required property int index

                width: targetRow.cellWidth
                iconText: modelData.icon
                iconSize: Style.font.title
                text: strings.t(modelData.labelKey)
                fontSize: Style.font.bodySmall
                foreground: root.foreground
                fontFamily: root.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                selected: root.configuredTarget === modelData.id
                hasCursor: root.cursorActive && root.targetIndex === index
                onClicked: root.setGpuTarget(modelData.id)
                onHovered: function(h) {
                  if (h) {
                    root.cursorActive = true
                    root.targetIndex = index
                  }
                }
              }
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.spacing.labelGap

          PanelSectionHeader {
            text: strings.t("sectionRtx3070")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          InfoPair {
            label: strings.t("vramUsage")
            value: strings.t("vramFormat")
              .arg(Commons.I18n.formatNumber(root.vramUsedMiB))
              .arg(Commons.I18n.formatNumber(root.vramTotalMiB))
          }

          InfoPair {
            label: strings.t("isolationStatus")
            value: root.activeGpu === "rtx3070"
              ? strings.t("desktopActive")
              : (root.rtxIsolated
                ? strings.t("isolatedClean")
                : strings.t("attachedProcesses").arg(root.formatHolders(root.desktopHolderNames) || "Hyprland"))
            valueColor: root.activeGpu === "rx580" && !root.rtxIsolated ? root.urgent : root.foreground
          }

          InfoPair {
            label: strings.t("computeApps")
            value: strings.t("computeCount").arg(Commons.I18n.formatNumber(root.computeProcesses))
          }

          InfoPair {
            label: strings.t("tempPower")
            value: strings.t("tempPowerFormat")
              .arg(Commons.I18n.formatNumber(root.tempC))
              .arg(root.powerW)
          }
        }

        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.spacing.labelGap

          PanelSectionHeader {
            text: strings.t("sectionRx580")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          InfoPair {
            label: strings.t("activeOutputs")
            value: root.formatOutputs(root.rxOutputs)
          }

          InfoPair {
            label: strings.t("bootVga")
            value: root.rxPci + " · " + (root.rxBootVga ? strings.t("yes") : strings.t("no"))
          }
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: strings.t("keyHints")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""
    property color valueColor: root.foreground

    readonly property real _maxValueWidth: Math.max(0, width - pairLabel.implicitWidth - spacing * 2)

    width: parent.width
    spacing: Style.space(8)

    Text {
      id: pairLabel
      textFormat: Text.PlainText
      text: label
      color: root.foreground
      opacity: 0.65
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Item {
      width: Math.max(0, parent.width - pairLabel.implicitWidth - pairValue.width - parent.spacing * 2)
      height: 1
    }

    Text {
      id: pairValue
      textFormat: Text.PlainText
      text: value
      width: Math.min(implicitWidth, parent._maxValueWidth)
      horizontalAlignment: Text.AlignRight
      color: valueColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      maximumLineCount: 1
    }
  }
}
