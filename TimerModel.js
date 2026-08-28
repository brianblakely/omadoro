// Pure timer-state helpers shared by QML and the Node test suite.

var StateVersion = 1
var StatusStopped = "stopped"
var StatusRunning = "running"
var StatusPaused = "paused"
var PhaseWork = "work"
var PhaseShortBreak = "shortBreak"
var PhaseLongBreak = "longBreak"

function finiteNumber(value, fallback) {
  var parsed = Number(value)
  return isFinite(parsed) ? parsed : fallback
}

function boundedInteger(value, fallback, minimum, maximum) {
  var parsed = Math.round(finiteNumber(value, fallback))
  return Math.max(minimum, Math.min(maximum, parsed))
}

function booleanSetting(value, fallback) {
  if (value === undefined || value === null || value === "") return fallback
  if (typeof value === "boolean") return value
  if (typeof value === "number") return value !== 0
  var text = String(value).trim().toLowerCase()
  if (text === "true" || text === "1" || text === "yes" || text === "on") return true
  if (text === "false" || text === "0" || text === "no" || text === "off") return false
  return fallback
}

var SoundCatalog = [
  { id: "alarm", label: "Alarm", file: "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga" },
  { id: "bell", label: "Bell", file: "/usr/share/sounds/freedesktop/stereo/bell.oga" },
  { id: "chime", label: "Chime", file: "/usr/share/sounds/freedesktop/stereo/complete.oga" },
  { id: "complete", label: "Complete", file: "/usr/share/sounds/freedesktop/stereo/service-login.oga" },
  { id: "attention", label: "Instant", file: "/usr/share/sounds/freedesktop/stereo/message-new-instant.oga" },
  { id: "message", label: "Message", file: "/usr/share/sounds/freedesktop/stereo/device-added.oga" },
  { id: "pop", label: "Pop", file: "/usr/share/sounds/freedesktop/stereo/message.oga" },
  { id: "warning", label: "Warning", file: "/usr/share/sounds/freedesktop/stereo/dialog-warning.oga" }
]

var FlashSpeeds = [
  { id: "fast", label: "Fast", ms: 90 },
  { id: "normal", label: "Normal", ms: 140 },
  { id: "slow", label: "Slow", ms: 220 }
]

var ScreenModes = [
  { id: "off", label: "Off" },
  { id: "background", label: "Background" },
  { id: "all", label: "Everything" }
]

function soundEntry(name) {
  var id = String(name || "complete")
  var complete = SoundCatalog[0]
  for (var i = 0; i < SoundCatalog.length; i++) {
    if (SoundCatalog[i].id === "complete") complete = SoundCatalog[i]
    if (SoundCatalog[i].id === id) return SoundCatalog[i]
  }
  return complete
}

function soundFile(name) {
  return soundEntry(name).file
}

function soundOptions() {
  var list = []
  for (var i = 0; i < SoundCatalog.length; i++)
    list.push({ value: SoundCatalog[i].id, label: SoundCatalog[i].label })
  return list
}

function normalizeSoundName(value) {
  return soundEntry(value).id
}

function flashSpeedEntry(name) {
  var id = String(name || "normal").toLowerCase()
  for (var i = 0; i < FlashSpeeds.length; i++) {
    if (FlashSpeeds[i].id === id) return FlashSpeeds[i]
  }
  return FlashSpeeds[1]
}

function flashSpeedMs(name) {
  return flashSpeedEntry(name).ms
}

function flashSpeedOptions() {
  var list = []
  for (var i = 0; i < FlashSpeeds.length; i++)
    list.push({ value: FlashSpeeds[i].id, label: FlashSpeeds[i].label })
  return list
}

function normalizeFlashSpeed(value) {
  return flashSpeedEntry(value).id
}

function screenModeEntry(name) {
  var id = String(name || "").toLowerCase()
  for (var i = 0; i < ScreenModes.length; i++) {
    if (ScreenModes[i].id === id) return ScreenModes[i]
  }
  return null
}

function normalizeFlashScreenMode(values) {
  var mode = screenModeEntry(values && values.flashScreenMode)
  if (mode) return mode.id
  if (values && values.flashScreenEnabled !== undefined && values.flashScreenEnabled !== null
      && values.flashScreenEnabled !== "")
    return booleanSetting(values.flashScreenEnabled, false) ? "all" : "off"
  return "off"
}

function screenModeOptions() {
  var list = []
  for (var i = 0; i < ScreenModes.length; i++)
    list.push({ value: ScreenModes[i].id, label: ScreenModes[i].label })
  return list
}

function cycleScreenMode(name, delta) {
  return cycleCatalog(ScreenModes, name, delta)
}

