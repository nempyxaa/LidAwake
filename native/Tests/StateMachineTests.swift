import Foundation

private var failures = 0
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() { print("PASS: \(message)") }
    else { failures += 1; print("FAIL: \(message)") }
}

private struct FaultHarness {
    var sleepDisabled = true
    var batteryOverride = true
    var manualOff = false
    var notices: [Notice] = []
    var logs: [String] = []

    mutating func execute(_ decision: Decision, failDisable: Bool = false) {
        for effect in decision.effects {
            switch effect {
            case let .setSleepDisabled(value, _):
                if !value && failDisable { logs.append("REVERT-VERIFY FAILED"); notices.append(.revertFailure); return }
                sleepDisabled = value
            case let .setBatteryOverride(value): batteryOverride = value
            case let .setManualOff(value): manualOff = value
            case let .notify(notice): notices.append(notice)
            case let .log(message): logs.append(message)
            default: break
            }
        }
    }
}

private func snapshot(power: PowerSource = .battery, battery: Int? = 80,
                      disabled: Bool = false, override: Bool = false,
                      manual: Bool = false, lid: LidState = .open,
                      previous: LidState = .open, thermal: Int = 0,
                      floor: Int = 20, elapsed: TimeInterval = 60) -> MachineSnapshot {
    MachineSnapshot(power: power, batteryPercent: battery, sleepDisabled: disabled,
                    batteryOverride: override, manualOff: manual, lid: lid,
                    previousLid: previous, secondsSinceLastTick: elapsed,
                    thermalState: thermal, thermalGuard: true, batteryFloor: floor)
}

@main
private enum StateMachineTestRunner {
    static func main() {
        let ac = StateMachine.guardTick(snapshot(power: .ac))
        expect(ac.effects.contains(.setSleepDisabled(true, verify: true)), "AC guard arms keep-awake with C9 verification")
        expect(ac.effects.contains(.notify(.acAutoOn)), "AC arm records its success notification")

        let refused = StateMachine.toggle(snapshot(battery: 24, floor: 20))
        expect(refused.effects == [.notify(.lowRefusal)], "battery arm is refused below floor + 5")
        let boundary = StateMachine.toggle(snapshot(battery: 25, floor: 20))
        expect(boundary.effects.contains(.setBatteryOverride(true)), "battery arm is allowed at floor + 5")

        let opened = StateMachine.guardTick(snapshot(disabled: true, override: true, lid: .open, previous: .closed))
        expect(opened.effects.contains(.setBatteryOverride(false)), "lid-open clears battery override")
        expect(opened.effects.contains(.setSleepDisabled(false, verify: true)), "lid-open revert is verified")
        expect(opened.effects.contains(.notify(.lidOpened)), "lid-open records its notification")

        let hot = StateMachine.guardTick(snapshot(disabled: true, override: true, lid: .closed, thermal: 2))
        expect(hot.effects.contains(.sleepNow), "thermal state 2 forces sleep")
        expect(hot.effects.contains(.setLowPowerMode(false)), "thermal revert disables Low Power Mode")
        expect(hot.terminal, "thermal force-sleep ends the guard tick")

        let off = StateMachine.toggle(snapshot(power: .ac, disabled: true, override: true))
        expect(off.effects.first == .setManualOff(true), "manual OFF persists retry intent before attempting cleanup")
        expect(off.effects.dropFirst().first == .setSleepDisabled(false, verify: true), "manual OFF verifies before clearing override state")
        expect(off.effects.last == .notify(.off), "manual OFF notifies only after verified cleanup")

        let failedOffRetry = StateMachine.guardTick(snapshot(power: .ac, disabled: true, manual: true))
        expect(failedOffRetry.effects.first == .setSleepDisabled(false, verify: true), "failed OFF retries on AC")
        let failedOffBatteryRetry = StateMachine.guardTick(snapshot(power: .battery, disabled: true, override: true, manual: true))
        expect(failedOffBatteryRetry.effects.first == .setSleepDisabled(false, verify: true), "failed OFF retries on battery")
        var failedOff = FaultHarness()
        failedOff.execute(off, failDisable: true)
        expect(failedOff.sleepDisabled && failedOff.batteryOverride && failedOff.manualOff, "failed pmset OFF retains recoverable persisted state and retry intent")
        expect(!failedOff.notices.contains(.off) && failedOff.notices.contains(.revertFailure), "failed pmset OFF suppresses OFF and raises failure")
        expect(failedOff.logs.contains("REVERT-VERIFY FAILED"), "failed pmset OFF is logged")

        let relaunched = StateMachine.guardTick(snapshot(disabled: true, override: true, lid: .closed, previous: .closed, elapsed: 60))
        expect(!relaunched.effects.contains(.setBatteryOverride(false)), "persisted override survives controller relaunch")
        var killedThenRelaunched = FaultHarness()
        killedThenRelaunched.execute(relaunched)
        expect(killedThenRelaunched.sleepDisabled && killedThenRelaunched.batteryOverride, "simulated kill and persisted-state relaunch preserves a safe active override")
        let relaunchedUnsafe = StateMachine.guardTick(snapshot(disabled: true, override: false, lid: .closed, previous: .closed, elapsed: 60))
        expect(relaunchedUnsafe.effects.first == .setSleepDisabled(false, verify: true), "relaunch without persisted override fails safe")

        let clockJump = StateMachine.guardTick(snapshot(disabled: true, override: true, lid: .closed, previous: .closed, elapsed: 600))
        expect(clockJump.effects.first == .setSleepDisabled(false, verify: true), "clock jump verifies sleep before clearing override")
        expect(clockJump.effects.contains(.setBatteryOverride(false)), "clock jump clears the expired override")

        let unknownLid = StateMachine.guardTick(snapshot(disabled: true, override: true, lid: .unknown, previous: .closed))
        expect(!unknownLid.effects.contains(.setSleepDisabled(false, verify: true)), "unknown lid does not invent an open edge")

        let starved = StateMachine.guardTick(snapshot(disabled: true, override: true, lid: .closed, previous: .closed, elapsed: 421))
        expect(starved.effects.first == .setSleepDisabled(false, verify: true), "timer starvation cleanup is transactional")

        let batteryAfterAC = StateMachine.guardTick(snapshot(power: .battery, disabled: true, override: false))
        expect(batteryAfterAC.effects.first == .setSleepDisabled(false, verify: true), "AC to battery flap restores sleep without an override")
        let acWithBatteryOverride = StateMachine.guardTick(snapshot(power: .ac, disabled: true, override: true))
        expect(acWithBatteryOverride.effects.contains(.setBatteryOverride(false)), "battery to AC flap clears the battery-only override")

        var failedThermal = FaultHarness()
        failedThermal.execute(hot, failDisable: true)
        expect(failedThermal.batteryOverride && !failedThermal.notices.contains(.hot), "failed thermal revert retains override and suppresses success notice")

        if failures > 0 { fputs("\(failures) test(s) failed\n", stderr); exit(1) }
        print("All state-machine tests passed")
    }
}
