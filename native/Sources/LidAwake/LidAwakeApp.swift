import AppKit
import Darwin
import Foundation
import LidAwakeCore
import ServiceManagement
import UserNotifications

private enum Shell {
    static func run(_ executable: String, _ arguments: [String]) -> (Int32, String) {
        let task = Process(), pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments; task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return (-1, "") }
        // Read to EOF BEFORE waitUntilExit: waiting first deadlocks forever
        // once the child fills the 64KB pipe buffer (launchctl list does on
        // agent-heavy Macs — v2's healthy-process-no-icon signature).
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
    static func pmset(_ args: [String], sudo: Bool = false) -> (Int32, String) {
        sudo ? run("/usr/bin/sudo", ["-n", "/usr/bin/pmset"] + args) : run("/usr/bin/pmset", args)
    }
}

private final class RuntimeState {
    private let d = UserDefaults.standard
    var oneShotActive: Bool { get { d.bool(forKey: "oneShotActive") } set { d.set(newValue, forKey: "oneShotActive") } }
    var acDeclined: Bool { get { d.bool(forKey: "acDeclined") } set { d.set(newValue, forKey: "acDeclined") } }
    var skipOnce: Bool { get { d.bool(forKey: "skipOnce") } set { d.set(newValue, forKey: "skipOnce") } }
    var alwaysPaused: Bool { get { d.bool(forKey: "alwaysPaused") } set { d.set(newValue, forKey: "alwaysPaused") } }
    var acHoldStart: Date? { get { d.object(forKey: "acHoldStart") as? Date } set { d.set(newValue, forKey: "acHoldStart") } }
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
private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private lazy var status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let state = RuntimeState()
    private var timer: Timer?
    private var permissionAlertShown = false
    private var activity: NSObjectProtocol?
    private var headless = false
    private var postmortemDisplayed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateStateDirectory()
        guard resolveSingleInstance() else { NSApp.terminate(nil); return }
        registerDefaults()
        migrateOldIdentifierDomain()
        migrateV2Defaults()
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
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated], reason: "Keep LidAwake safety state fresh")
        if !hasSudoRule() { showSudoFix() }
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
        ])
    }

    // One-time move of v2/v3 state from the retired hyphenated path. Runs
    // before anything logs so every write lands in ~/.lidawake. If both trees
    // exist (a partial earlier move) the old one is left for manual review.
    private func migrateStateDirectory() {
        let fm = FileManager.default, home = fm.homeDirectoryForCurrentUser
        let old = home.appendingPathComponent(".lid-awake")
        let new = home.appendingPathComponent(".lidawake")
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return }
        try? fm.moveItem(at: old, to: new)
    }

    // Bundle-identifier switch (spec: app.lidawake, old ids retired): carry
    // the stored policy over from the old defaults domain once, then delete
    // the old domain so nothing is left under the retired identifier.
    private func migrateOldIdentifierDomain() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "v3IdentifierMigrated") else { return }
        if let old = d.persistentDomain(forName: "com.nempyxaa.lid-awake") {
            for (key, value) in old { d.set(value, forKey: key) }
            d.removePersistentDomain(forName: "com.nempyxaa.lid-awake")
        }
        d.set(true, forKey: "v3IdentifierMigrated")
    }

    // v2 -> v3 defaults migration: "Ask each time" is removed (its rawValue 2
    // now means Always), the thermal checkbox is removed (the invariant is
    // always on), and a live v2 battery override carries over as a one-shot.
    private func migrateV2Defaults() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "v3Migrated") else { return }
        if d.object(forKey: "batteryMode") != nil && d.integer(forKey: "batteryMode") == 2 {
            d.set(BatteryMode.untilLidFloorHot.rawValue, forKey: "batteryMode")
        }
        if let thermalGuard = d.object(forKey: "thermalGuard") as? Bool, thermalGuard == false {
            deliverNotification(body: V3Strings.notifyOverheatInvariant, bypassToggle: true)
        }
        if d.bool(forKey: "batteryOverride") { state.oneShotActive = true }
        for legacy in ["thermalGuard", "batteryOverride", "batteryContract", "manualOff", "lastTick"] {
            d.removeObject(forKey: legacy)
        }
        d.set(true, forKey: "v3Migrated")
    }

    func menuWillOpen(_ menu: NSMenu) {
        postmortemDisplayed = state.postmortem != nil
        refreshMenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        // The postmortem line persists until the first menu open after the end.
        if postmortemDisplayed { state.postmortem = nil; postmortemDisplayed = false }
    }

    private var floor: Int { UserDefaults.standard.integer(forKey: "batteryFloor") }
    private var mode: BatteryMode { BatteryMode(rawValue: UserDefaults.standard.integer(forKey: "batteryMode")) ?? .untilLidFloorHot }

    private func snapshot() -> MachineSnapshot {
        let now = Date()
        let thermal = ProcessInfo.processInfo.thermalState.rawValue
        if thermal >= StateMachine.seriousThermal { state.lastHotAt = now }
        let thermalOK = state.lastHotAt.map { now.timeIntervalSince($0) } ?? 1_000_000_000
        return MachineSnapshot(
            power: powerSource(), previousPower: state.priorPower,
            batteryPercent: batteryPercent(),
            lid: lidState(), previousLid: state.priorLid,
            thermalState: thermal, thermalOKSeconds: thermalOK,
            sleepDisabled: sleepDisabled(),
            mode: mode, oneShotActive: state.oneShotActive,
            acDeclined: state.acDeclined, skipOnce: state.skipOnce,
            alwaysPaused: state.alwaysPaused,
            acHoldSeconds: state.acHoldStart.map { now.timeIntervalSince($0) },
            batteryFloor: floor)
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

    @objc private func armClicked() { act { StateMachine.arm($0) } }
    @objc private func declineClicked() { act { StateMachine.declineOnPower($0) } }
    @objc private func turnOffClicked() { act { StateMachine.turnOffOneShot($0) } }
    @objc private func skipOnceClicked() { act { StateMachine.toggleSkipOnce($0) } }
    @objc private func sleepNowClicked() { act { StateMachine.sleepNowAction($0) } }
    @objc private func turnOffAlwaysClicked() {
        let s = snapshot()
        guard execute(StateMachine.turnOffAlways(s), snapshot: s) else { refreshMenu(); return }
        UserDefaults.standard.set(BatteryMode.untilLidFloorHot.rawValue, forKey: "batteryMode")
        refreshMenu()
    }
    @objc private func setBatteryMode(_ sender: NSMenuItem) {
        guard let newMode = BatteryMode(rawValue: sender.tag) else { return }
        let s = snapshot()
        guard execute(StateMachine.modeChanged(s, to: newMode), snapshot: s) else { refreshMenu(); return }
        UserDefaults.standard.set(newMode.rawValue, forKey: "batteryMode")
        refreshMenu()
    }
    @objc private func setFloor(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: "batteryFloor")
        tick() // the resume predicate and every label recompute on floor change
    }
    @objc private func toggleNotifications() {
        let d = UserDefaults.standard, value = !d.bool(forKey: "notifications")
        d.set(value, forKey: "notifications")
        if value { requestNotificationsIfNeeded() }
        refreshMenu()
    }

    private func act(_ decide: (MachineSnapshot) -> Decision) {
        let s = snapshot()
        _ = execute(decide(s), snapshot: s)
        refreshMenu()
    }

    @objc private func systemWillSleep() {
        let s = snapshot()
        _ = execute(StateMachine.systemWillSleep(s), snapshot: s)
    }
    @objc private func systemDidWake() { tick() }

    // MARK: Effect executor

    @discardableResult private func execute(_ decision: Decision, snapshot s: MachineSnapshot) -> Bool {
        for effect in decision.effects {
            switch effect {
            case let .setSleepDisabled(value, verify):
                _ = Shell.pmset(["-a", "disablesleep", value ? "1" : "0"], sudo: true)
                if verify && sleepDisabled() != value {
                    appendLog(value ? "enable FAILED (pmset)" : "REVERT-VERIFY FAILED (SleepDisabled still 1)")
                    deliverNotification(body: value ? V3Strings.notifyFailure : V3Strings.notifyRevertFailure)
                    showSudoFix()
                    return false
                }
            case let .setLowPowerMode(value):
                _ = Shell.pmset(["-b", "lowpowermode", value ? "1" : "0"], sudo: true)
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
            case .sleepNow: _ = Shell.pmset(["sleepnow"], sudo: true)
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
        case .hotEnd: return V3Strings.notifyHotEnd
        case let .floorPaused(floor): return V3Strings.notifyFloorPaused(floor)
        case .hotPaused: return V3Strings.notifyHotPaused
        case .alwaysResumed: return V3Strings.notifyAlwaysResumed
        case .acExpired: return V3Strings.notifyACExpired
        case .failure: return V3Strings.notifyFailure
        case .revertFailure: return V3Strings.notifyRevertFailure
        }
    }

    // MARK: Menu

    private func refreshMenu() {
        guard !headless else { return }
        let s = snapshot(), menu = status.menu ?? NSMenu()
        menu.removeAllItems()
        status.button?.image = icon(for: s)

        if let line = state.postmortem { add(line, enabled: false, to: menu) }

        if s.power == .ac {
            if s.oneShotActive { buildACHoldMenu(s, menu) } else { buildACIdleMenu(s, menu) }
        } else if s.mode == .always {
            if s.alwaysPaused { buildAlwaysPausedMenu(s, menu) } else { buildAlwaysActiveMenu(s, menu) }
        } else if s.oneShotActive {
            buildOneShotArmedMenu(s, menu)
        } else {
            buildIdleMenu(s, menu)
        }

        menu.addItem(.separator())
        menu.addItem(settingsItem(s))
        status.menu = menu
    }

    private func buildIdleMenu(_ s: MachineSnapshot, _ menu: NSMenu) {
        add(V3Strings.idleHeader, image: "moon.zzz.fill", enabled: false, to: menu)
        add(V3Strings.battery(s.batteryPercent), enabled: false, to: menu)
        menu.addItem(.separator())
        // Spec: arming is disabled only at/below the floor or while hot; the
        // resume predicate gates resumption, not arming.
        let floorHit = StateMachine.floorHit(percent: s.batteryPercent, floor: s.batteryFloor)
        let hot = s.thermalState >= StateMachine.seriousThermal
        let ready = !floorHit && !hot
        let arm = add(V3Strings.armItem, image: "cup.and.saucer.fill",
                      action: ready ? #selector(armClicked) : nil, enabled: ready, to: menu)
        let contract = s.mode == .ignoringLid
            ? V3Strings.armSubIgnoringLid(s.batteryFloor)
            : V3Strings.armSubUntilLid(s.batteryFloor)
        if ready {
            arm.subtitle = contract + "\n" + V3Strings.armSubChangeMode
        } else {
            // Disabled with the reason as the subtitle.
            arm.subtitle = floorHit ? V3Strings.armDisabledLow(s.batteryFloor) : V3Strings.armDisabledHot
        }
        add(V3Strings.sleepNow, image: "zzz", action: #selector(sleepNowClicked), to: menu)
    }

    private func buildOneShotArmedMenu(_ s: MachineSnapshot, _ menu: NSMenu) {
        add(V3Strings.oneShotHeader, image: "cup.and.saucer.fill", enabled: false, to: menu)
        add(s.mode == .ignoringLid ? V3Strings.untilOneShotIgnoringLid(s.batteryFloor)
                                   : V3Strings.untilOneShotLid(s.batteryFloor),
            enabled: false, to: menu)
        add(V3Strings.battery(s.batteryPercent), enabled: false, to: menu)
        menu.addItem(.separator())
        add(V3Strings.turnOff, image: "moon.zzz.fill", action: #selector(turnOffClicked), to: menu)
        let sleep = add(V3Strings.sleepNow, image: "zzz", action: #selector(sleepNowClicked), to: menu)
        sleep.subtitle = V3Strings.sleepNowSubOneShot
    }

    private func buildAlwaysActiveMenu(_ s: MachineSnapshot, _ menu: NSMenu) {
        add(V3Strings.alwaysHeader, image: "cup.and.saucer.fill", enabled: false, to: menu)
        add(V3Strings.alwaysUntil(s.batteryFloor), enabled: false, to: menu)
        add(V3Strings.battery(s.batteryPercent), enabled: false, to: menu)
        menu.addItem(.separator())
        if s.skipOnce {
            add(V3Strings.skipOnceArmedItem, image: "moon.zzz.fill", action: #selector(skipOnceClicked), to: menu)
        } else {
            let skip = add(V3Strings.skipOnceItem, image: "moon.zzz.fill", action: #selector(skipOnceClicked), to: menu)
            skip.subtitle = V3Strings.skipOnceSub
        }
        let off = add(V3Strings.turnOffAlwaysItem, action: #selector(turnOffAlwaysClicked), to: menu)
        off.subtitle = V3Strings.turnOffAlwaysSub
        add(V3Strings.sleepNow, image: "zzz", action: #selector(sleepNowClicked), to: menu)
    }

    private func buildAlwaysPausedMenu(_ s: MachineSnapshot, _ menu: NSMenu) {
        add(V3Strings.idleHeader, image: "moon.zzz.fill", enabled: false, to: menu)
        // The cooling line shows only when thermals are the actual blocker.
        add(StateMachine.pauseBlockedByHeatOnly(s) ? V3Strings.pausedHot
                                                   : V3Strings.pausedFloor(s.batteryFloor),
            enabled: false, to: menu)
        add(V3Strings.battery(s.batteryPercent), enabled: false, to: menu)
        menu.addItem(.separator())
        let off = add(V3Strings.turnOffAlwaysItem, action: #selector(turnOffAlwaysClicked), to: menu)
        off.subtitle = V3Strings.turnOffAlwaysSub
        add(V3Strings.sleepNow, image: "zzz", action: #selector(sleepNowClicked), to: menu)
    }

    private func buildACIdleMenu(_ s: MachineSnapshot, _ menu: NSMenu) {
        add(s.acDeclined ? V3Strings.acHeaderDeclined : V3Strings.acHeaderOn,
            image: s.acDeclined ? "moon.zzz.fill" : "cup.and.saucer.fill", enabled: false, to: menu)
        add(V3Strings.batteryCharging(s.batteryPercent), enabled: false, to: menu)
        menu.addItem(.separator())
        let arm = add(V3Strings.armItem, image: "cup.and.saucer.fill",
                      action: s.acDeclined ? #selector(armClicked) : nil,
                      enabled: s.acDeclined, to: menu)
        arm.subtitle = V3Strings.armSubOnPower
        if !s.acDeclined {
            // The moon: clicking it declines automatic on-power Keep awake.
            add(V3Strings.turnOff, image: "moon.zzz.fill", action: #selector(declineClicked), to: menu)
        }
        add(V3Strings.sleepNow, image: "zzz", action: #selector(sleepNowClicked), to: menu)
    }

    private func buildACHoldMenu(_ s: MachineSnapshot, _ menu: NSMenu) {
        add(V3Strings.acHoldHeader, image: "bolt.fill", enabled: false, to: menu)
        add(s.mode == .ignoringLid ? V3Strings.untilOneShotIgnoringLid(s.batteryFloor)
                                   : V3Strings.untilOneShotLid(s.batteryFloor),
            enabled: false, to: menu)
        add(V3Strings.batteryCharging(s.batteryPercent), enabled: false, to: menu)
        menu.addItem(.separator())
        add(V3Strings.turnOff, image: "moon.zzz.fill", action: #selector(turnOffClicked), to: menu)
        add(V3Strings.sleepNow, image: "zzz", action: #selector(sleepNowClicked), to: menu)
    }

    private func settingsItem(_ s: MachineSnapshot) -> NSMenuItem {
        let settings = NSMenuItem(title: V3Strings.settings, action: nil, keyEquivalent: "")
        settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        let submenu = NSMenu()

        let notifications = add(V3Strings.showNotifications, action: #selector(toggleNotifications), to: submenu)
        notifications.state = UserDefaults.standard.bool(forKey: "notifications") ? .on : .off

        let floorItem = NSMenuItem(title: V3Strings.floorItem(floor), action: nil, keyEquivalent: "")
        floorItem.image = NSImage(systemSymbolName: "battery.25", accessibilityDescription: nil)
        let floors = NSMenu()
        let keepAwakeLive = s.power == .battery &&
            (s.oneShotActive || (s.mode == .always && !s.alwaysPaused))
        for value in [10, 15, 20, 25, 30] {
            let endsCurrent = keepAwakeLive && (s.batteryPercent ?? 0) <= value
            let item = NSMenuItem(title: endsCurrent ? V3Strings.floorOptionEndsCurrent(value)
                                                     : V3Strings.floorOption(value),
                                  action: #selector(setFloor(_:)), keyEquivalent: "")
            item.target = self; item.tag = value; item.state = value == floor ? .on : .off
            floors.addItem(item)
        }
        floorItem.submenu = floors; submenu.addItem(floorItem)

        submenu.addItem(.separator())
        let header = add(V3Strings.modeSection, enabled: false, to: submenu)
        header.attributedTitle = NSAttributedString(
            string: V3Strings.modeSection,
            attributes: [.font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)])
        let radios: [(BatteryMode, String)] = [
            (.untilLidFloorHot, V3Strings.modeRadioUntilLid(floor)),
            (.ignoringLid, V3Strings.modeRadioIgnoringLid(floor)),
            (.always, V3Strings.modeRadioAlways(floor)),
        ]
        for (radioMode, title) in radios {
            let item = add(title, action: #selector(setBatteryMode(_:)), to: submenu)
            item.tag = radioMode.rawValue
            item.state = radioMode == mode ? .on : .off
        }
        submenu.addItem(.separator())
        add(V3Strings.about, action: #selector(showAbout), to: submenu)
        add(V3Strings.quit, action: #selector(quit), to: submenu)
        settings.submenu = submenu
        return settings
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @discardableResult private func add(_ title: String, image: String? = nil, action: Selector? = nil,
                                        enabled: Bool = true, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; item.isEnabled = enabled
        if let image { item.image = NSImage(systemSymbolName: image, accessibilityDescription: nil) }
        menu.addItem(item); return item
    }

    // Template icon states: outline = next close sleeps, filled = next close
    // Keep awake, filled with a slash = selected but paused.
    private func icon(for s: MachineSnapshot) -> NSImage? {
        let paused = s.power == .battery && s.mode == .always && s.alwaysPaused
        let awakeOnClose: Bool
        if s.power == .ac {
            awakeOnClose = !s.acDeclined || s.oneShotActive
        } else if s.mode == .always {
            awakeOnClose = !s.alwaysPaused && !s.skipOnce
        } else {
            awakeOnClose = s.oneShotActive
        }
        let base = NSImage(systemSymbolName: awakeOnClose || paused ? "cup.and.saucer.fill" : "cup.and.saucer",
                           accessibilityDescription: V3Strings.appName)
        guard paused, let filled = base else { base?.isTemplate = true; return base }
        let size = filled.size
        let slashed = NSImage(size: size, flipped: false) { rect in
            filled.draw(in: rect)
            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: rect.minX + 1, y: rect.minY + 1))
            slash.line(to: NSPoint(x: rect.maxX - 1, y: rect.maxY - 1))
            slash.lineWidth = 1.5
            NSColor.black.setStroke()
            slash.stroke()
            return true
        }
        slashed.isTemplate = true
        return slashed
    }

    // MARK: Quit

    @objc private func quit() {
        let s = snapshot()
        if StateMachine.quitNeedsConfirm(s) {
            let alert = NSAlert()
            alert.messageText = V3Strings.quitConfirm
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        guard execute(StateMachine.quitCleanup(), snapshot: s) else { return }
        unloadGuardAgent(removeFile: true)
        if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() }
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        NSApp.terminate(nil)
    }

    // MARK: Probes

    private func sleepDisabled() -> Bool {
        let output = Shell.pmset(["-g"]).1
        guard let line = output.split(separator: "\n").first(where: { $0.contains("SleepDisabled") }) else { return false }
        return line.split(whereSeparator: \.isWhitespace).last == "1"
    }
    private func powerSource() -> PowerSource { Shell.pmset(["-g", "ps"]).1.contains("AC Power") ? .ac : .battery }
    private func batteryPercent() -> Int? {
        let text = Shell.pmset(["-g", "batt"]).1
        guard let range = text.range(of: #"[0-9]+%"#, options: .regularExpression) else { return nil }
        return Int(text[range].dropLast())
    }
    private func lidState() -> LidState {
        let text = Shell.run("/usr/sbin/ioreg", ["-r", "-k", "AppleClamshellState", "-d", "1"]).1
        if text.contains("AppleClamshellState\" = Yes") { return .closed }
        if text.contains("AppleClamshellState\" = No") { return .open }
        return .unknown
    }

    // MARK: Notifications & files

    private func deliverNotification(body: String, bypassToggle: Bool = false) {
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
    private func stateDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".lidawake/state", isDirectory: true)
    }
    private func appendLog(_ message: String) { append("\(stamp()) \(message)\n", to: "lid-guard.log") }
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
    private var sudoersLine: String {
        "\(NSUserName()) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -b lowpowermode 0, /usr/bin/pmset -b lowpowermode 1, /usr/bin/pmset sleepnow"
    }
    private func hasSudoRule() -> Bool {
        Shell.run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "0"]).0 == 0
    }
    private func showSudoFix() {
        guard !headless, !permissionAlertShown else { return }
        permissionAlertShown = true
        let alert = NSAlert()
        alert.messageText = "LidAwake needs permission to run pmset"
        alert.informativeText = "Run: sudo visudo -f /etc/sudoers.d/lidawake\nThen add this line:\n\(sudoersLine)"
        alert.addButton(withTitle: "Copy fix"); alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(sudoersLine, forType: .string)
        }
    }

    // MARK: Single instance & persistent services

    // One instance owns the state. A running v2 (lid-awake.app) is retired so
    // the v3 upgrade can proceed; a running v3 peer wins over this instance.
    private func resolveSingleInstance() -> Bool {
        let peers = NSRunningApplication
            .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "app.lidawake")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }
        var ok = true
        for peer in peers {
            if peer.bundleURL?.lastPathComponent == "lid-awake.app" {
                peer.forceTerminate()
                appendLog("terminated running v2 instance for migration")
            } else {
                ok = false
            }
        }
        return ok
    }

    private var runsFromApplications: Bool {
        Bundle.main.bundleURL.standardizedFileURL.path.hasPrefix("/Applications/")
    }
    nonisolated private var guardPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/app.lidawake.guard.plist")
    }
    private func configurePersistentServices() {
        guard runsFromApplications else {
            let alert = NSAlert()
            alert.messageText = "Move LidAwake to Applications"
            alert.informativeText = "The safety watchdog is enabled only from /Applications. Move the app there, then open it again."
            alert.addButton(withTitle: "OK"); alert.runModal()
            appendLog("persistent services refused outside /Applications"); return
        }
        migrateLegacyInstall()
        removeOldBundle()
        installGuardAgentIfNeeded()
        // v3 uses the KeepAlive LaunchAgent (RunAtLoad covers login); retire
        // any v2 login item so only one launcher owns the app.
        if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() }
    }

    // The v2 bundle was lid-awake.app — a different APFS entry from
    // LidAwake.app — and must be deleted on migration.
    private func removeOldBundle() {
        let old = URL(fileURLWithPath: "/Applications/lid-awake.app")
        guard FileManager.default.fileExists(atPath: old.path),
              old.path != Bundle.main.bundleURL.standardizedFileURL.path else { return }
        do {
            try FileManager.default.removeItem(at: old)
            appendLog("migration removed \(old.path)")
        } catch {
            appendLog("migration could not remove \(old.path): \(error.localizedDescription)")
        }
    }

    // The KeepAlive watchdog: launchd starts the app at login and relaunches
    // it after a crash; a clean exit (Quit, or yielding to a peer) stays down.
    private var guardPlistContent: [String: Any] {
        ["Label": "app.lidawake.guard",
         "ProgramArguments": [Bundle.main.executableURL?.path ?? ""],
         "RunAtLoad": true,
         "KeepAlive": ["SuccessfulExit": false]]
    }
    private func installGuardAgentIfNeeded() {
        let desired = guardPlistContent
        if let data = try? Data(contentsOf: guardPlistURL),
           let existing = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
           NSDictionary(dictionary: existing).isEqual(to: desired),
           Shell.run("/bin/launchctl", ["print", "gui/\(getuid())/app.lidawake.guard"]).0 == 0 {
            return // already installed and loaded; never bootout our own job
        }
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: desired, format: .xml, options: 0)
            try FileManager.default.createDirectory(at: guardPlistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let domain = "gui/\(getuid())"
            _ = Shell.run("/bin/launchctl", ["bootout", domain + "/app.lidawake.guard"])
            try data.write(to: guardPlistURL, options: .atomic)
            let result = Shell.run("/bin/launchctl", ["bootstrap", domain, guardPlistURL.path])
            if result.0 != 0 { appendLog("guard LaunchAgent bootstrap failed") }
        } catch { appendLog("guard LaunchAgent install failed: \(error.localizedDescription)") }
    }
    private func unloadGuardAgent(removeFile: Bool) {
        _ = Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())/app.lidawake.guard"])
        if removeFile { try? FileManager.default.removeItem(at: guardPlistURL) }
    }

    // v1/v2/old-identifier migration. Runs on every launch and works by
    // enumeration, never by expected names alone: the 2026-08 incident left
    // lv.fleet.lidguard and lid.10s.sh running in parallel with v2 because
    // the old code only looked for the names it had installed itself. The
    // bundle-id switch to app.lidawake retires com.nempyxaa.lid-awake.* too.
    nonisolated private var legacyAgentNames: Set<String> {
        ["org.lidawake.guard.plist", "lv.fleet.lidguard.plist", "com.nempyxaa.lid-awake.guard.plist"]
    }
    nonisolated private var legacyPluginNames: Set<String> { ["lidawake.10s.sh", "lid.10s.sh"] }
    private var legacyScriptNames: [String] { ["lid-battery-guard.sh", "lid-toggle.sh", "lid-settings.sh", "lidawake.10s.sh", "thermalstate"] }
    // Tokens that appear in legacy launchd labels — v1's, and the retired
    // com.nempyxaa.lid-awake.* labels. The remnant check first drops every
    // line carrying the CURRENT identifier ("app.lidawake" — the guard label
    // and the running app's application.app.lidawake.* entries), so these
    // tokens cannot match the new agent; bystanders like
    // com.apple.ATS.FontValidator never matched either way.
    nonisolated private var legacyLaunchdTokens: [String] { ["lidawake", "lidguard", "lid-guard", "lid-awake", "lv.fleet.lid"] }

    nonisolated private func listDirectory(_ dir: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    }
    nonisolated private func isLegacyAgentPlist(_ url: URL) -> Bool {
        guard url.pathExtension == "plist", url.lastPathComponent != guardPlistURL.lastPathComponent else { return false }
        if legacyAgentNames.contains(url.lastPathComponent) { return true }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return content.contains("lid-battery-guard") || content.contains("lidawake")
            || content.contains(".lid-awake/") || content.contains("com.nempyxaa.lid-awake")
    }
    // Content match keys on the v1 action scripts, not on ".lid-awake": a
    // user-authored plugin that merely displays state must survive.
    nonisolated private func isLegacyPlugin(_ url: URL) -> Bool {
        if legacyPluginNames.contains(url.lastPathComponent) { return true }
        guard url.pathExtension == "sh", let content = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return content.contains("lid-toggle") || content.contains("lid-battery-guard")
    }
    nonisolated private func swiftBarPluginDirectories() -> [URL] {
        let fm = FileManager.default
        var dirs: [URL] = []
        let configured = Shell.run("/usr/bin/defaults", ["read", "com.ameba.SwiftBar", "PluginDirectory"]).1
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty { dirs.append(URL(fileURLWithPath: (configured as NSString).expandingTildeInPath)) }
        let legacy = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/swiftbar-plugins")
        if !dirs.contains(where: { $0.standardizedFileURL.path == legacy.standardizedFileURL.path }) { dirs.append(legacy) }
        return dirs.filter { fm.fileExists(atPath: $0.path) }
    }
    private func backUp(_ url: URL, to dir: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var destination = dir.appendingPathComponent(url.lastPathComponent)
        var counter = 2
        while fm.fileExists(atPath: destination.path) {
            destination = dir.appendingPathComponent("\(url.lastPathComponent).\(counter)"); counter += 1
        }
        try? fm.copyItem(at: url, to: destination)
    }
    private func removeLegacyFile(_ url: URL, backupDir: URL, removed: inout [String]) {
        backUp(url, to: backupDir)
        try? FileManager.default.removeItem(at: url)
        if !FileManager.default.fileExists(atPath: url.path) { removed.append(url.path) }
    }

    private func migrateLegacyInstall() {
        let fm = FileManager.default, home = fm.homeDirectoryForCurrentUser
        let stampFormatter = DateFormatter(); stampFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let backupDir = home.appendingPathComponent(".lidawake/backups/v1-migration-\(stampFormatter.string(from: Date()))")
        var removed: [String] = []

        // 1. LaunchAgents: enumerate the directory, bootout by label and by
        // path, back up, remove — and take the guard script each agent ran.
        for plist in listDirectory(home.appendingPathComponent("Library/LaunchAgents")) where isLegacyAgentPlist(plist) {
            let dict = (try? Data(contentsOf: plist))
                .flatMap { try? PropertyListSerialization.propertyList(from: $0, options: [], format: nil) } as? [String: Any]
            let label = dict?["Label"] as? String ?? plist.deletingPathExtension().lastPathComponent
            _ = Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
            _ = Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())", plist.path])
            removeLegacyFile(plist, backupDir: backupDir, removed: &removed)
            for argument in dict?["ProgramArguments"] as? [String] ?? [] where argument.contains("lid-battery-guard") {
                let script = URL(fileURLWithPath: argument)
                if fm.fileExists(atPath: script.path) { removeLegacyFile(script, backupDir: backupDir, removed: &removed) }
            }
        }

        // 2. SwiftBar plugins: enumerate the configured plugin directory and
        // the known legacy one; match by exact name or plugin content.
        for dir in swiftBarPluginDirectories() {
            for plugin in listDirectory(dir) where isLegacyPlugin(plugin) {
                removeLegacyFile(plugin, backupDir: backupDir, removed: &removed)
            }
        }

        // 3. Known v1 script locations that nothing enumerable points at
        // anymore — the moved state dir, plus the old path in case the
        // one-time move was blocked.
        for dir in [home.appendingPathComponent(".claude/hooks"),
                    home.appendingPathComponent(".lidawake"),
                    home.appendingPathComponent(".lid-awake")] {
            for name in legacyScriptNames {
                let file = dir.appendingPathComponent(name)
                if fm.fileExists(atPath: file.path) { removeLegacyFile(file, backupDir: backupDir, removed: &removed) }
            }
        }

        // 4. A guard mid-run survives its agent's bootout; kill it.
        _ = Shell.run("/usr/bin/pkill", ["-f", "lid-battery-guard"])

        for path in removed { appendLog("migration removed \(path) (backup: \(backupDir.path))") }
        // The remnant verification shells out to `launchctl list`, whose
        // output can be large on agent-heavy Macs. It must never run on the
        // pre-icon critical path (or the main thread at all) — the sweep is
        // diagnostic only and retries on the next launch anyway.
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let remnants = self.legacyRemnants()
            guard !remnants.isEmpty else { return }
            await MainActor.run {
                for remnant in remnants { self.appendLog("migration VERIFY FAILED: \(remnant)") }
            }
        }
        if !removed.isEmpty && !headless {
            let alert = NSAlert()
            alert.messageText = "Old version removed"
            alert.informativeText = "The old background pieces were removed."
            alert.addButton(withTitle: "OK"); alert.runModal()
        }
    }

    // Post-migration verification by enumeration of live state, not expected
    // names: loaded launchd jobs, LaunchAgent plists, every SwiftBar plugin
    // directory, and running processes. Failures are logged and the sweep
    // retries on the next launch.
    nonisolated private func legacyRemnants() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var remnants: [String] = []
        // Drop every line carrying the current identifier first: the new
        // guard label and the running app's own application.app.lidawake.*
        // entries contain "lidawake" and must not read as remnants.
        let jobs = Shell.run("/bin/launchctl", ["list"]).1.lowercased()
            .split(separator: "\n")
            .filter { !$0.contains("app.lidawake") }
            .joined(separator: "\n")
        for token in legacyLaunchdTokens where jobs.contains(token) {
            remnants.append("launchctl list still shows a job matching '\(token)'")
        }
        for plist in listDirectory(home.appendingPathComponent("Library/LaunchAgents")) where isLegacyAgentPlist(plist) {
            remnants.append("LaunchAgent remains: \(plist.path)")
        }
        for dir in swiftBarPluginDirectories() {
            for plugin in listDirectory(dir) where isLegacyPlugin(plugin) {
                remnants.append("SwiftBar plugin remains: \(plugin.path)")
            }
        }
        if Shell.run("/usr/bin/pgrep", ["-f", "lid-battery-guard"]).0 == 0 {
            remnants.append("a legacy guard process is still running")
        }
        return remnants
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
