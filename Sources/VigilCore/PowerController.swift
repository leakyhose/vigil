import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import CoreGraphics

/// Keeps the Mac awake and lets it sleep again.
///
/// Two layers are used while holding:
/// - IOKit power assertions, which stop idle sleep (lid open, any power source).
/// - `pmset disablesleep 1`, which also stops lid-closed sleep on battery or AC. It needs a
///   sudoers rule (see `LidSupport`); without one Vigil only keeps the Mac awake with the lid open.
public final class PowerController {
    private var assertions: [IOPMAssertionID] = []
    private let flagFile: URL
    private let log: (String) -> Void
    public private(set) var holding = false

    public init(paths: Paths, log: @escaping (String) -> Void = { _ in }) {
        self.flagFile = paths.supportDirectory.appendingPathComponent("lid-hold")
        self.log = log
    }

    /// Undo a lid hold left behind if Vigil was killed while holding.
    public func recoverFromCrash() {
        guard FileManager.default.fileExists(atPath: flagFile.path) else { return }
        if setSleepDisabled(false) { try? FileManager.default.removeItem(at: flagFile) }
        log("recovered: re-enabled sleep left disabled by a previous run")
    }

    public func hold(reason: String) {
        if assertions.isEmpty {
            for type in [kIOPMAssertionTypePreventUserIdleSystemSleep, kIOPMAssertionTypePreventSystemSleep] {
                var id = IOPMAssertionID(0)
                if IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                               "Vigil: \(reason)" as CFString, &id) == kIOReturnSuccess {
                    assertions.append(id)
                }
            }
        }
        if !FileManager.default.fileExists(atPath: flagFile.path), LidSupport.isEnabled, setSleepDisabled(true) {
            try? FileManager.default.createDirectory(at: flagFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: flagFile.path, contents: nil)
            log("lid-closed sleep disabled")
        }
        if !holding { log("holding awake: \(reason)") }
        holding = true
    }

    public func release() {
        for id in assertions { IOPMAssertionRelease(id) }
        assertions = []
        if FileManager.default.fileExists(atPath: flagFile.path) {
            if setSleepDisabled(false) {
                try? FileManager.default.removeItem(at: flagFile)
                log("lid-closed sleep re-enabled")
            }
            // With the lid already shut nothing else would trigger sleep, so sleep now.
            if Self.isLidClosed && !Self.hasExternalDisplay {
                log("lid is closed: sleeping now")
                run("/usr/bin/pmset", ["sleepnow"])
            }
        }
        if holding { log("released: sleep allowed") }
        holding = false
    }

    @discardableResult
    private func setSleepDisabled(_ disabled: Bool) -> Bool {
        run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", disabled ? "1" : "0"]) == 0
    }

    public static var isLidClosed: Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return (value?.takeRetainedValue() as? Bool) ?? false
    }

    static var hasExternalDisplay: Bool {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
    }

    public static var battery: Battery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return Battery(percent: current * 100 / max, onAC: d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return nil
    }
}

/// Lid-closed support is a sudoers rule letting the current user run exactly
/// `pmset -a disablesleep 0|1` without a password.
public enum LidSupport {
    public static let sudoersFile = "/etc/sudoers.d/vigil"

    public static var isEnabled: Bool {
        run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "1"]) == 0
            && run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "0"]) == 0
    }

    public static func rule(user: String) -> String {
        "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n"
    }

    /// Shell command (run as root) that validates and installs the rule.
    public static func installCommand(user: String) -> String {
        let tmp = "/tmp/vigil-sudoers-\(UUID().uuidString)"
        return "printf %s \(shellQuote(rule(user: user))) > \(tmp) && /usr/sbin/visudo -cf \(tmp) && "
            + "/usr/sbin/chown root:wheel \(tmp) && /bin/chmod 440 \(tmp) && /bin/mv \(tmp) \(sudoersFile)"
    }

    public static var removeCommand: String {
        "/usr/bin/pmset -a disablesleep 0; /bin/rm -f \(sudoersFile)"
    }
}

func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

@discardableResult
func run(_ path: String, _ args: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return -1 }
    p.waitUntilExit()
    return p.terminationStatus
}
