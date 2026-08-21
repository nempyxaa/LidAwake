import AppKit
import Darwin
import Foundation
import LidAwakeCore
import ServiceManagement
import UserNotifications

enum AppActivity {
    /// Options for the process-lifetime Foundation activity. J-01: this
    /// must never include .idleSystemSleepDisabled (which .userInitiated
    /// does) — the app starts at login and the watchdog keeps it alive, so
    /// a PreventUserIdleSystemSleep assertion here would stop every
    /// open-lid idle sleep even with Keep awake off. Clamshell behavior is
    /// unaffected either way; that is pmset disablesleep's job.
    static let options: ProcessInfo.ActivityOptions = [.userInitiatedAllowingIdleSystemSleep]
    static let reason = "Keep LidAwake safety state fresh"
}

final class RuntimeState {
    private let d: UserDefaults
    /// The persistence seam (J-10): production state lives in .standard,
    /// tests inject a scratch suite.
    init(defaults: UserDefaults = .standard) { d = defaults }
    var oneShotActive: Bool { get { d.bool(forKey: "oneShotActive") } set { d.set(newValue, forKey: "oneShotActive") } }
    var acDeclined: Bool { get { d.bool(forKey: "acDeclined") } set { d.set(newValue, forKey: "acDeclined") } }
    var skipOnce: Bool { get { d.bool(forKey: "skipOnce") } set { d.set(newValue, forKey: "skipOnce") } }
    var alwaysPaused: Bool { get { d.bool(forKey: "alwaysPaused") } set { d.set(newValue, forKey: "alwaysPaused") } }
    var acHoldStart: Date? { get { d.object(forKey: "acHoldStart") as? Date } set { d.set(newValue, forKey: "acHoldStart") } }
    /// The user's own Low Power Mode value, snapshotted the moment Keep awake
    /// first turns LPM on; restored — never blind-forced off — when Keep
    /// awake ends. Persisted so a crash or reboot cannot orphan the value.
    var priorLowPowerMode: Int? {
        get { d.object(forKey: "priorLowPowerMode") as? Int }
        set { if let newValue { d.set(newValue, forKey: "priorLowPowerMode") } else { d.removeObject(forKey: "priorLowPowerMode") } }
    }
    var useLowPowerMode: Bool { d.bool(forKey: "useLowPowerMode") }
    var lastHotAt: Date? { get { d.object(forKey: "lastHotAt") as? Date } set { d.set(newValue, forKey: "lastHotAt") } }
    var postmortem: String? {
        get { d.string(forKey: "postmortem") }
        set { if let newValue { d.set(newValue, forKey: "postmortem") } else { d.removeObject(forKey: "postmortem") } }
    }
    var lastPercent: Int? {
        get { d.object(forKey: "lastPercent") as? Int }
        set { d.set(newValue, forKey: "lastPercent") }
    }
    var lastTickAt: Date? { get { d.object(forKey: "lastTickAt") as? Date } set { d.set(newValue, forKey: "lastTickAt") } }
    var priorLid: LidState {
        get { LidState(rawValue: d.string(forKey: "priorLid") ?? "") ?? .unknown }
        set { d.set(newValue.rawValue, forKey: "priorLid") }
    }
    var priorPower: PowerSource {
        get { d.string(forKey: "priorPower") == "ac" ? .ac : .battery }
        set { d.set(newValue == .ac ? "ac" : "battery", forKey: "priorPower") }
    }
    var bootTime: String? { get { d.string(forKey: "bootTime") } set { d.set(newValue, forKey: "bootTime") } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    // The status item carries an image from the moment it exists: v2's
    // worst regression was a healthy process with an empty menu-bar slot.
    // If even the placeholder symbol fails to load, the title falls back
    // to "LA" so there is always something visible to click.
    lazy var status: NSStatusItem = {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let placeholder = NSImage(systemSymbolName: "cup.and.saucer",
                                     accessibilityDescription: V3Strings.appName) {
            placeholder.isTemplate = true
            item.button?.image = placeholder
        } else {
            item.button?.title = V3Strings.iconFallback
        }
        return item
    }()
    var state = RuntimeState()
    /// The system seams (J-10); tests swap in fakes to inject failures.
    var power: any PowerAdapting = SystemPowerAdapter()
    var launchd: any LaunchdAdapting = SystemLaunchdAdapter()
    /// When set, notification bodies go here instead of the notification
    /// center (whose UN framework needs a bundled app context).
    var notificationSink: ((String) -> Void)?
    private var timer: Timer?
    var permissionAlertShown = false
    /// One notification per failure streak: without the sudoers rule the
    /// 60-second tick would otherwise notify forever. The per-tick log line
    /// stays; the streak resets on the first verified write that succeeds.
    private var failureStreakNotified = false
    private var activity: NSObjectProtocol?
    var headless = false
    private var postmortemDisplayed = false

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = status // create the status item (with its placeholder icon) FIRST
        migrateStateDirectory()
        guard resolveSingleInstance() else { NSApp.terminate(nil); return }
        registerDefaults()
        migrateOldIdentifierDomain()
        migrateV2Defaults()
        logEvent("launch v\(Self.appVersion) (pid \(ProcessInfo.processInfo.processIdentifier))")
        logPmsetAnchor()
        status.menu = NSMenu(); status.menu?.delegate = self
        requestNotificationsIfNeeded()
        configurePersistentServices()
        reconcileBoot()
        refreshMenu()
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = 5
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(systemWillSleep),
                              name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(systemDidWake),
                              name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensDidSleep),
                              name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensDidWake),
                              name: NSWorkspace.screensDidWakeNotification, object: nil)
        activity = ProcessInfo.processInfo.beginActivity(options: AppActivity.options, reason: AppActivity.reason)
        // J-07: validate ALL five privileged command forms, not just one —
        // a partial sudoers rule must surface at startup, with the full
        // repair line in the alert, not as a runtime failure later.
        let missingForms = missingSudoForms()
        if !missingForms.isEmpty {
            appendLog("sudoers validation: missing pmset forms: "
                + missingForms.map { $0.joined(separator: " ") }.joined(separator: ", "))
            showSudoFix()
        }
    }

    func runGuardTickHeadless() {
        headless = true
        migrateStateDirectory()
        registerDefaults()
        migrateOldIdentifierDomain()
        migrateV2Defaults()
        reconcileBoot()
        tick(refresh: false)
    }

    private func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            "notifications": true, "batteryFloor": 20,
            "batteryMode": BatteryMode.untilLidFloorHot.rawValue,
            "useLowPowerMode": SettingsDefaults.useLowPowerMode,
        ])
    }

    func menuWillOpen(_ menu: NSMenu) {
        postmortemDisplayed = state.postmortem != nil
        refreshMenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        // The postmortem line persists until the first menu open after the end.
        if postmortemDisplayed { state.postmortem = nil; postmortemDisplayed = false }
    }

    var floor: Int { UserDefaults.standard.integer(forKey: "batteryFloor") }
    var mode: BatteryMode { BatteryMode(rawValue: UserDefaults.standard.integer(forKey: "batteryMode")) ?? .untilLidFloorHot }

    func snapshot() -> MachineSnapshot {
        let now = Date()
        let thermal = ProcessInfo.processInfo.thermalState.rawValue
        if thermal >= StateMachine.seriousThermal { state.lastHotAt = now }
        let thermalOK = state.lastHotAt.map { now.timeIntervalSince($0) } ?? 1_000_000_000
        return MachineSnapshot(
            power: power.powerSource(), previousPower: state.priorPower,
            batteryPercent: power.batteryPercent(),
            lid: power.lidState(), previousLid: state.priorLid,
            thermalState: thermal, thermalOKSeconds: thermalOK,
            // An unknown probe reads as false only HERE, where it is safe:
            // any policy-clearing decision leads with a verified pmset
            // write, and verification refuses an unknown readback (J-06).
            sleepDisabled: power.readSleepDisabled() ?? false,
            mode: mode, oneShotActive: state.oneShotActive,
            acDeclined: state.acDeclined, skipOnce: state.skipOnce,
            alwaysPaused: state.alwaysPaused,
            acHoldSeconds: state.acHoldStart.map { now.timeIntervalSince($0) },
            batteryFloor: floor,
            useLowPowerMode: state.useLowPowerMode)
    }

    private func tick(refresh: Bool = true) {
        let s = snapshot()
        let applied = execute(StateMachine.tick(s), snapshot: s)
        // Edge-triggered transitions (lid opened, unplugged) must re-fire
        // after a failed pmset write: advance the edge baselines only when
        // the whole decision applied, so the next tick retries the same edge.
        if applied {
            state.priorLid = s.lid
            state.priorPower = s.power
        }
        if let percent = s.batteryPercent { state.lastPercent = percent }
        state.lastTickAt = Date()
        if refresh { refreshMenu() }
    }

    // MARK: Actions

    @objc func armClicked() {
        // The arm click carries its power context into the event log: the
        // 15:28 question ("was Keep awake armed, and on what power?") must
        // be answerable from this line plus the result line that follows.
        let s = snapshot()
        logEvent("arm clicked (power=\(label(s.power)), battery=\(label(s.batteryPercent)), "
            + "mode=\(s.mode.rawValue + 1), SleepDisabled pre=\(s.sleepDisabled ? "1" : "0"))")
        _ = execute(StateMachine.arm(s), snapshot: s)
        refreshMenu()
    }
    @objc func declineClicked() { act { StateMachine.declineOnPower($0) } }
    @objc func turnOffClicked() { act { StateMachine.turnOffOneShot($0) } }
    @objc func skipOnceClicked() { act { StateMachine.toggleSkipOnce($0) } }
    @objc func sleepNowClicked() { act { StateMachine.sleepNowAction($0) } }
    @objc func turnOffAlwaysClicked() {
        let s = snapshot()
        guard execute(StateMachine.turnOffAlways(s), snapshot: s) else { refreshMenu(); return }
        UserDefaults.standard.set(BatteryMode.untilLidFloorHot.rawValue, forKey: "batteryMode")
        refreshMenu()
    }
    @objc func setBatteryMode(_ sender: NSMenuItem) {
        guard let newMode = BatteryMode(rawValue: sender.tag) else { return }
        let s = snapshot()
        guard execute(StateMachine.modeChanged(s, to: newMode), snapshot: s) else { refreshMenu(); return }
        UserDefaults.standard.set(newMode.rawValue, forKey: "batteryMode")
        refreshMenu()
    }
    @objc func setFloor(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: "batteryFloor")
        tick() // the resume predicate and every label recompute on floor change
    }
    @objc func toggleNotifications() {
        let d = UserDefaults.standard, value = !d.bool(forKey: "notifications")
        d.set(value, forKey: "notifications")
        if value { requestNotificationsIfNeeded() }
        refreshMenu()
    }

    @objc func toggleLowPowerModeSetting() {
        let defaults = UserDefaults.standard
        let enabled = !defaults.bool(forKey: "useLowPowerMode")
        if !enabled { restoreLowPowerMode() }
        defaults.set(enabled, forKey: "useLowPowerMode")
        refreshMenu()
    }

    private func act(_ decide: (MachineSnapshot) -> Decision) {
        let s = snapshot()
        _ = execute(decide(s), snapshot: s)
        refreshMenu()
    }

    @objc private func systemWillSleep() {
        let s = snapshot()
        // THE adjudication line: at the moment the system commits to sleep,
        // record what Keep awake believed and what pmset actually held.
        logEvent("system willSleep (lid=\(s.lid.rawValue), power=\(label(s.power)), "
            + "battery=\(label(s.batteryPercent)), SleepDisabled=\(s.sleepDisabled ? "1" : "0"), "
            + "oneShot=\(s.oneShotActive), mode=\(s.mode.rawValue + 1), alwaysPaused=\(s.alwaysPaused))")
        _ = execute(StateMachine.systemWillSleep(s), snapshot: s)
    }
    @objc private func systemDidWake() {
        logEvent("system didWake")
        tick()
    }
    @objc private func screensDidSleep() { logEvent("screens did sleep") }
    @objc private func screensDidWake() { logEvent("screens did wake") }

    private func label(_ power: PowerSource) -> String { power == .ac ? "AC" : "battery" }
    private func label(_ percent: Int?) -> String { percent.map { "\($0)%" } ?? "?" }

    // MARK: Effect executor

    @discardableResult func execute(_ decision: Decision, snapshot s: MachineSnapshot) -> Bool {
        for effect in decision.respectingLowPowerModeSetting(s).effects {
            switch effect {
            case let .setSleepDisabled(value, verify):
                let writeStatus = power.writeSleepDisabled(value)
                if verify {
                    // J-06: the write must report status 0 AND the readback
                    // must match. An unknown readback is NOT false — false is
                    // exactly the expected value after a restore, so unknown
                    // fails verification, which keeps the stored policy and
                    // the edge baselines and retries on the next tick.
                    let readback = power.readSleepDisabled()
                    if writeStatus != 0 || readback != value {
                        if writeStatus != 0 {
                            appendLog(value ? "enable FAILED (pmset write status \(writeStatus))"
                                            : "REVERT FAILED (pmset write status \(writeStatus))")
                        } else if readback == nil {
                            appendLog("VERIFY UNKNOWN (pmset -g unreadable; policy kept, retrying)")
                        } else {
                            appendLog(value ? "enable FAILED (pmset)" : "REVERT-VERIFY FAILED (SleepDisabled still 1)")
                        }
                        if !failureStreakNotified {
                            failureStreakNotified = true
                            deliverNotification(body: value ? V3Strings.notifyFailure : V3Strings.notifyRevertFailure)
                        }
                        showSudoFix()
                        return false
                    }
                    failureStreakNotified = false
                    appendLog("pmset SleepDisabled=\(value ? "1" : "0") verified")
                } else {
                    appendLog("pmset SleepDisabled=\(value ? "1" : "0") write status \(writeStatus) (unverified)")
                }
            case let .setLowPowerMode(value):
                // Snapshot-and-restore (decision D3): remember the user's own
                // LPM value before the first turn-on, put it back at the end.
                // With no snapshot we never touched LPM — leave it alone
                // rather than blind-forcing it off.
                if value {
                    if state.priorLowPowerMode == nil {
                        state.priorLowPowerMode = power.liveLowPowerModeEnabled() ? 1 : 0
                    }
                    let writeStatus = power.writeBatteryLowPowerMode(1)
                    if writeStatus != 0 { appendLog("LPM enable FAILED (pmset write status \(writeStatus))") }
                } else {
                    restoreLowPowerMode()
                }
            case let .setOneShot(value):
                state.oneShotActive = value
                if value { state.postmortem = nil } // the line persists until the next arm
            case let .setACDeclined(value): state.acDeclined = value
            case let .setSkipOnce(value): state.skipOnce = value
            case let .setAlwaysPaused(value): state.alwaysPaused = value
            case let .setACHold(value):
                state.acHoldStart = value ? (state.acHoldStart ?? Date()) : nil
            case let .recordPostmortem(cause): recordPostmortem(cause, snapshot: s)
            case let .notify(kind): deliverNotification(body: body(for: kind))
            case let .log(message): appendLog(message)
            case .thermalHistory: appendThermalHistory()
            case .sleepNow: power.sleepNow()
            }
        }
        return true
    }

    private func recordPostmortem(_ cause: EndCause, snapshot s: MachineSnapshot) {
        let percent: Int, at: Date
        if cause == .restart {
            percent = state.lastPercent ?? s.batteryPercent ?? 0
            at = state.lastTickAt ?? Date()
        } else {
            percent = s.batteryPercent ?? state.lastPercent ?? 0
            at = Date()
        }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        state.postmortem = V3Strings.postmortem(percent, f.string(from: at))
    }

    private func body(for notice: Notice) -> String {
        switch notice {
        case .acAutoOn: return V3Strings.notifyACOn
        case .batteryAutoOff: return V3Strings.notifyBatteryOff
        case .manualOff: return V3Strings.notifyManualOff
        case .lidEnd: return V3Strings.notifyLidEnd
        case let .floorEnd(percent): return V3Strings.notifyFloorEnd(percent)
        case .batteryUnavailableEnd: return V3Strings.notifyBatteryUnavailable
        case .hotEnd: return V3Strings.notifyHotEnd
        case let .floorPaused(floor): return V3Strings.notifyFloorPaused(floor)
        case .hotPaused: return V3Strings.notifyHotPaused
        case .alwaysResumed: return V3Strings.notifyAlwaysResumed
        case .acExpired: return V3Strings.notifyACExpired
        case .failure: return V3Strings.notifyFailure
        case .revertFailure: return V3Strings.notifyRevertFailure
        }
    }


    // MARK: Quit

    @objc func quit() {
        let s = snapshot()
        if StateMachine.quitNeedsConfirm(s) {
            let alert = NSAlert()
            alert.messageText = V3Strings.quitConfirm
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        logEvent("quit clicked (menu; Keep awake reverts)")
        guard execute(StateMachine.quitCleanup(), snapshot: s) else { return }
        unloadGuardAgent(removeFile: true)
        if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() }
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        NSApp.terminate(nil)
    }

    /// Fires on every NSApp.terminate path (menu quit, single-instance
    /// yield, guard-agent handoff). A missing exit line next to a later
    /// launch line is itself forensic signal: the process died without
    /// AppKit teardown — a crash or a kill.
    func applicationWillTerminate(_ notification: Notification) {
        logEvent("exit v\(Self.appVersion) (pid \(ProcessInfo.processInfo.processIdentifier))")
    }

    // MARK: Probes

    /// Puts the user's snapshotted Low Power Mode value back. J-07: the
    /// snapshot clears only after the write reports success AND a readback
    /// of the battery LPM setting matches — clearing it on a failed restore
    /// would orphan the user's original value with no way back. A kept
    /// snapshot retries on the next setLowPowerMode(false) effect (every
    /// Keep awake end and quitCleanup emits one).
    func restoreLowPowerMode() {
        guard let prior = state.priorLowPowerMode else { return }
        let writeStatus = power.writeBatteryLowPowerMode(prior)
        if writeStatus == 0, power.readBatteryLowPowerModeSetting() == prior {
            state.priorLowPowerMode = nil
        } else {
            appendLog("LPM restore NOT verified (pmset write status \(writeStatus)); snapshot kept")
        }
    }

    // MARK: Notifications & files

    func deliverNotification(body: String, bypassToggle: Bool = false) {
        if let notificationSink { notificationSink(body); return }
        guard bypassToggle || UserDefaults.standard.bool(forKey: "notifications") else { return }
        let content = UNMutableNotificationContent()
        content.title = V3Strings.appName
        content.body = body
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
    private func requestNotificationsIfNeeded() {
        guard UserDefaults.standard.bool(forKey: "notifications") else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    /// Tests point this at a scratch directory so log writes never touch
    /// the real ~/.lidawake state (the event log follows the same override).
    var stateDirectoryOverride: URL?
    private func stateDirectory() -> URL {
        stateDirectoryOverride
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".lidawake/state", isDirectory: true)
    }
    /// The v3.2 event log under ~/Library/Logs/LidAwake — the standard
    /// place a post-incident reader looks first (issue #5).
    var events: EventLog { EventLog(directory: stateDirectoryOverride ?? EventLog.defaultDirectory) }
    /// App-lifecycle and sleep/wake events: event log only.
    func logEvent(_ message: String) { events.append(message) }
    /// State-machine and pmset lines: both the event log and the legacy
    /// diagnostic trail in ~/.lidawake/state/lid-guard.log.
    func appendLog(_ message: String) {
        append("\(stamp()) \(message)\n", to: "lid-guard.log")
        events.append(message)
    }
    /// The launch forensics anchor: whatever else a session's log misses,
    /// every launch pins the live pmset truth (pmset -g parse) so the
    /// reader starts from a known SleepDisabled value.
    func logPmsetAnchor() {
        let sd = power.readSleepDisabled()
        logEvent("pmset anchor: SleepDisabled=\(sd.map { $0 ? "1" : "0" } ?? "unknown"), "
            + "power=\(label(power.powerSource())), battery=\(label(power.batteryPercent()))")
    }
    private func appendThermalHistory() { append("\(stamp()) thermal force-sleep\n", to: "thermal-history.txt") }
    private func append(_ text: String, to name: String) {
        let dir = stateDirectory(); try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        if let handle = try? FileHandle(forWritingTo: url) { _ = try? handle.seekToEnd(); try? handle.write(contentsOf: Data(text.utf8)); try? handle.close() }
        else { try? Data(text.utf8).write(to: url) }
    }
    private func stamp() -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f.string(from: Date()) }

    // MARK: Boot & permissions

    private func reconcileBoot() {
        let boot = Shell.run("/usr/sbin/sysctl", ["-n", "kern.boottime"]).1
        if let old = state.bootTime, old != boot {
            let s = snapshot()
            _ = execute(StateMachine.reboot(hadOneShot: state.oneShotActive), snapshot: s)
            state.priorLid = .unknown
            state.lastTickAt = nil
        }
        state.bootTime = boot
    }
}
@main
@MainActor
struct LidAwakeApp {
    static func main() {
        if CommandLine.arguments.dropFirst().contains("--guard-tick") {
            let delegate = AppDelegate(); delegate.runGuardTickHeadless(); return
        }
        let app = NSApplication.shared, delegate = AppDelegate()
        app.delegate = delegate; app.setActivationPolicy(.accessory); app.run()
    }
}
