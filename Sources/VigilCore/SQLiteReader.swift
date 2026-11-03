import Foundation
import SQLite3

/// Minimal read-only SQLite access. Opening read-only never blocks or modifies the writer's database.
final class SQLiteReader {
    private var db: OpaquePointer?

    init?(path: String) {
        guard FileManager.default.fileExists(atPath: path),
              sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        sqlite3_busy_timeout(db, 2000)
    }

    deinit { sqlite3_close(db) }

    /// Runs `sql` and returns each row as an array of optional strings.
    func rows(_ sql: String) -> [[String?]]? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        var result: [[String?]] = []
        let columns = sqlite3_column_count(stmt)
        while true {
            let step = sqlite3_step(stmt)
            guard step == SQLITE_ROW else { return step == SQLITE_DONE ? result : nil }
            result.append((0..<columns).map { i in
                sqlite3_column_text(stmt, i).map { String(cString: $0) }
            })
        }
    }
}
