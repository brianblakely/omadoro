import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "b.omadoro"

  readonly property var timerService: bar && bar.shell
    ? bar.shell.serviceFor(moduleName)
    : null

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false
  readonly property real openPanelIndicatorWidth: Style.bar.iconCanvas
  readonly property real openPanelIndicatorHeight: Style.bar.iconCanvas

  function syncService() {
    if (timerService && typeof timerService.configure === "function")
      timerService.configure(settings)
    injectPanel()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("timerService" in target) target.timerService = root.timerService
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: Qt.callLater(syncService)
  onSettingsChanged: Qt.callLater(syncService)
  onTimerServiceChanged: Qt.callLater(syncService)
  Component.onCompleted: Qt.callLater(syncService)

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.syncService)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.timerService
      ? (root.timerService.awaitingAck
          ? root.timerService.phaseLabel + " finished · click to continue"
          : root.timerService.phaseLabel + " · " + root.timerService.remainingText)
      : "Omadoro"
    iconComponent: Component {
      CircularProgress {
        progress: root.timerService ? root.timerService.progress : 0
        trackColor: Color.muted
        fillColor: root.timerService && root.timerService.awaitingAck ? Color.urgent : Color.accent
        strokeWidth: Math.max(2, Style.spaceReal(2))
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode !== Qt.LeftButton) return
      if (root.timerService && root.timerService.awaitingAck) root.timerService.acknowledge()
      else root.toggle()
    }
  }
}
