import QtQuick
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "b.omadoro"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var timerService: null
  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: Color.popups.text
  readonly property color activeColor: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  property int selectedAction: 0
  property bool cursorActive: true

  function open() {
    selectedAction = 0
    cursorActive = true
    controller.show()
  }

  function close() {
    controller.hide()
  }

  function toggle() {
    if (opened) close()
    else open()
  }

  function selectAction(delta) {
    cursorActive = true
    if (!timerService || timerService.stopped || timerService.awaitingAck) {
      selectedAction = 0
      return
    }
    selectedAction = ((selectedAction + delta) % 4 + 4) % 4
  }

  function activateSelected() {
    if (!timerService || !timerService.initialized) return
    if (timerService.awaitingAck) { timerService.acknowledge(); return }
    if (selectedAction === 0) timerService.playOrStop()
    else if (selectedAction === 1 && !timerService.stopped) timerService.togglePause()
    else if (selectedAction === 2 && !timerService.stopped) timerService.addFiveMinutes()
    else if (selectedAction === 3 && !timerService.stopped) timerService.skip()
  }

  function actionHovered(index, hovered) {
    if (!hovered) return
    cursorActive = true
    selectedAction = index
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(330))
    contentHeight: contentWidth

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.selectAction(dx)
        else if (dy !== 0) root.selectAction(dy)
      }
      onActivateRequested: root.activateSelected()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(18)

        Item {
          id: timerFace
          width: parent.width
          height: Math.max(1, panel.contentHeight - panel.verticalContentInset
                           - content.spacing - actions.implicitHeight)

          CircularProgress {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height)
            height: width
            progress: root.timerService ? root.timerService.progress : 0
            trackColor: Color.muted
            fillColor: root.timerService && root.timerService.awaitingAck ? Color.urgent : root.activeColor
            strokeWidth: Math.max(5, Style.spaceReal(7))
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(5)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.timerService ? root.timerService.remainingText : "25:00"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Math.round(Style.font.displayLarge * 1.7)
              font.bold: true
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.timerService
                ? (root.timerService.awaitingAck
                    ? root.timerService.phaseLabel + " done — dismiss to continue"
                    : root.timerService.phaseLabel)
                : "Work"
              color: root.timerService && root.timerService.awaitingAck ? Color.urgent : root.activeColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }
          }
        }

        Row {
          id: actions
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(10)
          readonly property real buttonSize: Style.space(42)

          Button {
            id: stopButton
            implicitWidth: actions.buttonSize
            implicitHeight: actions.buttonSize
            width: actions.buttonSize
            height: actions.buttonSize
            iconText: root.timerService && root.timerService.awaitingAck ? ""
              : (root.timerService && root.timerService.stopped ? "" : "")
            tooltipText: root.timerService && root.timerService.awaitingAck
              ? "Dismiss and start next phase"
              : (root.timerService && root.timerService.stopped
                  ? "Start a new Pomodoro"
                  : "Stop Pomodoro")
            foreground: root.timerService && root.timerService.awaitingAck ? Color.urgent : root.foreground
            accent: root.activeColor
            iconSize: Style.font.iconLarge
            horizontalPadding: 0
            verticalPadding: 0
            enabled: !!root.timerService && root.timerService.initialized
            opacity: enabled ? 1 : 0.35
            hasCursor: root.cursorActive && root.selectedAction === 0
            onHovered: function(value) { root.actionHovered(0, value) }
            onClicked: {
              if (!root.timerService) return
              if (root.timerService.awaitingAck) root.timerService.acknowledge()
              else root.timerService.playOrStop()
            }
          }

          Button {
            id: pauseButton
            implicitWidth: actions.buttonSize
            implicitHeight: actions.buttonSize
            width: actions.buttonSize
            height: actions.buttonSize
            iconText: root.timerService && root.timerService.paused ? "" : ""
            tooltipText: root.timerService && root.timerService.paused
              ? "Resume current phase"
              : "Pause current phase"
            foreground: root.foreground
            accent: root.activeColor
            iconSize: Style.font.iconLarge
            horizontalPadding: 0
            verticalPadding: 0
            enabled: !!root.timerService && root.timerService.initialized && !root.timerService.stopped && !root.timerService.awaitingAck
            opacity: enabled ? 1 : 0.35
            hasCursor: root.cursorActive && root.selectedAction === 1
            onHovered: function(value) { root.actionHovered(1, value) }
            onClicked: if (root.timerService) root.timerService.togglePause()
          }

          Button {
            id: addButton
            implicitWidth: actions.buttonSize
            implicitHeight: actions.buttonSize
            width: actions.buttonSize
            height: actions.buttonSize
            iconText: "󰐕"
            tooltipText: "Add 5 minutes"
            foreground: root.foreground
            accent: root.activeColor
            iconSize: Style.font.iconLarge
            horizontalPadding: 0
            verticalPadding: 0
            enabled: !!root.timerService && root.timerService.initialized && !root.timerService.stopped && !root.timerService.awaitingAck
            opacity: enabled ? 1 : 0.35
            hasCursor: root.cursorActive && root.selectedAction === 2
            onHovered: function(value) { root.actionHovered(2, value) }
            onClicked: if (root.timerService) root.timerService.addFiveMinutes()
          }

          Button {
            id: skipButton
            implicitWidth: actions.buttonSize
            implicitHeight: actions.buttonSize
            width: actions.buttonSize
            height: actions.buttonSize
            iconText: ""
            tooltipText: "Skip to next phase"
            foreground: root.foreground
            accent: root.activeColor
            iconSize: Style.font.iconLarge
            horizontalPadding: 0
            verticalPadding: 0
            enabled: !!root.timerService && root.timerService.initialized && !root.timerService.stopped && !root.timerService.awaitingAck
            opacity: enabled ? 1 : 0.35
            hasCursor: root.cursorActive && root.selectedAction === 3
            onHovered: function(value) { root.actionHovered(3, value) }
            onClicked: if (root.timerService) root.timerService.skip()
          }
        }
      }
    }
  }
}
