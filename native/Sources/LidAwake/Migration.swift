import AppKit
import Darwin
import Foundation
import LidAwakeCore

@MainActor
extension AppDelegate {
// One-time move of v2/v3 state from the retired hyphenated path. Runs
// before anything logs so every write lands in ~/.lidawake. If both trees
// exist (a partial earlier move) the old one is left for manual review.
func migrateStateDirectory() {
    let fm = FileManager.default, home = fm.homeDirectoryForCurrentUser
    let old = home.appendingPathComponent(".lid-awake")
    let new = home.appendingPathComponent(".lidawake")
    guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return }
    try? fm.moveItem(at: old, to: new)
}

// Bundle-identifier switch (spec: app.lidawake, old ids retired): carry
// the stored policy over from the old defaults domain once, then delete
// the old domain so nothing is left under the retired identifier.
func migrateOldIdentifierDomain() {
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
func migrateV2Defaults() {
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

func removeOldBundle() {
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
enum LegacyPlistMatch: Equatable { case known, mentionOnly, none }

/// Labels the v1/v2 installers actually wrote.
nonisolated private var legacyAgentLabels: Set<String> {
    ["org.lidawake.guard", "lv.fleet.lidguard", "com.nempyxaa.lid-awake.guard"]
}
/// Payload fragments only our own legacy agents ever pointed at.
nonisolated private var legacyAgentPayloads: [String] {
    ["lid-battery-guard", "lidawake.10s.sh", "lid.10s.sh", "/.lid-awake/",
     "/Applications/lid-awake.app"]
}

/// J-08: removable means a KNOWN label/payload shape — an exact legacy
/// filename, a Label the old installers wrote, or a Program(Arguments)
/// pointing at our own legacy payloads. A plist that merely mentions the
/// app somewhere in its content (a third-party automation, say) is
/// `.mentionOnly`: reported to the user and left in place, never deleted.
nonisolated func classifyLegacyAgentPlist(_ url: URL) -> LegacyPlistMatch {
    guard url.pathExtension == "plist",
          url.lastPathComponent != guardPlistURL.lastPathComponent else { return .none }
    if legacyAgentNames.contains(url.lastPathComponent) { return .known }
    let dict = (try? Data(contentsOf: url)).flatMap {
        try? PropertyListSerialization.propertyList(from: $0, options: [], format: nil)
    } as? [String: Any]
    if let label = dict?["Label"] as? String, legacyAgentLabels.contains(label) { return .known }
    let payload = (((dict?["ProgramArguments"] as? [String]) ?? [])
        + [(dict?["Program"] as? String) ?? ""]).joined(separator: " ")
    for known in legacyAgentPayloads where payload.contains(known) { return .known }
    guard let content = try? String(contentsOf: url, encoding: .utf8) else { return .none }
    if content.contains("lid-battery-guard") || content.contains("lidawake")
        || content.contains(".lid-awake/") || content.contains("com.nempyxaa.lid-awake") {
        return .mentionOnly
    }
    return .none
}

nonisolated private func isLegacyAgentPlist(_ url: URL) -> Bool {
    classifyLegacyAgentPlist(url) == .known
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
/// Copies url into dir and verifies the copy byte-compares equal to the
/// original. False when the backup could not be made or verified.
private func verifiedBackUp(_ url: URL, to dir: URL) -> Bool {
    let fm = FileManager.default
    do {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var destination = dir.appendingPathComponent(url.lastPathComponent)
        var counter = 2
        while fm.fileExists(atPath: destination.path) {
            destination = dir.appendingPathComponent("\(url.lastPathComponent).\(counter)"); counter += 1
        }
        try fm.copyItem(at: url, to: destination)
        return fm.contentsEqual(atPath: url.path, andPath: destination.path)
    } catch { return false }
}
func removeLegacyFile(_ url: URL, backupDir: URL, removed: inout [String]) {
    // J-08: a verified backup is a PRECONDITION of deletion — the README
    // promises every removed file is saved first. No backup, no removal.
    guard verifiedBackUp(url, to: backupDir) else {
        appendLog("migration KEPT \(url.path): backup could not be made and verified")
        return
    }
    try? FileManager.default.removeItem(at: url)
    if !FileManager.default.fileExists(atPath: url.path) { removed.append(url.path) }
}

func migrateLegacyInstall() {
    let fm = FileManager.default, home = fm.homeDirectoryForCurrentUser
    let stampFormatter = DateFormatter(); stampFormatter.dateFormat = "yyyyMMdd-HHmmss"
    let backupDir = home.appendingPathComponent(".lidawake/backups/v1-migration-\(stampFormatter.string(from: Date()))")
    var removed: [String] = []

    // 1. LaunchAgents: enumerate the directory, bootout by label and by
    // path, back up, remove — and take the guard script each agent ran.
    // Only KNOWN legacy shapes are removed; a plist that merely mentions
    // the app is reported and left alone (J-08).
    for plist in listDirectory(home.appendingPathComponent("Library/LaunchAgents")) {
        switch classifyLegacyAgentPlist(plist) {
        case .none: continue
        case .mentionOnly:
            appendLog("migration left \(plist.path) in place: mentions the app but matches no known legacy shape — review it manually")
            continue
        case .known: break
        }
        let dict = (try? Data(contentsOf: plist))
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, options: [], format: nil) } as? [String: Any]
        let label = dict?["Label"] as? String ?? plist.deletingPathExtension().lastPathComponent
        launchd.bootout("gui/\(getuid())/\(label)")
        launchd.bootout(domain: "gui/\(getuid())", plistPath: plist.path)
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
