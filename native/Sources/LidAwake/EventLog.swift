import Foundation

/// v3.2 event log: the forensics trail LidAwake was missing. On 2026-08-20
/// a 15:28 clamshell sleep could not be adjudicated from the outside —
/// nothing under ~/Library/Logs said whether Keep awake was armed at that
/// moment, because the only state trail lived in ~/.lidawake/state, where
/// no post-incident reader looks. Every line here is one event: an ISO 8601
/// local-offset stamp, the event, its detail. Human-readable, append-only,
/// no dependencies.
struct EventLog: Sendable {
    static let rotateBytes = 1_048_576
    static let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/LidAwake", isDirectory: true)

    var directory = EventLog.defaultDirectory

    func append(_ event: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("events.log")
        rotateIfNeeded(url)
        let line = "\(stamp()) \(event)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    /// One rotated generation is enough: 1 MB holds months of lines at this
    /// volume, and a bounded pair of files can never fill a disk.
    private func rotateIfNeeded(_ url: URL) {
        let fm = FileManager.default
        guard let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int,
              size >= Self.rotateBytes else { return }
        let rotated = directory.appendingPathComponent("events.log.1")
        try? fm.removeItem(at: rotated)
        try? fm.moveItem(at: url, to: rotated)
    }

    /// ISO 8601 with the LOCAL offset ("2026-08-20T15:28:52+03:00"): the
    /// reader matches wall-clock memory ("it slept at 15:28") without
    /// timezone arithmetic, and the offset keeps travel days unambiguous.
    private func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        return f.string(from: Date())
    }
}
