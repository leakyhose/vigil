import Foundation

/// Locations Vigil reads from and writes to.
public struct Paths {
    public var home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    /// T3 Code's local state database.
    public var t3Database: URL { home.appendingPathComponent(".t3/userdata/statev2.sqlite") }

    /// Claude Code user settings, where the busy-marker hooks are registered.
    public var claudeSettings: URL { home.appendingPathComponent(".claude/settings.json") }

    /// Directory for the hook script and its per-session busy markers.
    public var hookDirectory: URL { home.appendingPathComponent(".claude/keepawake") }
    public var hookScript: URL { hookDirectory.appendingPathComponent("hook.sh") }
    public var markerDirectory: URL { hookDirectory.appendingPathComponent("active") }

    public var supportDirectory: URL { home.appendingPathComponent("Library/Application Support/Vigil") }
    public var logFile: URL { home.appendingPathComponent("Library/Logs/Vigil.log") }
}
