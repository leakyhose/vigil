import XCTest
@testable import VigilCore

final class ClaudeHooksTests: XCTestCase {
    var home: URL!
    var hooks: ClaudeHooks!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        hooks = ClaudeHooks(paths: Paths(home: home))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: home)
    }

    func settings() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: hooks.paths.claudeSettings)) as! [String: Any]
    }

    func writeSettings(_ json: String) throws {
        try json.write(to: hooks.paths.claudeSettings, atomically: true, encoding: .utf8)
    }

    func testInstallIntoMissingSettings() throws {
        XCTAssertFalse(hooks.isInstalled)
        try hooks.install()
        XCTAssertTrue(hooks.isInstalled)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: hooks.paths.hookScript.path))
    }

    func testInstallPreservesOtherSettingsAndHooksAndIsIdempotent() throws {
        try writeSettings(#"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#)
        try hooks.install()
        try hooks.install()
        let s = try settings()
        XCTAssertEqual(s["model"] as? String, "opus")
        let stop = (s["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
        XCTAssertEqual(stop.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: hooks.paths.claudeSettings.path + ".vigil-backup"))
    }

    func testUninstallRemovesOnlyOurHooks() throws {
        try writeSettings(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#)
        try hooks.install()
        try hooks.uninstall()
        XCTAssertFalse(hooks.isInstalled)
        let h = try settings()["hooks"] as! [String: Any]
        XCTAssertEqual(Array(h.keys), ["Stop"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: hooks.paths.hookDirectory.path))
    }

    func testUninstallDropsEmptyHooksObject() throws {
        try writeSettings(#"{"model":"opus"}"#)
        try hooks.install()
        try hooks.uninstall()
        XCTAssertNil(try settings()["hooks"])
    }

    func testRecognizesHooksInstalledByHand() throws {
        try writeSettings(#"""
        {"hooks":{
          "UserPromptSubmit":[{"hooks":[{"type":"command","command":"$HOME/.claude/keepawake/hook.sh start"}]}],
          "Stop":[{"hooks":[{"type":"command","command":"$HOME/.claude/keepawake/hook.sh stop"}]}],
          "SessionEnd":[{"hooks":[{"type":"command","command":"$HOME/.claude/keepawake/hook.sh stop"}]}]}}
        """#)
        XCTAssertTrue(hooks.isInstalled)
    }

    func testHookScriptWritesAndClearsMarker() throws {
        try hooks.install()
        let input = #"{"session_id":"abc-123","hook_event_name":"UserPromptSubmit"}"#
        try runHook("start", input: input)
        let marker = hooks.paths.markerDirectory.appendingPathComponent("abc-123")
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        try runHook("stop", input: input)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func runHook(_ arg: String, input: String) throws {
        let p = Process()
        p.executableURL = hooks.paths.hookScript
        p.arguments = [arg]
        p.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        let pipe = Pipe()
        p.standardInput = pipe
        try p.run()
        pipe.fileHandleForWriting.write(Data(input.utf8))
        try pipe.fileHandleForWriting.close()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
    }
}
