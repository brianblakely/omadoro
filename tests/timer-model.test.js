#!/usr/bin/env node

const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const source = fs.readFileSync(path.join(__dirname, "..", "TimerModel.js"), "utf8")
const model = {}
vm.createContext(model)
vm.runInContext(source, model, { filename: "TimerModel.js" })

const config = model.normalizeConfig({
  workMinutes: 25,
  shortBreakMinutes: 5,
  longBreakMinutes: 15,
  workPhasesPerLongBreak: 4
})

function closeTo(actual, expected, message) {
  assert.ok(Math.abs(actual - expected) < 0.0001,
            `${message}: expected ${expected}, received ${actual}`)
}

assert.deepEqual(
  { ...model.normalizeConfig({ workMinutes: 0, shortBreakMinutes: 100, longBreakMinutes: 999, workPhasesPerLongBreak: 0 }) },
  { workMinutes: 1, shortBreakMinutes: 60, longBreakMinutes: 120, workPhasesPerLongBreak: 1 },
  "configuration values are integer-clamped to the manifest ranges"
)

let state = model.stoppedState(config, 0)
assert.equal(state.status, model.StatusStopped)
assert.equal(state.phase, model.PhaseWork)
assert.equal(state.remainingSec, 1500)

state = model.startNewCycle(config, 1000)
assert.equal(state.status, model.StatusRunning)
assert.equal(state.deadlineMs, 1501000)
assert.equal(model.remainingSeconds(state, 301000), 1200)
closeTo(model.elapsedProgress(state, 301000), 0.2, "elapsed progress grows through a Work phase")

state = model.pause(state, 301000)
assert.equal(state.status, model.StatusPaused)
assert.equal(state.remainingSec, 1200)
assert.equal(model.remainingSeconds(state, 901000), 1200)

state = model.resume(state, 901000)
assert.equal(state.status, model.StatusRunning)
assert.equal(state.deadlineMs, 2101000)
closeTo(model.elapsedProgress(state, 901000), 0.2, "resume preserves elapsed progress")

state = model.addSeconds(state, 300, 901000)
assert.equal(state.phaseDurationSec, 1800)
assert.equal(state.deadlineMs, 2401000)
assert.equal(model.remainingSeconds(state, 901000), 1500)
closeTo(model.elapsedProgress(state, 901000), 1 / 6, "adding time extends both total and remaining duration")

state = model.startNewCycle(config, 0)
for (let work = 1; work <= 4; work++) {
  state = model.advance(state, config, work * 1000)
  assert.equal(
    state.phase,
    work === 4 ? model.PhaseLongBreak : model.PhaseShortBreak,
    `Work phase ${work} chooses the correct break`
  )
  assert.equal(state.completedWorkPhases, work)
  state = model.advance(state, config, work * 1000 + 1)
  assert.equal(state.phase, model.PhaseWork)
}
assert.equal(state.completedWorkPhases, 0, "a completed Long Break resets the work count")

const skippedWork = model.advance(model.startNewCycle(config, 0), config, 10)
assert.equal(skippedWork.phase, model.PhaseShortBreak)
assert.equal(skippedWork.completedWorkPhases, 1, "skipping Work counts toward the cycle")

// Recovery never restarts a phase and never auto-advances one. A work phase
// interrupted mid-run (shell restart, suspend, a tick loop stalled >5s) keeps
// the time it had actually earned: restarting it from full duration here was
// what stopped the timer ever reaching a break on a laptop that suspends.
const interruptedWork = model.runningPhase(model.PhaseWork, 2, 1500, 1000)
let recovery = model.recoverInterrupted(interruptedWork, config, 601000)
assert.equal(recovery.state.phase, model.PhaseWork)
assert.equal(recovery.state.status, model.StatusRunning)
assert.equal(model.remainingSeconds(recovery.state, 601000), 900,
  "an interrupted work phase resumes where it was, not from the top")
assert.equal(recovery.state.completedWorkPhases, 2)
assert.equal(recovery.notifyPhase, "")

// A work phase whose deadline passed while away parks for acknowledgement.
recovery = model.recoverInterrupted(interruptedWork, config, 2000000)
assert.equal(recovery.state.status, model.StatusAwaitingAck)
assert.equal(recovery.state.phase, model.PhaseWork,
  "a work phase that ended while away waits to be acknowledged")
