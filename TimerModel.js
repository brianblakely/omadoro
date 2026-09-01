// Pure timer-state helpers shared by QML and the Node test suite.

var StateVersion = 1
var StatusStopped = "stopped"
var StatusRunning = "running"
var StatusPaused = "paused"
var StatusAwaitingAck = "awaitingAck"
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

function normalizeConfig(settings) {
  var values = settings || {}
  return {
    workMinutes: boundedInteger(values.workMinutes, 25, 1, 120),
    shortBreakMinutes: boundedInteger(values.shortBreakMinutes, 5, 1, 60),
    longBreakMinutes: boundedInteger(values.longBreakMinutes, 15, 1, 120),
    workPhasesPerLongBreak: boundedInteger(values.workPhasesPerLongBreak, 4, 1, 12)
  }
}

function isPhase(value) {
  return value === PhaseWork || value === PhaseShortBreak || value === PhaseLongBreak
}

function isStatus(value) {
  return value === StatusStopped || value === StatusRunning || value === StatusPaused
    || value === StatusAwaitingAck
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
  if (!state || state.status === StatusStopped || state.status === StatusAwaitingAck) return state
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

// A finished phase parks here instead of auto-advancing, so the next phase
// only starts once the user has actually dismissed the alert.
function awaitPhase(state, nowMs) {
  if (!state || state.status !== StatusRunning) return state
  var now = finiteNumber(nowMs, 0)
  var next = cloneState(state)
  next.status = StatusAwaitingAck
  next.remainingSec = 0
  next.deadlineMs = 0
  next.updatedAtMs = now
  return next
}

// The dismiss action: only takes effect from awaitingAck, and reuses the
// normal advance() so the next phase starts exactly as it always has.
function acknowledge(state, config, nowMs) {
  if (!state || state.status !== StatusAwaitingAck) return state
  return advance(state, config, nowMs)
}

function recoverInterrupted(state, config, nowMs) {
  var now = finiteNumber(nowMs, 0)
  var clean = sanitizeState(state, config, now)
  if (clean.status === StatusStopped)
    return { state: stoppedState(config, now), notifyPhase: "" }
  if (clean.status === StatusPaused)
    return { state: clean, notifyPhase: "" }
  // Still waiting for dismissal across the restart: keep it parked, and let
  // the caller re-arm its own alert (notification/sound) rather than firing
  // the one-shot "phase started" notification this function normally signals.
  if (clean.status === StatusAwaitingAck)
    return { state: clean, notifyPhase: "" }

  // Still running. A phase must never restart and never auto-advance: the only
  // way out of a finished phase is the user acknowledging it. If the deadline
  // passed while the shell was away (suspend/resume, a shell restart, or a tick
  // loop stalled for more than 5s), park it in awaitingAck exactly as the live
  // tick would have at the instant it ended, and let the caller re-arm the
  // alert. Previously a running work phase was restarted from full duration
  // here, so a single suspend during work meant the timer never reached a
  // break at all; a running break was auto-advanced straight into work without
  // any acknowledgement.
  if (finiteNumber(clean.deadlineMs, 0) <= now)
    return { state: awaitPhase(clean, now), notifyPhase: "" }

  clean.remainingSec = remainingMilliseconds(clean, now) / 1000
  clean.updatedAtMs = now
  return { state: clean, notifyPhase: "" }
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
