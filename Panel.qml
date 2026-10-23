import QtQuick
import qs.Commons
import qs.Ui
import "TimerModel.js" as TimerModel

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
  property bool configOpen: false
  property int selectedSetting: 0

  readonly property var timerConfig: timerService && timerService.config
    ? timerService.config
    : ({ workMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15, workPhasesPerLongBreak: 4 })
  readonly property var durationRows: [
    { key: "workMinutes", label: "Work" },
    { key: "shortBreakMinutes", label: "Short break" },
    { key: "longBreakMinutes", label: "Long break" }
  ]

  function open() {
    selectedAction = 0
    cursorActive = true
    // The panel always opens on the timer face; leaving the editor open
    // across a close would greet the next summon with sliders instead of
    // the clock.
    configOpen = false
    selectedSetting = 0
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
    if (!timerService || !timerService.initialized) {
      selectedAction = 0
      return
    }
    // Stop leaves only Play and the settings gear live, so step over the
    // buttons that are faded out rather than parking the cursor on one.
    var next = selectedAction
    for (var i = 0; i < 5; i++) {
      next = ((next + delta) % 5 + 5) % 5
      if (actionEnabled(next)) break
    }
    selectedAction = next
  }

  function actionEnabled(index) {
    if (!timerService || !timerService.initialized) return false
    if (index === 0 || index === 4) return true
    return !timerService.stopped
  }

  function activateSelected() {
    if (!timerService || !timerService.initialized) return
    if (selectedAction === 0) timerService.playOrStop()
    else if (selectedAction === 1 && !timerService.stopped) timerService.togglePause()
    else if (selectedAction === 2 && !timerService.stopped) timerService.addFiveMinutes()
    else if (selectedAction === 3 && !timerService.stopped) timerService.skip()
    else if (selectedAction === 4) openSettings()
  }

  function openSettings() {
    configOpen = true
    selectedSetting = 0
    cursorActive = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function closeSettings() {
    configOpen = false
    selectedAction = 4
    cursorActive = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function selectSetting(delta) {
    cursorActive = true
    selectedSetting = ((selectedSetting + delta) % durationRows.length + durationRows.length) % durationRows.length
  }

  function focusSettingField(index) {
    var row = settingsRepeater.itemAt(index)
    if (row && typeof row.focusField === "function") row.focusField()
  }

  function adjustSetting(direction) {
    var row = durationRows[selectedSetting]
    if (!row) return
    var current = Number(timerConfig[row.key])
    if (!isFinite(current)) current = TimerModel.configBounds(row.key).minimum
    applySetting(row.key, TimerModel.clampDuration(row.key, current + direction))
  }

  function applySetting(key, value) {
    if (hostWidget && typeof hostWidget.applySetting === "function")
      hostWidget.applySetting(key, value)
    else if (timerService && typeof timerService.setConfigValue === "function")
      timerService.setConfigValue(key, value)
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
      // A focused duration field owns the keyboard: digits and Left/Right
      // have to reach the editor instead of moving the panel cursor.
      blocked: !activeFocus

      onMoveRequested: function(dx, dy) {
        if (root.configOpen) {
          if (dy !== 0) root.selectSetting(dy)
          else if (dx !== 0) root.adjustSetting(dx)
        } else if (dx !== 0) root.selectAction(dx)
        else if (dy !== 0) root.selectAction(dy)
      }
      onActivateRequested: root.configOpen ? root.focusSettingField(root.selectedSetting) : root.activateSelected()
      onCloseRequested: root.configOpen ? root.closeSettings() : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(18)

        readonly property real faceHeight: Math.max(1, panel.contentHeight - panel.verticalContentInset
                                                   - spacing - actions.implicitHeight)

        Item {
          id: timerFace
          visible: !root.configOpen
          width: parent.width
          height: content.faceHeight

          CircularProgress {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height)
            height: width
            progress: root.timerService ? root.timerService.progress : 0
            trackColor: Color.muted
            fillColor: root.activeColor
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
              text: root.timerService ? root.timerService.phaseLabel : "Work"
              color: root.activeColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }
          }
        }

        Item {
          id: settingsFace
          visible: root.configOpen
          width: parent.width
          height: content.faceHeight

          Column {
            id: settingsColumn
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            spacing: Style.space(10)

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: "Timer settings"
              color: Color.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Repeater {
              id: settingsRepeater
              model: root.durationRows

              delegate: CursorSurface {
                id: settingRow
                required property int index
                required property var modelData

                width: settingsColumn.width
                height: rowContent.implicitHeight + Style.space(10)
                hasCursor: root.cursorActive && root.selectedSetting === index
                foreground: root.foreground
                outline: true

                function focusField() {
                  rowField.forceActiveFocus()
                  rowField.selectAll()
                }

                HoverHandler {
                  onHoveredChanged: {
                    if (!hovered) return
                    root.cursorActive = true
                    root.selectedSetting = settingRow.index
                  }
                }

                // Parse what was typed, clamp it to the configured range, and
                // write it back through the same path the slider uses, so a
                // hand-typed "0" or "999" lands where the CLI would put it.
                function commitField() {
                  var raw = String(rowField.text).trim()
                  if (raw === "" || !isFinite(Number(raw))) {
                    rowField.text = String(Math.round(rowSlider.liveValue))
                    return
                  }
                  var next = TimerModel.clampDuration(settingRow.modelData.key, Number(raw))
                  rowField.text = String(next)
                  root.applySetting(settingRow.modelData.key, next)
                }

                Column {
                  id: rowContent
                  anchors.fill: parent
                  anchors.margins: Style.space(5)
                  spacing: Style.space(2)

                  Item {
                    width: parent.width
                    height: Math.max(rowLabel.implicitHeight, rowField.implicitHeight)

                    Text {
                      id: rowLabel
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      text: settingRow.modelData.label
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }

                    Row {
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(5)

                      TextField {
                        id: rowField
                        width: Style.space(54)
                        height: Style.space(22)
                        horizontalAlignment: TextInput.AlignHCenter
                        foreground: root.foreground
                        accent: root.activeColor
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        horizontalPadding: Style.space(4)
                        verticalPadding: 0
                        inputMethodHints: Qt.ImhDigitsOnly
                        validator: IntValidator {
                          bottom: TimerModel.configBounds(settingRow.modelData.key).minimum
                          top: TimerModel.configBounds(settingRow.modelData.key).maximum
                        }

                        Component.onCompleted: text = String(Math.round(rowSlider.liveValue))

                        onAccepted: {
                          settingRow.commitField()
                          Qt.callLater(function() { keyCatcher.forceActiveFocus() })
                        }
                        onActiveFocusChanged: {
                          if (activeFocus) selectAll()
                          else settingRow.commitField()
                        }
                        Keys.onEscapePressed: {
                          rowField.text = String(Math.round(rowSlider.liveValue))
                          Qt.callLater(function() { keyCatcher.forceActiveFocus() })
                        }
                      }

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "min"
                        color: Color.muted
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                      }
                    }
                  }

                  PanelSlider {
                    id: rowSlider
                    bar: root.bar
                    width: parent.width
                    minimum: TimerModel.configBounds(settingRow.modelData.key).minimum
                    maximum: TimerModel.configBounds(settingRow.modelData.key).maximum
                    integer: true
                    step: 1
                    value: Number(root.timerConfig[settingRow.modelData.key]
                                  || TimerModel.configBounds(settingRow.modelData.key).minimum)
                    onReleased: function(value) {
                      root.applySetting(settingRow.modelData.key, Math.round(value))
                    }
                    // Keep the field in step with the thumb, but never
                    // overwrite a number the user is halfway through typing.
                    onLiveValueChanged: if (!rowField.activeFocus)
                      rowField.text = String(Math.round(liveValue))
                    onValueChanged: if (!rowField.activeFocus)
                      rowField.text = String(Math.round(value))
                  }
                }
              }
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
            visible: !root.configOpen
            implicitWidth: actions.buttonSize
            implicitHeight: actions.buttonSize
            width: actions.buttonSize
            height: actions.buttonSize
            iconText: root.timerService && root.timerService.stopped ? "" : ""
            tooltipText: root.timerService && root.timerService.stopped
              ? "Start a new Pomodoro"
              : "Stop Pomodoro"
            foreground: root.foreground
            accent: root.activeColor
            iconSize: Style.font.iconLarge
            horizontalPadding: 0
            verticalPadding: 0
            enabled: !!root.timerService && root.timerService.initialized
            opacity: enabled ? 1 : 0.35
            hasCursor: root.cursorActive && root.selectedAction === 0
            onHovered: function(value) { root.actionHovered(0, value) }
            onClicked: if (root.timerService) root.timerService.playOrStop()
          }

          Button {
            id: pauseButton
            visible: !root.configOpen
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
            enabled: !!root.timerService && root.timerService.initialized && !root.timerService.stopped
            opacity: enabled ? 1 : 0.35
            hasCursor: root.cursorActive && root.selectedAction === 1
            onHovered: function(value) { root.actionHovered(1, value) }
            onClicked: if (root.timerService) root.timerService.togglePause()
          }

          Button {
            id: addButton
            visible: !root.configOpen
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
            enabled: !!root.timerService && root.timerService.initialized && !root.timerService.stopped
            opacity: enabled ? 1 : 0.35
            hasCursor: root.cursorActive && root.selectedAction === 2
            onHovered: function(value) { root.actionHovered(2, value) }
            onClicked: if (root.timerService) root.timerService.addFiveMinutes()
          }

          Button {
            id: skipButton
            visible: !root.configOpen
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
            enabled: !!root.timerService && root.timerService.initialized && !root.timerService.stopped
            opacity: enabled ? 1 : 0.35
            hasCursor: root.cursorActive && root.selectedAction === 3
            onHovered: function(value) { root.actionHovered(3, value) }
            onClicked: if (root.timerService) root.timerService.skip()
          }

          Button {
            id: settingsButton
            visible: !root.configOpen
            implicitWidth: actions.buttonSize
            implicitHeight: actions.buttonSize
            width: actions.buttonSize
            height: actions.buttonSize
            iconText: "\uf013"
            tooltipText: "Work and break durations"
            foreground: root.foreground
            accent: root.activeColor
            iconSize: Style.font.iconLarge
            horizontalPadding: 0
            verticalPadding: 0
            enabled: !!root.timerService && root.timerService.initialized
            opacity: enabled ? 1 : 0.35
            hasCursor: root.cursorActive && root.selectedAction === 4
            onHovered: function(value) { root.actionHovered(4, value) }
            onClicked: root.openSettings()
          }

          Button {
            id: doneButton
            visible: root.configOpen
            implicitHeight: actions.buttonSize
            text: "Done"
            tooltipText: "Back to the timer"
            foreground: root.foreground
            accent: root.activeColor
            bordered: true
            fontSize: Style.font.body
            horizontalPadding: Style.space(20)
            verticalPadding: 0
            onClicked: root.closeSettings()
          }
        }
      }
    }
  }
}
