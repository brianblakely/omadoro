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
  {
    workMinutes: 1,
    shortBreakMinutes: 60,
    longBreakMinutes: 120,
    workPhasesPerLongBreak: 1,
    soundEnabled: true,
    soundName: "complete",
    flashScreenMode: "off",
    flashBarEnabled: true,
    flashBorderEnabled: true,
    flashCount: 3,
    flashSpeed: "normal"
  },
  "configuration values are integer-clamped to the manifest ranges"
)

assert.equal(model.booleanSetting(undefined, true), true)
assert.equal(model.booleanSetting("false", true), false)
assert.equal(model.booleanSetting("0", true), false)
assert.equal(model.booleanSetting("off", true), false)
assert.equal(model.booleanSetting(false, true), false)
assert.equal(model.booleanSetting("true", false), true)
assert.equal(model.booleanSetting("yes", false), true)
assert.equal(
  model.normalizeConfig({ soundEnabled: "off", flashEnabled: 0 }).soundEnabled,
  false
)
assert.equal(
  model.normalizeConfig({ soundEnabled: "off", flashScreenEnabled: 0 }).flashScreenMode,
  "off"
)
assert.equal(model.normalizeConfig({ flashCount: 0 }).flashCount, 1)
assert.equal(model.normalizeConfig({ flashCount: 99 }).flashCount, 8)
assert.equal(model.normalizeConfig({ flashCount: "5" }).flashCount, 5)
assert.equal(model.normalizeConfig({ flashScreenEnabled: true }).flashScreenMode, "all")
assert.equal(model.normalizeConfig({ flashScreenMode: "background" }).flashScreenMode, "background")
assert.equal(model.cycleScreenMode("off", 1), "background")
assert.equal(model.normalizeConfig({ soundName: "alarm" }).soundName, "alarm")
assert.equal(model.normalizeConfig({ soundName: "nope" }).soundName, "complete")
assert.equal(model.normalizeConfig({ flashSpeed: "slow" }).flashSpeed, "slow")
assert.equal(model.soundFile("bell"), "/usr/share/sounds/freedesktop/stereo/bell.oga")
assert.notEqual(model.soundFile("attention"), model.soundFile("warning"))
assert.equal(model.soundFile("attention"), "/usr/share/sounds/freedesktop/stereo/message-new-instant.oga")
assert.equal(model.soundFile("chime"), "/usr/share/sounds/freedesktop/stereo/complete.oga")
assert.equal(model.soundFile("complete"), "/usr/share/sounds/freedesktop/stereo/service-login.oga")
assert.equal(model.soundFile("pop"), "/usr/share/sounds/freedesktop/stereo/message.oga")
assert.equal(model.soundFile("message"), "/usr/share/sounds/freedesktop/stereo/device-added.oga")
assert.equal(model.cycleSoundName("complete", 1), "attention")
assert.equal(model.flashSpeedMs("fast"), 90)
assert.equal(model.cycleFlashSpeed("normal", 1), "slow")

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
