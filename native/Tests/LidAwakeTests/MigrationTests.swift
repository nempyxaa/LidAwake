import Foundation
import Testing
@testable import LidAwake

// J-08: the legacy sweep may only DELETE known label/payload shapes, and
// only after a verified backup exists. Everything else is reported.

@MainActor
private func makeDelegate(stateDir: URL) -> AppDelegate {
    let delegate = AppDelegate()
    delegate.headless = true
    delegate.stateDirectoryOverride = stateDir
    return delegate
}

private func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("lidawake-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func writePlist(_ dict: [String: Any], name: String, in dir: URL) throws -> URL {
    let url = dir.appendingPathComponent(name)
    let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    try data.write(to: url)
    return url
}

@MainActor
@Suite struct LegacyPlistClassificationTests {
    @Test func knownShapesClassifyAsKnown() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let delegate = makeDelegate(stateDir: dir)

        let byName = try writePlist(["Label": "anything"], name: "org.lidawake.guard.plist", in: dir)
        #expect(delegate.classifyLegacyAgentPlist(byName) == .known)

        let byLabel = try writePlist(["Label": "lv.fleet.lidguard"], name: "custom-name.plist", in: dir)
        #expect(delegate.classifyLegacyAgentPlist(byLabel) == .known)

        let byPayload = try writePlist(
            ["Label": "user.custom.job",
             "ProgramArguments": ["/bin/bash", "/Users/x/.claude/hooks/lid-battery-guard.sh"]],
            name: "user.custom.job.plist", in: dir)
        #expect(delegate.classifyLegacyAgentPlist(byPayload) == .known)
    }

    @Test func mentionOnlyPlistIsNotRemovable() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let delegate = makeDelegate(stateDir: dir)

        // A third-party automation that merely mentions the app in an
        // argument: it must classify as a reportable mention, never .known.
        let mention = try writePlist(
            ["Label": "com.example.backup",
             "ProgramArguments": ["/usr/local/bin/backup", "--note", "syncs lidawake logs"]],
            name: "com.example.backup.plist", in: dir)
        #expect(delegate.classifyLegacyAgentPlist(mention) == .mentionOnly)
    }

    @Test func unrelatedAndOwnGuardPlistsMatchNothing() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let delegate = makeDelegate(stateDir: dir)

        let unrelated = try writePlist(["Label": "com.example.other"],
                                       name: "com.example.other.plist", in: dir)
        #expect(delegate.classifyLegacyAgentPlist(unrelated) == .none)

        // The app's own guard plist is never legacy, whatever it contains.
        let own = try writePlist(["Label": "app.lidawake.guard"],
                                 name: "app.lidawake.guard.plist", in: dir)
        #expect(delegate.classifyLegacyAgentPlist(own) == .none)
    }
}

@MainActor
@Suite struct MigrationBackupGateTests {
    @Test func removalRequiresAVerifiedBackup() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let delegate = makeDelegate(stateDir: dir)
        let fm = FileManager.default

        let victim = dir.appendingPathComponent("victim.plist")
        try Data("payload".utf8).write(to: victim)

        // A backup directory nested under a regular FILE cannot be
        // created: the backup fails, so the original must survive.
        let blocker = dir.appendingPathComponent("blocker")
        try Data().write(to: blocker)
        var removed: [String] = []
        delegate.removeLegacyFile(victim, backupDir: blocker.appendingPathComponent("nested"),
                                  removed: &removed)
        #expect(fm.fileExists(atPath: victim.path), "no verified backup, no deletion")
        #expect(removed.isEmpty)

        // With a writable backup location the removal proceeds and the
        // backup holds the original bytes.
        let backupDir = dir.appendingPathComponent("backups")
        delegate.removeLegacyFile(victim, backupDir: backupDir, removed: &removed)
        #expect(!fm.fileExists(atPath: victim.path))
        #expect(removed == [victim.path])
        let backedUp = backupDir.appendingPathComponent("victim.plist")
        #expect((try? Data(contentsOf: backedUp)) == Data("payload".utf8))
    }
}
