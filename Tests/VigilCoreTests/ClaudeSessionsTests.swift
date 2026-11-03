import XCTest
@testable import VigilCore

final class ClaudeSessionsTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    func mark(_ session: String, pid: String, age: TimeInterval = 0) throws {
        let file = dir.appendingPathComponent(session)
        try pid.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: file.path)
    }

    func sessions(alive: Set<pid_t>, t3: Set<pid_t> = []) -> ClaudeSessions {
        var s = ClaudeSessions(markerDirectory: dir)
        s.isAlive = { alive.contains($0) }
        s.isManagedByT3 = { t3.contains($0) }
        return s
    }

    func remaining() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
    }

    func testCountsLiveSessionsAndDropsDeadOnes() throws {
        try mark("live", pid: "100")
        try mark("dead", pid: "200")
        XCTAssertEqual(sessions(alive: [100]).busyCount(), 1)
        XCTAssertEqual(try remaining(), ["live"])
    }

    func testMarkerWithoutPidExpiresByAge() throws {
        try mark("fresh", pid: "")
        try mark("old", pid: "", age: 25 * 3600)
        XCTAssertEqual(sessions(alive: []).busyCount(), 1)
        XCTAssertEqual(try remaining(), ["fresh"])
    }

    func testSkipsSessionsRunByT3WithoutDeletingThem() throws {
        try mark("t3", pid: "100")
        try mark("terminal", pid: "101")
        XCTAssertEqual(sessions(alive: [100, 101], t3: [100]).busyCount(), 1)
        XCTAssertEqual(try remaining(), ["t3", "terminal"])
    }

    func testMissingDirectoryCountsZero() {
        XCTAssertEqual(ClaudeSessions(markerDirectory: dir.appendingPathComponent("nope")).busyCount(), 0)
    }

    func testRealProcessLookup() {
        XCTAssertTrue(ProcessInfoLookup.isAlive(getpid()))
        XCTAssertTrue(ProcessInfoLookup.isAlive(1))
        XCTAssertEqual(ProcessInfoLookup.parent(of: getpid()), getppid())
    }
}