assert.equal(recovery.state.completedWorkPhases, 2)
assert.equal(recovery.notifyPhase, "")

const activeBreak = model.runningPhase(model.PhaseShortBreak, 1, 300, 1000)
recovery = model.recoverInterrupted(activeBreak, config, 121000)
assert.equal(recovery.state.phase, model.PhaseShortBreak)
assert.equal(model.remainingSeconds(recovery.state, 121000), 180)
assert.equal(recovery.notifyPhase, "")

// Same for a break: it parks instead of silently starting the next work phase.
recovery = model.recoverInterrupted(activeBreak, config, 401000)
assert.equal(recovery.state.status, model.StatusAwaitingAck)
assert.equal(recovery.state.phase, model.PhaseShortBreak,
  "a break that ended while away waits to be acknowledged")
assert.equal(recovery.state.completedWorkPhases, 1)
assert.equal(recovery.notifyPhase, "")

// The full 25/5, 25/5, 25/5, 25/15 cycle, driven only by acknowledgements.
let cycleState = model.startNewCycle(config, 0)
let cycleClock = 0
const observed = []
for (let i = 0; i < 8; i++) {
  observed.push(model.phaseLabel(cycleState.phase)
    + "/" + Math.round(cycleState.phaseDurationSec / 60))
  cycleClock += cycleState.phaseDurationSec * 1000
  cycleState = model.awaitPhase(cycleState, cycleClock)
  cycleState = model.acknowledge(cycleState, config, cycleClock)
}
assert.deepEqual(observed, [
  "Work/25", "Short Break/5",
  "Work/25", "Short Break/5",
  "Work/25", "Short Break/5",
  "Work/25", "Long Break/15"
], "four work phases, a long break only after the fourth")

const pausedBreak = model.pause(activeBreak, 61000)
recovery = model.recoverInterrupted(pausedBreak, config, 900000)
assert.equal(recovery.state.status, model.StatusPaused)
assert.equal(recovery.state.phase, model.PhaseShortBreak)
assert.equal(recovery.state.remainingSec, 240)
assert.equal(recovery.notifyPhase, "")

assert.equal(model.formatRemaining(0), "00:00")
assert.equal(model.formatRemaining(65), "01:05")
assert.equal(model.formatRemaining(3605), "60:05")

// A finished phase parks in awaitingAck instead of auto-advancing.
let running = model.startNewCycle(config, 0)
let awaiting = model.awaitPhase(running, 1500000)
assert.equal(awaiting.status, model.StatusAwaitingAck)
assert.equal(awaiting.phase, model.PhaseWork)
assert.equal(awaiting.remainingSec, 0)
assert.equal(model.remainingSeconds(awaiting, 1500000), 0)
closeTo(model.elapsedProgress(awaiting, 1500000), 1, "an awaiting phase reads as fully elapsed")

// awaitPhase only takes effect from Running; every other status is a no-op.
assert.equal(model.awaitPhase(model.stoppedState(config, 0), 0).status, model.StatusStopped)

// acknowledge() only takes effect from awaitingAck, and hands off to the
// normal advance() so the next phase starts exactly as it always has.
const acknowledged = model.acknowledge(awaiting, config, 1500000)
assert.equal(acknowledged.status, model.StatusRunning)
assert.equal(acknowledged.phase, model.PhaseShortBreak)
assert.equal(acknowledged.completedWorkPhases, 1)
assert.equal(model.acknowledge(running, config, 0).status, model.StatusRunning, "acknowledge() is a no-op outside awaitingAck")

// addSeconds() is also a no-op while awaiting acknowledgment.
assert.deepEqual(model.addSeconds(awaiting, 300, 1500000), awaiting)

// Recovery keeps an awaitingAck session parked across a restart rather than
// silently auto-advancing or resetting it.
const awaitingRecovery = model.recoverInterrupted(awaiting, config, 1600000)
assert.equal(awaitingRecovery.state.status, model.StatusAwaitingAck)
assert.equal(awaitingRecovery.state.phase, model.PhaseWork)
assert.equal(awaitingRecovery.notifyPhase, "", "recovery does not fire the one-shot phase-started notification while awaiting")

console.log("timer model tests passed")
