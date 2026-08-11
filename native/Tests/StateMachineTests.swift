import Foundation

private var failures = 0
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() { print("PASS: \(message)") }
    else { failures += 1; print("FAIL: \(message)") }
}

private func snapshot(power: PowerSource = .battery, battery: Int? = 80,
                      disabled: Bool = false, override: Bool = false,
                      manual: Bool = false, lid: LidState = .open,
                      previous: LidState = .open, thermal: Int = 0,
                      floor: Int = 20) -> MachineSnapshot {
    MachineSnapshot(power: power, batteryPercent: battery, sleepDisabled: disabled,
                    batteryOverride: override, manualOff: manual, lid: lid,
                    previousLid: previous, secondsSinceLastTick: 60,
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

        if failures > 0 { fputs("\(failures) test(s) failed\n", stderr); exit(1) }
        print("All state-machine tests passed")
    }
}