function normalizeConfig(settings) {
  var values = settings || {}
  return {
    workMinutes: boundedInteger(values.workMinutes, 25, 1, 120),
    shortBreakMinutes: boundedInteger(values.shortBreakMinutes, 5, 1, 60),
    longBreakMinutes: boundedInteger(values.longBreakMinutes, 15, 1, 120),
    workPhasesPerLongBreak: boundedInteger(values.workPhasesPerLongBreak, 4, 1, 12),
    soundEnabled: booleanSetting(values.soundEnabled, true),
    soundName: normalizeSoundName(values.soundName),
    flashScreenMode: normalizeFlashScreenMode(values),
    flashBarEnabled: booleanSetting(values.flashBarEnabled, true),
    flashBorderEnabled: booleanSetting(values.flashBorderEnabled, true),
    flashCount: boundedInteger(values.flashCount, 3, 1, 8),
    flashSpeed: normalizeFlashSpeed(values.flashSpeed)
  }
}

function cycleCatalog(list, id, delta) {
  var index = 0
  for (var i = 0; i < list.length; i++) {
    if (list[i].id === id) { index = i; break }
  }
  var next = ((index + delta) % list.length + list.length) % list.length
  return list[next].id
}

function cycleSoundName(name, delta) {
  return cycleCatalog(SoundCatalog, name, delta)
}

function cycleFlashSpeed(name, delta) {
  return cycleCatalog(FlashSpeeds, name, delta)
}

function isPhase(value) {
  return value === PhaseWork || value === PhaseShortBreak || value === PhaseLongBreak
}

function isStatus(value) {
  return value === StatusStopped || value === StatusRunning || value === StatusPaused
}

function phaseLabel(phase) {
  if (phase === PhaseShortBreak) return "Short Break"
  if (phase === PhaseLongBreak) return "Long Break"
  return "Work"
}

function durationSeconds(phase, config) {
  var values = normalizeConfig(config)
  if (phase === PhaseShortBreak) return values.shortBreakMinutes * 60
  if (phase === PhaseLongBreak) return values.longBreakMinutes * 60
  return values.workMinutes * 60
}

function stoppedState(config, nowMs) {
  var duration = durationSeconds(PhaseWork, config)
  return {
    version: StateVersion,
    status: StatusStopped,
    phase: PhaseWork,
    completedWorkPhases: 0,
    phaseDurationSec: duration,
    remainingSec: duration,
    startedAtMs: 0,
    deadlineMs: 0,
    updatedAtMs: finiteNumber(nowMs, 0)
  }
}

function runningPhase(phase, completedWorkPhases, durationSec, nowMs) {
  var now = finiteNumber(nowMs, 0)
  var duration = Math.max(1, finiteNumber(durationSec, 1))
  return {
    version: StateVersion,
    status: StatusRunning,
    phase: isPhase(phase) ? phase : PhaseWork,
    completedWorkPhases: Math.max(0, Math.round(finiteNumber(completedWorkPhases, 0))),
    phaseDurationSec: duration,
    remainingSec: duration,
    startedAtMs: now,
    deadlineMs: now + duration * 1000,
    updatedAtMs: now
  }
}

function startNewCycle(config, nowMs) {
  return runningPhase(PhaseWork, 0, durationSeconds(PhaseWork, config), nowMs)
}

function restartWork(state, config, nowMs) {
  var completed = state ? state.completedWorkPhases : 0
  return runningPhase(PhaseWork, completed, durationSeconds(PhaseWork, config), nowMs)
}

function remainingMilliseconds(state, nowMs) {
  if (!state) return 0
  if (state.status === StatusRunning)
    return Math.max(0, finiteNumber(state.deadlineMs, 0) - finiteNumber(nowMs, 0))
  return Math.max(0, finiteNumber(state.remainingSec, 0) * 1000)
}

function remainingSeconds(state, nowMs) {
  return Math.ceil(remainingMilliseconds(state, nowMs) / 1000)
}

function elapsedProgress(state, nowMs) {
  if (!state) return 0
  var totalMs = Math.max(1000, finiteNumber(state.phaseDurationSec, 1) * 1000)
  var elapsed = totalMs - remainingMilliseconds(state, nowMs)
  return Math.max(0, Math.min(1, elapsed / totalMs))
}

function pause(state, nowMs) {
  if (!state || state.status !== StatusRunning) return state
  var now = finiteNumber(nowMs, 0)
  var remaining = remainingMilliseconds(state, now) / 1000
  var next = cloneState(state)
  next.status = StatusPaused
  next.remainingSec = Math.max(0, remaining)
  next.deadlineMs = 0
  next.updatedAtMs = now
  return next
}

