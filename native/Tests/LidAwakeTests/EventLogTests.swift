import Foundation
import Testing
@testable import LidAwake

// v3.2 (issue #5): the event log is the forensics surface — append must
// create its directory, stamp ISO 8601 lines, stay bounded by rotation,
// and mirror every executor log line so the state-machine trail is
// readable from ~/Library/Logs without knowing about ~/.lidawake.

@Suite struct EventLogTests {
    private func scratchDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lidawake-eventlog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func appendCreatesTheDirectoryAndStampsISO8601() throws {
        let dir = try scratchDirectory().appendingPathComponent("nested", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        EventLog(directory: dir).append("launch v9.9.9 (pid 1)")
        let text = try String(contentsOf: dir.appendingPathComponent("events.log"), encoding: .utf8)
        #expect(text.hasSuffix("launch v9.9.9 (pid 1)\n"))
        #expect(text.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2}) "#,
                           options: .regularExpression) != nil)
    }

    @Test func rotatesPastTheCapAndKeepsExactlyOneGeneration() throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = EventLog(directory: dir)
        let live = dir.appendingPathComponent("events.log")

        try Data(repeating: UInt8(ascii: "x"), count: EventLog.rotateBytes).write(to: live)
        log.append("first line after rotation")
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("events.log.1").path))
        let text = try String(contentsOf: live, encoding: .utf8)
        #expect(text.contains("first line after rotation"))
        #expect(text.utf8.count < 200, "the live file restarted from empty")

        // A second oversized generation replaces the first — never a third file.
        try Data(repeating: UInt8(ascii: "y"), count: EventLog.rotateBytes).write(to: live)
        log.append("second rotation")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(names == ["events.log", "events.log.1"])
    }

    @MainActor
    @Test func executorLogLinesMirrorIntoTheEventLog() throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let delegate = AppDelegate()
        delegate.headless = true
        delegate.stateDirectoryOverride = dir
        delegate.appendLog("one-shot armed (mode 1)")
        let events = try String(contentsOf: dir.appendingPathComponent("events.log"), encoding: .utf8)
        let legacy = try String(contentsOf: dir.appendingPathComponent("lid-guard.log"), encoding: .utf8)
        #expect(events.contains("one-shot armed (mode 1)"))
        #expect(legacy.contains("one-shot armed (mode 1)"))
    }
}
