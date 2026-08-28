import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "TimerModel.js" as TimerModel

Item {
  id: root

  property var shell: null
  property var manifest: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || ""

  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME")
    || ((Quickshell.env("HOME") || "") + "/.local/state")
  readonly property string stateDir: stateHome + "/omarchy"
  readonly property string statePath: stateDir + "/omadoro.json"
  readonly property string notificationExecutable: omarchyPath !== ""
    ? omarchyPath + "/bin/omarchy-notification-send"
    : "omarchy-notification-send"
  readonly property string alertSoundFile: TimerModel.soundFile(config.soundName)
  readonly property int flashIntervalMs: TimerModel.flashSpeedMs(config.flashSpeed)

  property var config: TimerModel.normalizeConfig({})
  property var timerState: TimerModel.stoppedState(config, Date.now())
  property double nowMs: Date.now()
  property double lastTickMs: 0
  property bool configReady: false
  property bool stateFileLoaded: false
  property bool initialized: false
  property bool stateDirReady: false
  property bool savePending: false
  property string loadedStateText: ""
  property bool alerting: false
  property bool flashActive: false
  property int flashTicksLeft: 0

  readonly property string status: timerState.status
  readonly property string phase: timerState.phase
  readonly property string phaseLabel: TimerModel.phaseLabel(phase)
  readonly property int remainingSeconds: TimerModel.remainingSeconds(timerState, nowMs)
  readonly property string remainingText: TimerModel.formatRemaining(remainingSeconds)
  readonly property real progress: TimerModel.elapsedProgress(timerState, nowMs)
  readonly property bool stopped: status === TimerModel.StatusStopped
  readonly property bool running: status === TimerModel.StatusRunning
  readonly property bool paused: status === TimerModel.StatusPaused
  readonly property bool soundEnabled: config.soundEnabled !== false
  readonly property string soundName: config.soundName || "complete"
  readonly property string flashScreenMode: config.flashScreenMode || "off"
  readonly property bool flashBackgroundEnabled: flashScreenMode === "background"
  readonly property bool flashEverythingEnabled: flashScreenMode === "all"
  readonly property bool flashBarEnabled: config.flashBarEnabled !== false
  readonly property bool flashBorderEnabled: config.flashBorderEnabled !== false
  readonly property int flashBorderPx: 5
  readonly property int flashCount: Math.max(1, Number(config.flashCount || 3))
  readonly property string flashSpeed: config.flashSpeed || "normal"
  readonly property var hostBar: shell && shell.bar ? shell.bar : null
  readonly property string barPosition: hostBar ? String(hostBar.position || "top") : "top"
  readonly property bool barVertical: barPosition === "left" || barPosition === "right"
  readonly property int barPixelSize: hostBar && hostBar.barSize ? hostBar.barSize : Style.bar.sizeHorizontal
  readonly property string backgroundLink: stateHome + "/omarchy/current/background"
  readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omadoro"
  readonly property string invertedWallpaperPath: runtimeDir + "/background-invert.jpg"
  property int invertVersion: 0

  function pluginPath(name) {
    var url = String(Qt.resolvedUrl(name) || "")
    if (url.indexOf("file://") === 0) {
      var path = url.substring(7)
      if (path.charAt(0) !== "/") path = "/" + path
      return decodeURIComponent(path)
    }
    return url
  }

  function configure(settings) {
    var next = TimerModel.normalizeConfig(settings || {})
    if (JSON.stringify(next) !== JSON.stringify(config)) {
      config = next
      if (initialized && stopped) {
        setState(TimerModel.stoppedState(config, Date.now()), true)
      }
    }
    configReady = true
    initializeIfReady()
  }

  function initializeIfReady() {
    if (initialized || !configReady || !stateFileLoaded) return

    var restored = null
    if (String(loadedStateText || "").trim() !== "") {
      try {
        restored = JSON.parse(loadedStateText)
      } catch (error) {
        console.warn("Omadoro: ignoring invalid persisted timer state:", error)
      }
    }

    var result = TimerModel.recoverInterrupted(restored, config, Date.now())
    initialized = true
    lastTickMs = Date.now()
    setState(result.state, true)
    if (result.notifyPhase !== "") notifyPhaseStarted(result.notifyPhase, false)
    refreshInvertedWallpaper()
  }

  function setState(next, persist) {
    timerState = next
    nowMs = Date.now()
    if (persist) scheduleSave()
  }

  function playOrStop() {
    if (!initialized) return
    var now = Date.now()
    if (stopped) setState(TimerModel.startNewCycle(config, now), true)
    else setState(TimerModel.stoppedState(config, now), true)
    lastTickMs = now
  }

  function togglePause() {
    if (!initialized || stopped) return
    var now = Date.now()
    if (running) setState(TimerModel.pause(timerState, now), true)
    else setState(TimerModel.resume(timerState, now), true)
    lastTickMs = now
  }

  function addFiveMinutes() {
    if (!initialized || stopped) return
    setState(TimerModel.addSeconds(timerState, 5 * 60, Date.now()), true)
  }

  function skip() {
    if (!initialized || stopped) return
    var now = Date.now()
    setState(TimerModel.advance(timerState, config, now), true)
    lastTickMs = now
  }

  function tick() {
    if (!initialized) return
    var now = Date.now()
    nowMs = now

    if (!running) {
      lastTickMs = now
      return
    }

    if (lastTickMs > 0 && now - lastTickMs > 5000) {
      var recovered = TimerModel.recoverInterrupted(timerState, config, now)
      setState(recovered.state, true)
      if (recovered.notifyPhase !== "") notifyPhaseStarted(recovered.notifyPhase, false)
      lastTickMs = now
      return
    }

    if (now >= Number(timerState.deadlineMs || 0)) {
      var next = TimerModel.advance(timerState, config, now)
      setState(next, true)
      notifyPhaseStarted(next.phase)
    }
    lastTickMs = now
  }

  function notifyPhaseStarted(startedPhase, withAlerts) {
    var title = TimerModel.phaseLabel(startedPhase) + " started"
    var minutes = Math.round(TimerModel.durationSeconds(startedPhase, config) / 60)
    var description = startedPhase === TimerModel.PhaseWork
      ? minutes + " minutes of focus."
      : "Take " + minutes + " minutes."
    Quickshell.execDetached([
      notificationExecutable,
      "--app-name", "omadoro",
      "-g", "󱎫",
      "-u", "normal",
      title,
      description
    ])
    if (withAlerts === false) return
    playAlertSound()
    startAlertFlash()
  }

  function playAlertSound() {
    if (!soundEnabled) return
    previewSound()
  }

  function previewSound() {
    Quickshell.execDetached([
      "pw-play",
      "--volume=1.0",
      "--media-role", "Event",
      alertSoundFile
    ])
  }

  function previewAlert() {
    playAlertSound()
    startAlertFlash()
  }

  function refreshInvertedWallpaper() {
    if (!invertWallpaperProc.running) invertWallpaperProc.running = true
  }

  function startAlertFlash() {
    if (!flashEverythingEnabled && !flashBackgroundEnabled
        && !flashBarEnabled && !flashBorderEnabled) return
    var intervalSec = (flashIntervalMs / 1000).toFixed(3)
    flashTicksLeft = flashCount * 2
    alerting = true
    flashActive = true
    flashTimer.restart()
    if (flashBackgroundEnabled && root.invertVersion === 0) refreshInvertedWallpaper()
    if (flashEverythingEnabled) {
      Quickshell.execDetached([
        "bash",
        pluginPath("flash-invert.sh"),
        String(flashCount),
        intervalSec,
        intervalSec
      ])
    }
  }

  function scheduleSave() {
    if (!initialized) return
    savePending = true
    saveTimer.restart()
  }

  function flushState() {
    if (!savePending || !stateDirReady) return
    savePending = false
    var snapshot = TimerModel.serializableState(timerState, Date.now())
    stateFile.setText(JSON.stringify(snapshot, null, 2) + "\n")
  }

  Component.onCompleted: {
    stateDirProcess.running = true
    refreshInvertedWallpaper()
  }

  Timer {
    interval: 250
    repeat: true
    running: root.initialized
    onTriggered: root.tick()
  }

  Timer {
    id: saveTimer
    interval: 100
    repeat: false
    onTriggered: root.flushState()
  }

  Timer {
    id: flashTimer
    interval: root.flashIntervalMs
    repeat: true
    onTriggered: {
      root.alerting = !root.alerting
      root.flashTicksLeft -= 1
      if (root.flashTicksLeft <= 0) {
        root.alerting = false
        flashHideTimer.restart()
        stop()
      }
    }
  }

  Timer {
    id: flashHideTimer
    interval: root.flashIntervalMs
    repeat: false
    onTriggered: root.flashActive = false
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData
      screen: modelData
      visible: root.flashActive && (root.flashBarEnabled || root.flashBorderEnabled)
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }
      WlrLayershell.namespace: "omadoro-flash"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      mask: Region {}

      Item {
        anchors.fill: parent
        opacity: root.alerting ? 1 : 0

        Behavior on opacity {
          NumberAnimation {
            duration: Math.max(70, root.flashIntervalMs)
            easing.type: Easing.InOutCubic
          }
        }

        Rectangle {
          visible: root.flashBarEnabled
          color: Color.foreground
          x: root.barPosition === "right" ? parent.width - root.barPixelSize : 0
          y: root.barPosition === "bottom" ? parent.height - root.barPixelSize : 0
          width: root.barVertical ? root.barPixelSize : parent.width
          height: root.barVertical ? parent.height : root.barPixelSize
        }

        Rectangle {
          visible: root.flashBorderEnabled
          anchors.top: parent.top
          width: parent.width
          height: root.flashBorderPx
          color: Color.foreground
        }

        Rectangle {
          visible: root.flashBorderEnabled
          anchors.bottom: parent.bottom
          width: parent.width
          height: root.flashBorderPx
          color: Color.foreground
        }

        Rectangle {
          visible: root.flashBorderEnabled
          anchors.left: parent.left
          width: root.flashBorderPx
          height: parent.height
          color: Color.foreground
        }

        Rectangle {
          visible: root.flashBorderEnabled
          anchors.right: parent.right
          width: root.flashBorderPx
          height: parent.height
          color: Color.foreground
        }
      }
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData
      screen: modelData
      visible: root.flashActive && root.flashBackgroundEnabled && root.invertVersion > 0
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }
      WlrLayershell.namespace: "omadoro-background-flash"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      mask: Region {}

      Image {
        anchors.fill: parent
        source: root.invertVersion > 0
          ? ("file://" + root.invertedWallpaperPath + "?v=" + root.invertVersion)
          : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        opacity: root.alerting ? 1 : 0

        Behavior on opacity {
          NumberAnimation {
            duration: Math.max(70, root.flashIntervalMs)
            easing.type: Easing.InOutCubic
          }
        }
      }
    }
  }

  Process {
    id: invertWallpaperProc
    command: [
      "bash", "-c",
      "set -euo pipefail; mkdir -p \"$(dirname \"$2\")\"; src=$(readlink -f \"$1\"); magick \"$src\" -negate \"$2\"",
      "omadoro-bg",
      root.backgroundLink,
      root.invertedWallpaperPath
    ]
    onExited: function(exitCode) {
      if (exitCode === 0) root.invertVersion += 1
    }
  }

  FileView {
    path: root.backgroundLink
    watchChanges: true
    printErrors: false
    onFileChanged: root.refreshInvertedWallpaper()
    onLoaded: root.refreshInvertedWallpaper()
    onLoadFailed: root.refreshInvertedWallpaper()
  }

  Process {
    id: stateDirProcess
    command: ["mkdir", "-p", root.stateDir, root.runtimeDir]
    onExited: function(exitCode) {
      root.stateDirReady = exitCode === 0
      if (!root.stateDirReady) {
        console.warn("Omadoro: could not create the state directory")
        return
      }
      root.flushState()
    }
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: {
      root.loadedStateText = text()
      root.stateFileLoaded = true
      root.initializeIfReady()
    }
    onLoadFailed: {
      root.loadedStateText = ""
      root.stateFileLoaded = true
      root.initializeIfReady()
    }
  }
}