function resume(state, nowMs) {
  if (!state || state.status !== StatusPaused) return state
  var now = finiteNumber(nowMs, 0)
  var remaining = Math.max(1, finiteNumber(state.remainingSec, 1))
  var total = Math.max(remaining, finiteNumber(state.phaseDurationSec, remaining))
  var next = cloneState(state)
  next.status = StatusRunning
  next.phaseDurationSec = total
  next.remainingSec = remaining
  next.startedAtMs = now - (total - remaining) * 1000
  next.deadlineMs = now + remaining * 1000
  next.updatedAtMs = now
  return next
}

function addSeconds(state, seconds, nowMs) {
  if (!state || state.status === StatusStopped) return state
  var addition = Math.max(0, finiteNumber(seconds, 0))
  if (addition === 0) return state
  var now = finiteNumber(nowMs, 0)
  var next = cloneState(state)
  next.phaseDurationSec = Math.max(1, finiteNumber(next.phaseDurationSec, 1) + addition)
  if (next.status === StatusRunning) {
    next.deadlineMs = Math.max(now, finiteNumber(next.deadlineMs, now)) + addition * 1000
    next.remainingSec = remainingMilliseconds(next, now) / 1000
  } else {
    next.remainingSec = Math.max(0, finiteNumber(next.remainingSec, 0)) + addition
  }
  next.updatedAtMs = now
  return next
}

function nextPhaseInfo(state, config) {
  var values = normalizeConfig(config)
  var completed = Math.max(0, Math.round(finiteNumber(state && state.completedWorkPhases, 0)))
  var phase = state && isPhase(state.phase) ? state.phase : PhaseWork

  if (phase === PhaseWork) {
    completed++
    if (completed >= values.workPhasesPerLongBreak)
      return { phase: PhaseLongBreak, completedWorkPhases: completed }
    return { phase: PhaseShortBreak, completedWorkPhases: completed }
  }

  if (phase === PhaseLongBreak) completed = 0
  return { phase: PhaseWork, completedWorkPhases: completed }
}

function advance(state, config, nowMs) {
  var next = nextPhaseInfo(state, config)
  return runningPhase(next.phase, next.completedWorkPhases,
                      durationSeconds(next.phase, config), nowMs)
}

function recoverInterrupted(state, config, nowMs) {
  var now = finiteNumber(nowMs, 0)
  var clean = sanitizeState(state, config, now)
  if (clean.status === StatusStopped)
    return { state: stoppedState(config, now), notifyPhase: "" }
  if (clean.status === StatusPaused)
    return { state: clean, notifyPhase: "" }

  if (clean.phase === PhaseWork)
    return { state: restartWork(clean, config, now), notifyPhase: PhaseWork }

  if (finiteNumber(clean.deadlineMs, 0) > now) {
    clean.remainingSec = remainingMilliseconds(clean, now) / 1000
    clean.updatedAtMs = now
    return { state: clean, notifyPhase: "" }
  }

  var nextWork = advance(clean, config, now)
  return { state: nextWork, notifyPhase: PhaseWork }
}

function sanitizeState(raw, config, nowMs) {
  var now = finiteNumber(nowMs, 0)
  if (!raw || Number(raw.version) !== StateVersion || !isStatus(raw.status) || !isPhase(raw.phase))
    return stoppedState(config, now)

  var phase = raw.phase
  var fallbackDuration = durationSeconds(phase, config)
  var duration = Math.max(1, finiteNumber(raw.phaseDurationSec, fallbackDuration))
  var remaining = Math.max(0, Math.min(duration, finiteNumber(raw.remainingSec, duration)))
  var status = raw.status
  if (status === StatusPaused && remaining <= 0) remaining = 1

  return {
    version: StateVersion,
    status: status,
    phase: phase,
    completedWorkPhases: Math.max(0, Math.round(finiteNumber(raw.completedWorkPhases, 0))),
    phaseDurationSec: duration,
    remainingSec: status === StatusRunning
      ? Math.max(0, finiteNumber(raw.remainingSec, duration))
      : remaining,
    startedAtMs: Math.max(0, finiteNumber(raw.startedAtMs, 0)),
    deadlineMs: status === StatusRunning ? Math.max(0, finiteNumber(raw.deadlineMs, 0)) : 0,
    updatedAtMs: Math.max(0, finiteNumber(raw.updatedAtMs, now))
  }
}

function serializableState(state, nowMs) {
  var next = cloneState(state)
  var now = finiteNumber(nowMs, 0)
  if (next.status === StatusRunning)
    next.remainingSec = remainingMilliseconds(next, now) / 1000
  next.updatedAtMs = now
  return next
}

function formatRemaining(seconds) {
  var value = Math.max(0, Math.ceil(finiteNumber(seconds, 0)))
  var minutes = Math.floor(value / 60)
  var remainder = value % 60
  return String(minutes).padStart(2, "0") + ":" + String(remainder).padStart(2, "0")
}

function cloneState(state) {
  var copy = {}
  for (var key in state) copy[key] = state[key]
  return copy
}
