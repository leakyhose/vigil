import XCTest
@testable import VigilCore

final class PolicyTests: XCTestCase {
    let policy = Policy(lowBatteryCutoff: 10)
    let wait = LimitWait(title: "t", resetAt: Date())

    func testOffNeverHolds() {
        let busy = Snapshot(t3: T3Activity(running: ["a"], available: true), claudeSessions: 2)
        XCTAssertEqual(policy.decide(mode: .off, snapshot: busy), .off)
    }

    func testAgentsModeHoldsWhileWorkingOrWaiting() {
        XCTAssertEqual(policy.decide(mode: .agents, snapshot: Snapshot()), .idle)
        XCTAssertEqual(policy.decide(mode: .agents, snapshot: Snapshot(claudeSessions: 1)),
                       .working(count: 1, limitWaits: 0))
        let waiting = Snapshot(t3: T3Activity(running: ["a"], limitWaits: [wait], available: true))
        XCTAssertEqual(policy.decide(mode: .agents, snapshot: waiting), .working(count: 1, limitWaits: 1))
        XCTAssertTrue(policy.decide(mode: .agents, snapshot: waiting).holdsAwake)
    }

    func testAlwaysModeHoldsWithNothingRunning() {
        XCTAssertEqual(policy.decide(mode: .always, snapshot: Snapshot()), .always)
    }

    func testLowBatteryOnlyCountsWhenUnplugged() {
        let low = Snapshot(claudeSessions: 1, battery: Battery(percent: 8, onAC: false))
        XCTAssertEqual(policy.decide(mode: .agents, snapshot: low), .lowBattery(percent: 8))
        XCTAssertEqual(policy.decide(mode: .always, snapshot: low), .lowBattery(percent: 8))
        let charging = Snapshot(claudeSessions: 1, battery: Battery(percent: 8, onAC: true))
        XCTAssertEqual(policy.decide(mode: .agents, snapshot: charging), .working(count: 1, limitWaits: 0))
        XCTAssertEqual(Policy(lowBatteryCutoff: nil).decide(mode: .always, snapshot: low), .always)
    }
}

final class LidSupportTests: XCTestCase {
    func testRuleIsValidSudoers() throws {
        let file = NSTemporaryDirectory() + "sudoers-\(UUID().uuidString)"
        try LidSupport.rule(user: "someone").write(toFile: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: file) }
        XCTAssertEqual(VigilCore.run("/usr/sbin/visudo", ["-cf", file]), 0)
    }

    func testShellQuote() {
        XCTAssertEqual(shellQuote("it's"), #"'it'\''s'"#)
    }
}
