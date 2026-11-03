import XCTest
@testable import VigilCore

final class PathsTests: XCTestCase {
    func testPathsAreRootedAtHome() {
        let paths = Paths(home: URL(fileURLWithPath: "/tmp/home"))
        XCTAssertEqual(paths.t3Database.path, "/tmp/home/.t3/userdata/statev2.sqlite")
        XCTAssertEqual(paths.markerDirectory.path, "/tmp/home/.claude/keepawake/active")
    }
}
