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
  readonly property string shellIpcExecutable: omarchyPath !== ""
    ? omarchyPath + "/bin/omarchy-shell"
    : "omarchy-shell"

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
  readonly property bool awaitingAck: status === TimerModel.StatusAwaitingAck

  // Alert for a finished phase: a non-expiring critical notification plus a
  // ding that repeats until acknowledge() is called. Neither is a systemd
  // timer or anything else that would outlive this process, so a shell
  // restart while awaiting must re-arm both — see initializeIfReady().
  // Shipped with the plugin (tools/make-alert-sound.py regenerates it): a
  // bright C7 triple ding. The freedesktop bell.oga used before is a soft,
  // low, single chime that is trivially missed over music or a call.
  readonly property string alertSoundPath: Qt.resolvedUrl("alert-ding.wav")
    .toString().replace("file://", "")
  property int alertNotificationId: 0

  onAwaitingAckChanged: if (!awaitingAck) silenceAlert()

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
    if (result.notifyPhase !== "") notifyPhaseStarted(result.notifyPhase)
    if (result.state.status === TimerModel.StatusAwaitingAck) beginAlert(result.state.phase)
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
    if (!initialized || stopped || awaitingAck) return
    setState(TimerModel.addSeconds(timerState, 5 * 60, Date.now()), true)
  }

  function skip() {
    if (!initialized || stopped || awaitingAck) return
    var now = Date.now()
    setState(TimerModel.advance(timerState, config, now), true)
    lastTickMs = now
  }

  // The dismiss action: silences the alert (via onAwaitingAckChanged, once
  // the status below actually changes) and starts the next phase. Only takes
  // effect while awaiting; TimerModel.acknowledge() is a no-op otherwise.
  function acknowledge() {
    if (!initialized || !awaitingAck) return
    var now = Date.now()
    var next = TimerModel.acknowledge(timerState, config, now)
    setState(next, true)
    notifyPhaseStarted(next.phase)
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
      if (recovered.state.status === TimerModel.StatusAwaitingAck) beginAlert(recovered.state.phase)
      lastTickMs = now
      return
    }

    if (now >= Number(timerState.deadlineMs || 0)) {
      var finishedPhase = timerState.phase
      setState(TimerModel.awaitPhase(timerState, now), true)
      beginAlert(finishedPhase)
    }
    lastTickMs = now
  }

  // Fires once when a phase finishes: a critical (non-expiring) notification
  // plus an immediate ding, then the ding repeats until acknowledge() (or
  // Stop) ends awaitingAck and onAwaitingAckChanged calls silenceAlert().
  function beginAlert(finishedPhase) {
    sendAlertNotification(finishedPhase)
    playAlertSound()
    alertSoundTimer.restart()
  }

  function silenceAlert() {
    alertSoundTimer.stop()
    if (alertNotificationId > 0) {
      Quickshell.execDetached([
        "busctl", "--user", "call",
        "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
        "org.freedesktop.Notifications", "CloseNotification", "u",
        String(alertNotificationId)
      ])
      alertNotificationId = 0
    }
  }

  function sendAlertNotification(finishedPhase) {
    // Announce what clicking will start, and how long it runs — that is the
    // decision the alert is actually asking about.
    var upcoming = TimerModel.nextPhaseInfo(timerState, config)
    var nextLabel = TimerModel.phaseLabel(upcoming.phase)
    var nextMinutes = Math.round(TimerModel.durationSeconds(upcoming.phase, config) / 60)
    var title = nextLabel + " — " + nextMinutes + " minutes"
    var description = TimerModel.phaseLabel(finishedPhase)
      + " finished. Click this notification to start."
    // -u critical makes it non-expiring; --exec is what the notification
    // service runs when the toast is clicked, and must come last.
    alertNotifyProcess.command = [
      notificationExecutable,
      "--app-name", "omadoro",
      "-g", "󱎫",
      "-u", "critical",
      "-p",
      title,
      description,
      "--exec", shellIpcExecutable, "-q", "b.omadoro", "acknowledge"
    ]
    alertNotifyProcess.running = true
  }

  function playAlertSound() {
    Quickshell.execDetached(["paplay", alertSoundPath])
  }

  Timer {
    id: alertSoundTimer
    interval: 3000
    repeat: true
    running: false
    onTriggered: root.playAlertSound()
  }

  Process {
    id: alertNotifyProcess
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = parseInt(String(text || "").trim(), 10)
        if (isFinite(parsed) && parsed > 0) root.alertNotificationId = parsed
      }
    }
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

  // Lets the alert notification's --exec click action drive the same
  // acknowledge() the bar icon and panel button use.
  IpcHandler {
    target: "b.omadoro"

    function acknowledge(): void { root.acknowledge() }
    function status(): string {
      return JSON.stringify({
        status: root.status,
        phase: root.phase,
        remainingSeconds: root.remainingSeconds,
        completedWorkPhases: root.timerState.completedWorkPhases
      })
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
