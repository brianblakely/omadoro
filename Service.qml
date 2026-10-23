import QtQuick
import Quickshell
import Quickshell.Io
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

  readonly property string status: timerState.status
  readonly property string phase: timerState.phase
  readonly property string phaseLabel: TimerModel.phaseLabel(phase)
  readonly property int remainingSeconds: TimerModel.remainingSeconds(timerState, nowMs)
  readonly property string remainingText: TimerModel.formatRemaining(remainingSeconds)
  readonly property real progress: TimerModel.elapsedProgress(timerState, nowMs)
  readonly property bool stopped: status === TimerModel.StatusStopped
  readonly property bool running: status === TimerModel.StatusRunning
  readonly property bool paused: status === TimerModel.StatusPaused

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

  // Apply one duration change before the shell.json round trip lands, so the
  // panel never snaps back to the old value for a frame. configure() clamps
  // and, while stopped, retimes the face; the persisted settings that follow
  // resolve to the same config and therefore do nothing.
  function setConfigValue(key, value) {
    var values = {}
    for (var name in config) values[name] = config[name]
    values[key] = value
    configure(values)
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
    if (result.notifyPhase !== "") notifyPhaseStarted(result.notifyPhase)
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
      if (recovered.notifyPhase !== "") notifyPhaseStarted(recovered.notifyPhase)
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

  function notifyPhaseStarted(startedPhase) {
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

  Component.onCompleted: stateDirProcess.running = true

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

  Process {
    id: stateDirProcess
    command: ["mkdir", "-p", root.stateDir]
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
