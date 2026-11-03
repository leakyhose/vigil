import Foundation

/// Installs or removes the Claude Code hooks that write busy markers.
/// Only entries pointing at our hook script are touched; other hooks are preserved.
public struct ClaudeHooks {
    public var paths: Paths

    public init(paths: Paths) {
        self.paths = paths
    }

    static let events = ["UserPromptSubmit": "start", "Stop": "stop", "SessionEnd": "stop"]
    static let scriptMarker = ".claude/keepawake/hook.sh"

    static let script = """
        #!/bin/zsh
        # Vigil hook for Claude Code: `hook.sh start` on UserPromptSubmit, `hook.sh stop` on Stop/SessionEnd.
        # Marks a session busy so Vigil keeps the Mac awake until the turn finishes.
        dir=~/.claude/keepawake/active
        mkdir -p $dir
        sid=$(grep -o '"session_id" *: *"[^"]*"' | head -1 | sed 's/.*"\\([^"]*\\)"$/\\1/')
        [[ -z $sid ]] && exit 0
        if [[ $1 == start ]]; then
          # Record the owning claude process so crashed sessions get cleaned up.
          pid=$PPID
          while (( pid > 1 )); do
            [[ $(ps -o comm= -p $pid) == *claude* ]] && break
            pid=$(ps -o ppid= -p $pid | tr -d ' ')
          done
          (( pid > 1 )) || pid=
          print $pid > $dir/$sid
        else
          rm -f $dir/$sid
        fi
        exit 0

        """

    public var isInstalled: Bool {
        guard let settings = try? readSettings(), let hooks = settings["hooks"] as? [String: Any] else { return false }
        return Self.events.keys.allSatisfy { event in
            (hooks[event] as? [[String: Any]] ?? []).contains(where: Self.isOurs)
        }
    }

    public func install() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: paths.markerDirectory, withIntermediateDirectories: true)
        try Self.script.write(to: paths.hookScript, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: paths.hookScript.path)

        try updateSettings { hooks in
            for (event, arg) in Self.events {
                var groups = (hooks[event] as? [[String: Any]] ?? []).filter { !Self.isOurs($0) }
                groups.append(["hooks": [["type": "command", "command": "$HOME/\(Self.scriptMarker) \(arg)"]]])
                hooks[event] = groups
            }
        }
    }

    public func uninstall() throws {
        try updateSettings { hooks in
            for event in Self.events.keys {
                let groups = (hooks[event] as? [[String: Any]] ?? []).filter { !Self.isOurs($0) }
                hooks[event] = groups.isEmpty ? nil : groups
            }
        }
        try? FileManager.default.removeItem(at: paths.hookDirectory)
    }

    static func isOurs(_ group: [String: Any]) -> Bool {
        (group["hooks"] as? [[String: Any]] ?? []).contains {
            ($0["command"] as? String)?.contains(scriptMarker) == true
        }
    }

    private func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: paths.claudeSettings.path) else { return [:] }
        let data = try Data(contentsOf: paths.claudeSettings)
        if data.isEmpty { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return object
    }

    private func updateSettings(_ change: (inout [String: Any]) -> Void) throws {
        var settings = try readSettings()
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        change(&hooks)
        settings["hooks"] = hooks.isEmpty ? nil : hooks

        let fm = FileManager.default
        try fm.createDirectory(at: paths.claudeSettings.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: paths.claudeSettings.path) {
            let backup = paths.claudeSettings.appendingPathExtension("vigil-backup")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: paths.claudeSettings, to: backup)
        }
        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: paths.claudeSettings, options: .atomic)
    }
}
