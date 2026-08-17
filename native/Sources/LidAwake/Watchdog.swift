import AppKit
import Darwin
import Foundation
import ServiceManagement

enum Shell {
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

@MainActor
extension AppDelegate {
/// Every privileged pmset command form the app runs. The sudoers rule,
/// the startup validation, and the repair line must all cover exactly
/// this set — J-07: probing a single form let a partial rule (four of
/// five commands) look healthy until the missing one failed at runtime.
nonisolated static let privilegedCommandForms: [[String]] = [
    ["-a", "disablesleep", "0"], ["-a", "disablesleep", "1"],
    ["-b", "lowpowermode", "0"], ["-b", "lowpowermode", "1"],
    ["sleepnow"],
]
private var sudoersLine: String {
    "\(NSUserName()) ALL=(root) NOPASSWD: " + Self.privilegedCommandForms
        .map { "/usr/bin/pmset " + $0.joined(separator: " ") }
        .joined(separator: ", ")
}
/// The command forms sudo -l refuses to run passwordless right now.
func missingSudoForms() -> [[String]] {
    Self.privilegedCommandForms.filter {
        Shell.run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset"] + $0).0 != 0
    }
}
func hasSudoRule() -> Bool { missingSudoForms().isEmpty }
func showSudoFix() {
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

// One instance owns the state. A running v2 is retired so the v3 upgrade
// can proceed; a running v3 peer wins over this instance.
func resolveSingleInstance() -> Bool {
    // v2's bundle id is com.nempyxaa.lid-awake — enumerating only the
    // current id can never see it, and a surviving v2 keeps writing its
    // own pmset policy against ours. Terminate it BEFORE the migration
    // deletes its bundle out from under it.
    for old in NSRunningApplication.runningApplications(withBundleIdentifier: "com.nempyxaa.lid-awake")
    where !old.isTerminated {
        old.forceTerminate()
        appendLog("terminated running v2 instance (com.nempyxaa.lid-awake) for migration")
    }
    let selfPID = ProcessInfo.processInfo.processIdentifier
    let peers = NSRunningApplication
        .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "app.lidawake")
        .filter { $0.processIdentifier != selfPID && !$0.isTerminated }
    guard !peers.isEmpty else { return true }
    // v3 peers: the launchd-owned instance wins (it is the supervised
    // one — yielding to a manual instance would leave the survivor
    // unwatched); with no launchd owner among us, the lowest PID wins,
    // so two racing fresh instances can never both exit.
    let guardPID = guardJobPID()
    var ok = true
    for peer in peers {
        if peer.bundleURL?.lastPathComponent == "lid-awake.app" {
            peer.forceTerminate()
            appendLog("terminated running v2 instance for migration")
        } else if guardPID == selfPID {
            continue // we are launchd's instance; the peer will yield
        } else if guardPID == peer.processIdentifier {
            appendLog("yielding to the launchd-owned instance (pid \(peer.processIdentifier))")
            ok = false
        } else if selfPID > peer.processIdentifier {
            appendLog("yielding to the lower-PID instance (pid \(peer.processIdentifier))")
            ok = false
        }
    }
    return ok
}

/// PID of the process launchd currently runs for the guard job, if any.
private func guardJobPID() -> Int32? {
    let output = launchd.printJob("gui/\(getuid())/app.lidawake.guard").1
    for line in output.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("pid = ") {
            return Int32(trimmed.dropFirst("pid = ".count).trimmingCharacters(in: .whitespaces))
        }
    }
    return nil
}

private var runsFromApplications: Bool {
    Bundle.main.bundleURL.standardizedFileURL.path.hasPrefix("/Applications/")
}
nonisolated var guardPlistURL: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/app.lidawake.guard.plist")
}
func configurePersistentServices() {
    guard runsFromApplications else {
        let alert = NSAlert()
        alert.messageText = "Move LidAwake to Applications"
        alert.informativeText = "The safety watchdog is enabled only from /Applications. Move the app there, then open it again."
        alert.addButton(withTitle: "OK"); alert.runModal()
        appendLog("persistent services refused outside /Applications"); return
    }
    migrateLegacyInstall()
    removeOldBundle()
    // v3 uses the KeepAlive LaunchAgent (RunAtLoad covers login); retire
    // any v2 login item so only one launcher owns the app. This runs
    // before the guard install because a fresh bootstrap hands off to
    // the launchd-owned instance and terminates this one.
    if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() }
    installGuardAgentIfNeeded()
}

// The v2 bundle was lid-awake.app — a different APFS entry from
// LidAwake.app — and must be deleted on migration.
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
       launchd.printJob("gui/\(getuid())/app.lidawake.guard").0 == 0 {
        return // already installed and loaded; never bootout our own job
    }
    do {
        let data = try PropertyListSerialization.data(fromPropertyList: desired, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: guardPlistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let domain = "gui/\(getuid())"
        launchd.bootout(domain + "/app.lidawake.guard")
        try data.write(to: guardPlistURL, options: .atomic)
        let bootstrapStatus = launchd.bootstrap(domain: domain, plistPath: guardPlistURL.path)
        guard bootstrapStatus == 0 else { appendLog("guard LaunchAgent bootstrap failed"); return }
        // Hand the session to the launchd-owned instance: kickstart the
        // job (RunAtLoad usually already started it) and, when this
        // process is not the one launchd runs, exit cleanly. Staying
        // alive would leave THIS instance unsupervised — launchd's
        // duplicate yields in resolveSingleInstance and the KeepAlive
        // job then sits dormant until the next login.
        launchd.kickstart(domain + "/app.lidawake.guard")
        if guardJobPID() != ProcessInfo.processInfo.processIdentifier {
            appendLog("guard agent bootstrapped; handing off to the launchd-owned instance")
            NSApp.terminate(nil)
        }
    } catch { appendLog("guard LaunchAgent install failed: \(error.localizedDescription)") }
}
func unloadGuardAgent(removeFile: Bool) {
    launchd.bootout("gui/\(getuid())/app.lidawake.guard")
    if removeFile { try? FileManager.default.removeItem(at: guardPlistURL) }
}

}
