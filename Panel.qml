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

  property string page: "timer"
  readonly property bool settingsOpen: page === "settings"
  readonly property bool alerting: timerService ? timerService.alerting === true : false
  readonly property color foreground: alerting && !settingsOpen ? Color.popups.background : Color.popups.text
  readonly property color activeColor: alerting && !settingsOpen ? Color.popups.text : Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  property int selectedAction: 0
  property bool cursorActive: true

  readonly property bool soundEnabled: timerService ? timerService.soundEnabled : true
  readonly property string soundName: timerService ? timerService.soundName : "complete"
  readonly property string flashScreenMode: timerService ? timerService.flashScreenMode : "off"
  readonly property bool flashBarEnabled: timerService ? timerService.flashBarEnabled : true
  readonly property bool flashBorderEnabled: timerService ? timerService.flashBorderEnabled : true
  readonly property int flashCount: timerService ? timerService.flashCount : 3
  readonly property string flashSpeed: timerService ? timerService.flashSpeed : "normal"
  readonly property var soundOptions: TimerModel.soundOptions()
  readonly property var flashSpeedOptions: TimerModel.flashSpeedOptions()
  readonly property var screenModeOptions: TimerModel.screenModeOptions()
  readonly property int timerActionCount: 5
  readonly property int settingsActionCount: 8
  readonly property bool settingsPopupOpen: soundDropdown.popupOpen
    || speedDropdown.popupOpen || screenModeDropdown.popupOpen

  function open() {
    page = "timer"
    selectedAction = 0
    cursorActive = true
    controller.show()
  }

  function close() {
    page = "timer"
    controller.hide()
  }

  function toggle() {
    if (opened) close()
    else open()
  }

  function openSettings() {
    page = "settings"
    selectedAction = 0
    cursorActive = true
  }

  function closeSettings() {
    page = "timer"
    selectedAction = 4
    cursorActive = true
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    var base = timerService && timerService.config ? timerService.config : {}
    for (var key in base) entry[key] = base[key]
    for (var existing in root.settings)
      if (existing !== "id") entry[existing] = root.settings[existing]
    for (var next in values) entry[next] = values[next]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget)
      root.hostWidget.settings = entry
    if (root.timerService && typeof root.timerService.configure === "function")
      root.timerService.configure(entry)
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function selectAction(delta) {
    cursorActive = true
    var count = settingsOpen ? settingsActionCount : timerActionCount
    selectedAction = ((selectedAction + delta) % count + count) % count
  }

  function nudgeSetting(delta) {
    cursorActive = true
    if (selectedAction === 1)
      persistSettings({ soundName: TimerModel.cycleSoundName(soundName, delta) })
    else if (selectedAction === 5)
      persistSettings({ flashCount: Math.max(1, Math.min(8, flashCount + delta)) })
    else if (selectedAction === 6)
      persistSettings({ flashSpeed: TimerModel.cycleFlashSpeed(flashSpeed, delta) })
    else if (selectedAction === 0)
      persistSettings({ soundEnabled: !soundEnabled })
    else if (selectedAction === 2)
      persistSettings({ flashScreenMode: TimerModel.cycleScreenMode(flashScreenMode, delta) })
    else if (selectedAction === 3)
      persistSettings({ flashBarEnabled: !flashBarEnabled })
    else if (selectedAction === 4)
      persistSettings({ flashBorderEnabled: !flashBorderEnabled })
  }

  function activateSelected() {
    if (settingsOpen) {
      if (selectedAction === 0) persistSettings({ soundEnabled: !soundEnabled })
      else if (selectedAction === 1) soundDropdown.toggle()
      else if (selectedAction === 2) screenModeDropdown.toggle()
      else if (selectedAction === 3) persistSettings({ flashBarEnabled: !flashBarEnabled })
      else if (selectedAction === 4) persistSettings({ flashBorderEnabled: !flashBorderEnabled })
      else if (selectedAction === 6) speedDropdown.toggle()
      else if (selectedAction === 7 && timerService) timerService.previewAlert()
      return
    }
    if (!timerService || !timerService.initialized) return
    if (selectedAction === 0) timerService.playOrStop()
    else if (selectedAction === 1 && !timerService.stopped) timerService.togglePause()
    else if (selectedAction === 2 && !timerService.stopped) timerService.addFiveMinutes()
    else if (selectedAction === 3 && !timerService.stopped) timerService.skip()
    else if (selectedAction === 4) openSettings()
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
    contentHeight: root.settingsOpen
      ? panel.fittedContentWidth(Style.space(570))
      : contentWidth

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (root.settingsPopupOpen) return
        if (root.settingsOpen && dx !== 0 && dy === 0) root.nudgeSetting(dx)
        else root.selectAction(dx !== 0 ? dx : dy)
      }
      onActivateRequested: root.activateSelected()
      onCloseRequested: {
        if (root.settingsPopupOpen) return
        if (root.settingsOpen) root.closeSettings()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: timerPage
        visible: !root.settingsOpen
        width: parent.width
        spacing: Style.space(18)

        Item {
          id: timerFace
          width: parent.width
          height: Math.max(1, panel.contentHeight - panel.verticalContentInset
                           - timerPage.spacing - timerActions.implicitHeight)

          Rectangle {
            anchors.fill: parent
            color: root.alerting ? Color.popups.text : "transparent"
          }

          CircularProgress {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height)
            height: width
            progress: root.timerService ? root.timerService.progress : 0
            trackColor: root.alerting ? Color.popups.background : Color.muted
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

          Button {
            anchors.right: parent.right
            anchors.top: parent.top
            implicitWidth: Style.space(38)
            implicitHeight: Style.space(38)
            width: implicitWidth
            height: implicitHeight
            iconText: "󰒓"
            tooltipText: "Alert settings"
            foreground: root.foreground
            accent: root.activeColor
            iconSize: Style.font.iconLarge
            horizontalPadding: 0
            verticalPadding: 0
            enabled: true
            z: 2
            hasCursor: root.cursorActive && root.selectedAction === 4
            onHovered: function(value) { root.actionHovered(4, value) }
            onClicked: root.openSettings()
          }
        }

        Row {
          id: timerActions
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(8)
          readonly property real buttonSize: Style.space(42)

          Button {
            implicitWidth: timerActions.buttonSize
            implicitHeight: timerActions.buttonSize
            width: timerActions.buttonSize
            height: timerActions.buttonSize
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
            implicitWidth: timerActions.buttonSize
            implicitHeight: timerActions.buttonSize
            width: timerActions.buttonSize
            height: timerActions.buttonSize
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
            implicitWidth: timerActions.buttonSize
            implicitHeight: timerActions.buttonSize
            width: timerActions.buttonSize
            height: timerActions.buttonSize
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
            implicitWidth: timerActions.buttonSize
            implicitHeight: timerActions.buttonSize
            width: timerActions.buttonSize
            height: timerActions.buttonSize
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
        }
      }

      Column {
        id: settingsPage
        visible: root.settingsOpen
        width: parent.width
        spacing: Style.space(10)

        Row {
          width: parent.width
          spacing: Style.space(10)

          Button {
            implicitWidth: Style.space(42)
            implicitHeight: Style.space(42)
            width: implicitWidth
            height: implicitHeight
            iconText: ""
            tooltipText: "Back to timer"
            foreground: Color.popups.text
            accent: Color.accent
            iconSize: Style.font.iconLarge
            horizontalPadding: 0
            verticalPadding: 0
            onClicked: root.closeSettings()
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Alerts"
            color: Color.popups.text
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }
        }

        Toggle {
          width: parent.width
          label: "Sound"
          description: "Play a sound when a phase starts"
          checked: root.soundEnabled
          foreground: Color.popups.text
          accent: Color.accent
          fontFamily: root.fontFamily
          hasCursor: root.cursorActive && root.selectedAction === 0
          onHovered: function(value) { root.actionHovered(0, value) }
          onClicked: root.persistSettings({ soundEnabled: !root.soundEnabled })
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Dropdown {
            id: soundDropdown
            width: parent.width - previewSoundButton.width - parent.spacing
            label: "Sound"
            value: root.soundName
            options: root.soundOptions
            foreground: Color.popups.text
            accent: Color.accent
            fontFamily: root.fontFamily
            hasCursor: root.cursorActive && root.selectedAction === 1
            onHovered: function(value) { root.actionHovered(1, value) }
            onChanged: function(value) {
              root.persistSettings({ soundName: value })
              if (root.timerService) root.timerService.previewSound()
            }
          }

          Button {
            id: previewSoundButton
            anchors.bottom: parent.bottom
            implicitWidth: Style.space(42)
            implicitHeight: Style.space(42)
            width: implicitWidth
            height: implicitHeight
            iconText: ""
            tooltipText: "Preview sound"
            foreground: Color.popups.text
            accent: Color.accent
            iconSize: Style.font.iconLarge
            horizontalPadding: 0
            verticalPadding: 0
            onClicked: if (root.timerService) root.timerService.previewSound()
          }
        }

        Dropdown {
          id: screenModeDropdown
          width: parent.width
          label: "Screen invert"
          value: root.flashScreenMode
          options: root.screenModeOptions
          foreground: Color.popups.text
          accent: Color.accent
          fontFamily: root.fontFamily
          hasCursor: root.cursorActive && root.selectedAction === 2
          onHovered: function(value) { root.actionHovered(2, value) }
          onChanged: function(value) { root.persistSettings({ flashScreenMode: value }) }
        }

        Toggle {
          width: parent.width
          label: "Flash bar"
          description: "Invert the status bar when a phase starts"
          checked: root.flashBarEnabled
          foreground: Color.popups.text
          accent: Color.accent
          fontFamily: root.fontFamily
          hasCursor: root.cursorActive && root.selectedAction === 3
          onHovered: function(value) { root.actionHovered(3, value) }
          onClicked: root.persistSettings({ flashBarEnabled: !root.flashBarEnabled })
        }

        Toggle {
          width: parent.width
          label: "Flash border"
          description: "Draw a 5px frame around the monitor"
          checked: root.flashBorderEnabled
          foreground: Color.popups.text
          accent: Color.accent
          fontFamily: root.fontFamily
          hasCursor: root.cursorActive && root.selectedAction === 4
          onHovered: function(value) { root.actionHovered(4, value) }
          onClicked: root.persistSettings({ flashBorderEnabled: !root.flashBorderEnabled })
        }

        NumberField {
          width: parent.width
          label: "Flashes"
          value: root.flashCount
          from: 1
          to: 8
          foreground: Color.popups.text
          accent: Color.accent
          fontFamily: root.fontFamily
          hasCursor: root.cursorActive && root.selectedAction === 5
          onHovered: function(on) { if (on) root.actionHovered(5, true) }
          onModified: function(value) { root.persistSettings({ flashCount: value }) }
        }

        Dropdown {
          id: speedDropdown
          width: parent.width
          label: "Flash speed"
          value: root.flashSpeed
          options: root.flashSpeedOptions
          foreground: Color.popups.text
          accent: Color.accent
          fontFamily: root.fontFamily
          hasCursor: root.cursorActive && root.selectedAction === 6
          onHovered: function(value) { root.actionHovered(6, value) }
          onChanged: function(value) { root.persistSettings({ flashSpeed: value }) }
        }

        Button {
          width: parent.width
          text: "Preview alert"
          tooltipText: "Play the current sound and flash settings"
          foreground: Color.popups.text
          accent: Color.accent
          hasCursor: root.cursorActive && root.selectedAction === 7
          onHovered: function(value) { root.actionHovered(7, value) }
          onClicked: if (root.timerService) root.timerService.previewAlert()
        }
      }
    }
  }
}
