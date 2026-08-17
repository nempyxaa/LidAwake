import Foundation
import LidAwakeCore
import Testing
@testable import LidAwake

// J-10 failure injection: the executor's write/read handling against a
// power adapter that fails on demand — the layer the green core suite
// never touched, where the J-06/J-07 defects lived.

final class FakePowerAdapter: PowerAdapting, @unchecked Sendable {
    var sleepDisabled = false
    var batteryLPM = 0
    var failSleepDisabledWrites = false
    var failLPMWrites = false
    /// .some(nil) forces an unknown readback; nil mirrors the fake state.
    var sleepDisabledReadbackOverride: Bool??
    var lpmReadbackOverride: Int??
    var source = PowerSource.battery
    var percent: Int? = 80
    var lid = LidState.open
    private(set) var sleptNow = false

    func writeSleepDisabled(_ value: Bool) -> Int32 {
        if failSleepDisabledWrites { return 1 }
        sleepDisabled = value
        return 0
    }
    func readSleepDisabled() -> Bool? {
        if let override = sleepDisabledReadbackOverride { return override }
        return sleepDisabled
    }
    func writeBatteryLowPowerMode(_ value: Int) -> Int32 {
        if failLPMWrites { return 1 }
        batteryLPM = value
        return 0
    }
    func readBatteryLowPowerModeSetting() -> Int? {
        if let override = lpmReadbackOverride { return override }
        return batteryLPM
    }
    func liveLowPowerModeEnabled() -> Bool { batteryLPM == 1 }
    func powerSource() -> PowerSource { source }
    func batteryPercent() -> Int? { percent }
    func lidState() -> LidState { lid }
    func sleepNow() { sleptNow = true }
}

@MainActor
private struct Harness {
    let delegate: AppDelegate
    let power: FakePowerAdapter
    let suiteName: String
    let stateDir: URL
    var notified: [String] { notifications.value }
    private let notifications: Captured

    final class Captured: @unchecked Sendable {
        var value: [String] = []
    }

    init() throws {
        suiteName = "app.lidawake.tests.\(UUID().uuidString)"
        stateDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lidawake-executor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        power = FakePowerAdapter()
        delegate = AppDelegate()
        delegate.headless = true
        delegate.power = power
        delegate.state = RuntimeState(defaults: UserDefaults(suiteName: suiteName)!)
        delegate.stateDirectoryOverride = stateDir
        let captured = Captured()
        notifications = captured
        delegate.notificationSink = { captured.value.append($0) }
    }

    func log() -> String {
        (try? String(contentsOf: stateDir.appendingPathComponent("lid-guard.log"), encoding: .utf8)) ?? ""
    }

    /// A one-shot floor end: verified restore first, policy clear after —
    /// the exact shape J-06 protects.
    func executeRestoreEnd() -> Bool {
        let s = MachineSnapshot(sleepDisabled: true, oneShotActive: true)
        return delegate.execute(Decision(effects: [
            .setSleepDisabled(false, verify: true), .setLowPowerMode(false),
            .setOneShot(false), .recordPostmortem(.floor), .notify(.floorEnd(20)),
        ]), snapshot: s)
    }

    func cleanUp() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: stateDir)
    }
}

@MainActor
@Suite struct ExecutorFailureInjectionTests {
    @Test func failedWriteAbortsBeforePolicyClears() throws {
        let h = try Harness()
        defer { h.cleanUp() }
        h.delegate.state.oneShotActive = true
        h.power.sleepDisabled = true
        h.power.failSleepDisabledWrites = true
        #expect(!h.executeRestoreEnd())
        #expect(h.delegate.state.oneShotActive, "policy survives a failed write")
        #expect(h.log().contains("REVERT FAILED"))
        #expect(h.notified.count == 1, "one notification per failure streak")
    }

    @Test func unknownReadbackIsNotFalse() throws {
        // J-06: after a restore, false is exactly the expected value — an
        // unknown probe must FAIL the verification, never pass it.
        let h = try Harness()
        defer { h.cleanUp() }
        h.delegate.state.oneShotActive = true
        h.power.sleepDisabled = true
        h.power.sleepDisabledReadbackOverride = .some(nil)
        #expect(!h.executeRestoreEnd())
        #expect(h.delegate.state.oneShotActive, "unknown keeps the stored policy")
        #expect(h.log().contains("VERIFY UNKNOWN"))
    }

    @Test func readbackMismatchFailsVerification() throws {
        let h = try Harness()
        defer { h.cleanUp() }
        h.delegate.state.oneShotActive = true
        h.power.sleepDisabled = true
        h.power.sleepDisabledReadbackOverride = .some(true) // Mac says still 1
        #expect(!h.executeRestoreEnd())
        #expect(h.delegate.state.oneShotActive)
        #expect(h.log().contains("REVERT-VERIFY FAILED"))
    }

    @Test func verifiedRestoreClearsPolicyAndResetsStreak() throws {
        let h = try Harness()
        defer { h.cleanUp() }
        h.delegate.state.oneShotActive = true
        h.power.sleepDisabled = true
        #expect(h.executeRestoreEnd())
        #expect(!h.delegate.state.oneShotActive)
        #expect(!h.power.sleepDisabled)
    }

    @Test func lpmSnapshotClearsOnlyAfterVerifiedRestore() throws {
        // J-07: a failed or unverified LPM restore keeps the snapshot so a
        // later restore can still return the user's own value.
        let h = try Harness()
        defer { h.cleanUp() }
        h.delegate.state.priorLowPowerMode = 1
        h.power.batteryLPM = 0

        h.power.failLPMWrites = true
        h.delegate.restoreLowPowerMode()
        #expect(h.delegate.state.priorLowPowerMode == 1, "failed write keeps the snapshot")

        h.power.failLPMWrites = false
        h.power.lpmReadbackOverride = .some(nil)
        h.delegate.restoreLowPowerMode()
        #expect(h.delegate.state.priorLowPowerMode == 1, "unknown readback keeps the snapshot")
        #expect(h.log().contains("LPM restore NOT verified"))

        h.power.lpmReadbackOverride = nil
        h.delegate.restoreLowPowerMode()
        #expect(h.delegate.state.priorLowPowerMode == nil, "verified restore clears it")
        #expect(h.power.batteryLPM == 1, "the user's value is back")
    }
}
