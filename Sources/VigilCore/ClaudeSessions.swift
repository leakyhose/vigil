import Foundation

/// Claude Code sessions marked busy by the hook script: a file per session in the marker
/// directory, created when a prompt is submitted and removed when the turn stops.
/// Each file holds the pid of the session's `claude` process (or nothing if unknown).
public struct ClaudeSessions {
    public var markerDirectory: URL
    /// Markers older than this are left over from a crash.
    public var maxAge: TimeInterval = 24 * 3600
    public var isAlive: (pid_t) -> Bool = ProcessInfoLookup.isAlive
    /// Sessions launched by T3 Code are already reported by `T3Monitor`.
    public var isManagedByT3: (pid_t) -> Bool = { pid in
        ProcessInfoLookup.ancestorPaths(of: pid).contains { $0.contains("/T3 Code") }
    }

    public init(markerDirectory: URL) {
        self.markerDirectory = markerDirectory
    }

    /// Number of busy sessions not run by T3. Deletes stale markers as it goes.
    public func busyCount(now: Date = Date()) -> Int {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: markerDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return 0 }
        var count = 0
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let pid = (try? String(contentsOf: file, encoding: .utf8))
                .flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if now.timeIntervalSince(modified) > maxAge || pid.map({ !isAlive($0) }) == true {
                try? fm.removeItem(at: file)
                continue
            }
            if let pid, isManagedByT3(pid) { continue }
            count += 1
        }
        return count
    }
}
