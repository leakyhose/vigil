import XCTest
@testable import VigilCore

final class T3MonitorTests: XCTestCase {
    var dbPath: String!
    let now = parseDate("2026-11-02T21:00:00Z")!

    override func setUpWithError() throws {
        dbPath = NSTemporaryDirectory() + "t3-\(UUID().uuidString).sqlite"
        try sqlite(dbPath, """
            create table orchestration_v2_projection_threads (
              thread_id text primary key, title text, archived_at text, deleted_at text, payload_json text);
            create table orchestration_v2_projection_runs (
              run_id text primary key, thread_id text, status text, requested_at text);
            """)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    func addThread(_ id: String, _ title: String, payload: String = "{}", archived: Bool = false) throws {
        try sqlite(dbPath, "insert into orchestration_v2_projection_threads values ('\(id)', '\(title)', \(archived ? "'2026-01-01'" : "null"), null, '\(payload)')")
    }

    func addRun(_ thread: String, status: String, requestedAt: String) throws {
        try sqlite(dbPath, "insert into orchestration_v2_projection_runs values ('\(UUID())', '\(thread)', '\(status)', '\(requestedAt)')")
    }

    func limit(_ resetAt: String, autoResume: Bool = true) -> String {
        #"{"limitRecovery":{"resetAt":"\#(resetAt)","autoResume":\#(autoResume),"snooze":false}}"#
    }

    func testMissingDatabaseIsUnavailable() {
        let activity = T3Monitor(databasePath: "/nonexistent.sqlite").activity(now: now)
        XCTAssertFalse(activity.available)
        XCTAssertEqual(activity, T3Activity())
    }

    func testCountsOnlyRecentRunningRuns() throws {
        try addThread("a", "Active")
        try addThread("b", "Done")
        try addThread("c", "Crashed long ago")
        try addThread("d", "Archived", archived: true)
        try addRun("a", status: "running", requestedAt: "2026-11-02T20:30:00.000Z")
        try addRun("b", status: "completed", requestedAt: "2026-11-02T20:30:00.000Z")
        try addRun("c", status: "running", requestedAt: "2026-10-30T20:30:00.000Z")
        try addRun("d", status: "running", requestedAt: "2026-11-02T20:30:00.000Z")
        let activity = T3Monitor(databasePath: dbPath).activity(now: now)
        XCTAssertTrue(activity.available)
        XCTAssertEqual(activity.running, ["Active"])
    }

    func testLimitWaitsRespectAutoResumeGraceAndHorizon() throws {
        try addThread("a", "Resets soon", payload: limit("2026-11-02T22:10:00.000Z"))
        try addThread("b", "Manual resume", payload: limit("2026-11-02T22:10:00.000Z", autoResume: false))
        try addThread("c", "Just reset", payload: limit("2026-11-02T20:55:00.000Z"))
        try addThread("d", "Reset long ago", payload: limit("2026-11-02T20:00:00.000Z"))
        try addThread("e", "Weekly limit", payload: limit("2026-11-06T00:00:00.000Z"))
        try addThread("f", "Resets sooner", payload: limit("2026-11-02T21:30:00Z"))
        let waits = T3Monitor(databasePath: dbPath).activity(now: now).limitWaits
        XCTAssertEqual(waits.map(\.title), ["Just reset", "Resets sooner", "Resets soon"])
    }

    func testUnexpectedSchemaFailsSoft() throws {
        try sqlite(dbPath, "drop table orchestration_v2_projection_runs")
        try addThread("a", "Resets soon", payload: limit("2026-11-02T22:10:00.000Z"))
        let activity = T3Monitor(databasePath: dbPath).activity(now: now)
        XCTAssertEqual(activity.running, [])
        XCTAssertEqual(activity.limitWaits.count, 1)
    }
}

func sqlite(_ path: String, _ sql: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    process.arguments = [path, sql]
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 { throw NSError(domain: "sqlite3", code: Int(process.terminationStatus)) }
}
