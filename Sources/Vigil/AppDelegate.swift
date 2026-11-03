import AppKit
import ServiceManagement
import VigilCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let paths = Paths()
    private lazy var power = PowerController(paths: paths, log: Log.write)
    private lazy var hooks = ClaudeHooks(paths: paths)
    private lazy var t3 = T3Monitor(databasePath: paths.t3Database.path)
    private lazy var claude = ClaudeSessions(markerDirectory: paths.markerDirectory)

    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var snapshot = Snapshot()
    private var decision = Decision.off
    private let defaults = UserDefaults.standard

    private var mode: Mode {
        get { Mode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .off }
        set {
            defaults.set(newValue.rawValue, forKey: "mode")
            Log.write("mode: \(newValue.rawValue)")
            tick()
        }
    }

    private var stopOnLowBattery: Bool {
        get { defaults.object(forKey: "stopOnLowBattery") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "stopOnLowBattery"); tick() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        power.recoverFromCrash()
        power.lidSupport = LidSupport.isEnabled
        Log.write("started (mode: \(mode.rawValue), lid-closed support: \(power.lidSupport))")

        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 3
        tick()
    }

    func applicationWillTerminate(_ notification: Notification) {
        power.release()
        Log.write("quit")
    }

    // MARK: - State

    private func tick() {
        snapshot = Snapshot(
            t3: t3.activity(),
            claudeSessions: claude.busyCount(),
            battery: PowerController.battery)
        let policy = Policy(lowBatteryCutoff: stopOnLowBattery ? 10 : nil)
        decision = policy.decide(mode: mode, snapshot: snapshot)

        switch decision {
        case .always: power.hold(reason: "always on")
        case let .working(count, waits): power.hold(reason: "\(count) working, \(waits) waiting on limits")
        case .off, .idle, .lowBattery: power.release()
        }
        updateIcon()
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let symbol: String
        var color: NSColor?
        var title = ""
        switch decision {
        case .off:
            symbol = "moon.zzz"
        case .idle:
            symbol = "cup.and.saucer"
        case .lowBattery:
            symbol = "battery.25"
            color = .systemRed
        case .always:
            symbol = "cup.and.saucer.fill"
            color = .systemOrange
        case let .working(count, waits):
            symbol = "cup.and.saucer.fill"
            color = .systemOrange
            title = " \(count + waits)"
        }
        var image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Vigil")
        if let color {
            image = image?.withSymbolConfiguration(.init(paletteColors: [color]))
            image?.isTemplate = false
        } else {
            image?.isTemplate = true
        }
        button.image = image
        button.imagePosition = .imageLeading
        button.title = title
        button.appearsDisabled = decision == .off
        button.toolTip = statusLine
    }

    private var statusLine: String {
        switch decision {
        case .off: return "Off: your Mac sleeps normally"
        case .idle: return "On: nothing running, Mac can sleep"
        case let .lowBattery(percent): return "Paused: battery at \(percent)%, Mac can sleep"
        case .always: return "Keeping your Mac awake (always)"
        case let .working(count, waits):
            var parts: [String] = []
            if count > 0 { parts.append("\(count) working") }
            if waits > 0 { parts.append("\(waits) waiting for limit reset") }
            return "Keeping your Mac awake: " + parts.joined(separator: ", ")
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        power.lidSupport = LidSupport.isEnabled
        tick()
        menu.removeAllItems()

        menu.addItem(disabled(statusLine))
        for title in snapshot.t3.running.prefix(6) {
            menu.addItem(disabled("    ▸ \(truncate(title))"))
        }
        if snapshot.claudeSessions > 0 {
            menu.addItem(disabled("    ▸ \(snapshot.claudeSessions) Claude Code session(s) outside T3"))
        }
        let time = DateFormatter()
        time.timeStyle = .short
        for wait in snapshot.t3.limitWaits.prefix(6) {
            let when = wait.resetAt > Date() ? "resumes \(time.string(from: wait.resetAt))" : "resuming now"
            menu.addItem(disabled("    ⏸ \(truncate(wait.title)) (\(when))"))
        }
        if mode != .off && !power.lidSupport {
            menu.addItem(disabled("Lid-closed support is off: closing the lid still sleeps"))
        }
        if !snapshot.t3.available && mode == .agents {
            menu.addItem(disabled("T3 Code data not found"))
        }

        menu.addItem(.separator())
        menu.addItem(modeItem("Keep Awake While Agents Work", .agents))
        menu.addItem(modeItem("Keep Awake Always", .always))

        menu.addItem(.separator())
        let settings = NSMenu()
        if power.lidSupport {
            settings.addItem(checked("Lid-Closed Support", true, nil))
            settings.addItem(item("Remove Lid-Closed Support…", #selector(removeLidSupport)))
        } else {
            settings.addItem(item("Enable Lid-Closed Support…", #selector(enableLidSupport)))
        }
        settings.addItem(checked("Track Claude Code Outside T3", hooks.isInstalled, #selector(toggleHooks)))
        settings.addItem(checked("Let Mac Sleep at 10% Battery", stopOnLowBattery, #selector(toggleLowBattery)))
        settings.addItem(checked("Launch at Login", SMAppService.mainApp.status == .enabled, #selector(toggleLogin)))
        settings.addItem(.separator())
        settings.addItem(item("Open Log", #selector(openLog)))
        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.submenu = settings
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        menu.addItem(item("Quit Vigil", #selector(quit), key: "q"))
    }

    private func truncate(_ s: String) -> String {
        s.count > 48 ? String(s.prefix(47)) + "…" : s
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func checked(_ title: String, _ on: Bool, _ action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        if action == nil { item.isEnabled = false }
        return item
    }

    private func modeItem(_ title: String, _ value: Mode) -> NSMenuItem {
        let item = item(title, #selector(selectMode(_:)))
        item.representedObject = value.rawValue
        item.state = mode == value ? .on : .off
        return item
    }

    // MARK: - Actions

    /// Choosing the checked mode again turns Vigil off.
    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let value = (sender.representedObject as? String).flatMap(Mode.init) else { return }
        mode = mode == value ? .off : value
    }

    @objc private func enableLidSupport() {
        let explain = "To keep your Mac awake with the lid closed, Vigil needs permission to run "
            + "“pmset -a disablesleep” without a password. macOS will ask for your administrator password once."
        guard confirm("Enable Lid-Closed Support?", explain, button: "Continue") else { return }
        if runAsAdmin(LidSupport.installCommand(user: NSUserName())) {
            power.lidSupport = LidSupport.isEnabled
            Log.write("lid-closed support enabled: \(power.lidSupport)")
            tick()
        }
    }

    @objc private func removeLidSupport() {
        power.release()
        if runAsAdmin(LidSupport.removeCommand) {
            power.lidSupport = LidSupport.isEnabled
            Log.write("lid-closed support removed (still enabled: \(power.lidSupport))")
            if power.lidSupport {
                alert("Lid-closed support is still active",
                      "Another sudoers rule also allows “pmset -a disablesleep”. Look in /etc/sudoers.d/.")
            }
        }
        tick()
    }

    @objc private func toggleHooks() {
        do {
            if hooks.isInstalled { try hooks.uninstall() } else { try hooks.install() }
            Log.write("Claude Code hooks installed: \(hooks.isInstalled)")
        } catch {
            alert("Couldn’t update Claude Code settings", error.localizedDescription)
        }
    }

    @objc private func toggleLowBattery() {
        stopOnLowBattery.toggle()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            alert("Couldn’t change Launch at Login", error.localizedDescription)
        }
    }

    @objc private func openLog() {
        if !FileManager.default.fileExists(atPath: paths.logFile.path) { Log.write("log opened") }
        NSWorkspace.shared.open(paths.logFile)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private func runAsAdmin(_ command: String) -> Bool {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?.executeAndReturnError(&error)
        if let error, (error[NSAppleScript.errorNumber] as? Int) != -128 {
            alert("Couldn’t change lid-closed support", error[NSAppleScript.errorMessage] as? String ?? "\(error)")
        }
        return error == nil
    }

    private func confirm(_ title: String, _ text: String, button: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: button)
        a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn
    }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}
