import Foundation

/// A T3 thread paused on a usage limit that T3 will resume automatically.
public struct LimitWait: Equatable {
    public var title: String
    public var resetAt: Date

    public init(title: String, resetAt: Date) {
        self.title = title
        self.resetAt = resetAt
    }
}

public struct T3Activity: Equatable {
    /// Titles of threads with a turn in progress (any provider).
    public var running: [String] = []
    /// Threads waiting for a limit reset, soonest first.
    public var limitWaits: [LimitWait] = []
    /// False when the T3 database is missing or unreadable.
    public var available = false

    public init(running: [String] = [], limitWaits: [LimitWait] = [], available: Bool = false) {
        self.running = running
        self.limitWaits = limitWaits
        self.available = available
    }
}

/// Reads T3 Code's local state database. The schema is internal to T3 and undocumented,
/// so every query fails soft: a schema change yields "no activity", never a crash.
public struct T3Monitor {
    public var databasePath: String
    /// Ignore runs marked running for longer than this; they are left over from a crash.
    public var staleRunAge: TimeInterval = 24 * 3600
    /// Keep counting a limit wait this long past its reset, so the resumed turn can start.
    public var resetGrace: TimeInterval = 10 * 60
    /// Ignore limit waits whose reset is further away than this (e.g. weekly limits).
    public var maxWaitAhead: TimeInterval = 12 * 3600

    public init(databasePath: String) {
        self.databasePath = databasePath
    }

    public func activity(now: Date = Date()) -> T3Activity {
        guard let db = SQLiteReader(path: databasePath) else { return T3Activity() }
        var activity = T3Activity(available: true)

        let runs = db.rows("""
            select t.title, r.requested_at, t.thread_id
            from orchestration_v2_projection_runs r
            join orchestration_v2_projection_threads t using (thread_id)
            where r.status = 'running' and t.archived_at is null and t.deleted_at is null
            """) ?? []
        var runningThreads = Set<String>()
        for row in runs {
            guard let title = row[0], let requested = row[1].flatMap(parseDate),
                  now.timeIntervalSince(requested) < staleRunAge else { continue }
            activity.running.append(title)
            runningThreads.insert(row[2] ?? "")
        }

        let limited = db.rows("""
            select title, thread_id,
                   json_extract(payload_json, '$.limitRecovery.resetAt'),
                   json_extract(payload_json, '$.limitRecovery.autoResume')
            from orchestration_v2_projection_threads
            where archived_at is null and deleted_at is null
              and json_extract(payload_json, '$.limitRecovery') is not null
            """) ?? []
        for row in limited {
            // A thread that has already resumed is counted as running instead.
            guard let title = row[0], !runningThreads.contains(row[1] ?? ""),
                  let resetAt = row[2].flatMap(parseDate), row[3] == "1" else { continue }
            let untilReset = resetAt.timeIntervalSince(now)
            if untilReset > -resetGrace && untilReset < maxWaitAhead {
                activity.limitWaits.append(LimitWait(title: title, resetAt: resetAt))
            }
        }
        activity.limitWaits.sort { $0.resetAt < $1.resetAt }
        return activity
    }
}

private let fractionalFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
private let plainFormatter = ISO8601DateFormatter()

func parseDate(_ string: String) -> Date? {
    fractionalFormatter.date(from: string) ?? plainFormatter.date(from: string)
}
