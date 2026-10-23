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

assert.deepEqual(
  { ...model.configBounds("workMinutes") },
  { minimum: 1, maximum: 120 },
  "the panel reads its work range from the shared bounds"
)
assert.deepEqual(
  { ...model.configBounds("shortBreakMinutes") },
  { minimum: 1, maximum: 60 },
  "the panel reads its short-break range from the shared bounds"
)
assert.equal(model.clampDuration("workMinutes", 0), 1, "typed values clamp up to the range")
assert.equal(model.clampDuration("workMinutes", 999), 120, "typed values clamp down to the range")
assert.equal(model.clampDuration("shortBreakMinutes", "7"), 7, "numeric strings from the editor are accepted")
assert.equal(model.clampDuration("shortBreakMinutes", 12.4), 12, "typed values round to whole minutes")
assert.equal(model.clampDuration("workPhasesPerLongBreak", 0), 1, "phase counts share the same clamp")
assert.equal(model.clampDuration("notAKey", 5), null, "unknown keys are rejected instead of coerced")

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

const interruptedWork = model.runningPhase(model.PhaseWork, 2, 1500, 1000)
let recovery = model.recoverInterrupted(interruptedWork, config, 601000)
assert.equal(recovery.state.phase, model.PhaseWork)
assert.equal(recovery.state.remainingSec, 1500)
assert.equal(recovery.state.completedWorkPhases, 2)
assert.equal(recovery.notifyPhase, model.PhaseWork)

const activeBreak = model.runningPhase(model.PhaseShortBreak, 1, 300, 1000)
recovery = model.recoverInterrupted(activeBreak, config, 121000)
assert.equal(recovery.state.phase, model.PhaseShortBreak)
assert.equal(model.remainingSeconds(recovery.state, 121000), 180)
assert.equal(recovery.notifyPhase, "")

recovery = model.recoverInterrupted(activeBreak, config, 401000)
assert.equal(recovery.state.phase, model.PhaseWork)
assert.equal(recovery.state.completedWorkPhases, 1)
assert.equal(recovery.state.remainingSec, 1500)
assert.equal(recovery.notifyPhase, model.PhaseWork)

const pausedBreak = model.pause(activeBreak, 61000)
recovery = model.recoverInterrupted(pausedBreak, config, 900000)
assert.equal(recovery.state.status, model.StatusPaused)
assert.equal(recovery.state.phase, model.PhaseShortBreak)
assert.equal(recovery.state.remainingSec, 240)
assert.equal(recovery.notifyPhase, "")

assert.equal(model.formatRemaining(0), "00:00")
assert.equal(model.formatRemaining(65), "01:05")
assert.equal(model.formatRemaining(3605), "60:05")

console.log("timer model tests passed")
