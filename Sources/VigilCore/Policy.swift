import Foundation

public enum Mode: String, CaseIterable {
    /// Vigil does nothing; the Mac sleeps normally.
    case off
    /// Stay awake while agents are working or waiting on a limit reset.
    case agents
    /// Stay awake unconditionally.
    case always
}

public struct Battery: Equatable {
    public var percent: Int
    public var onAC: Bool

    public init(percent: Int, onAC: Bool) {
        self.percent = percent
        self.onAC = onAC
    }
}

public struct Snapshot: Equatable {
    public var t3 = T3Activity()
    public var claudeSessions = 0
    public var battery: Battery?

    public init(t3: T3Activity = T3Activity(), claudeSessions: Int = 0, battery: Battery? = nil) {
        self.t3 = t3
        self.claudeSessions = claudeSessions
        self.battery = battery
    }

    public var working: Int { t3.running.count + claudeSessions }
}

public enum Decision: Equatable {
    case off
    case idle
    case lowBattery(percent: Int)
    case always
    case working(count: Int, limitWaits: Int)

    public var holdsAwake: Bool {
        switch self {
        case .always, .working: return true
        case .off, .idle, .lowBattery: return false
        }
    }
}

public struct Policy {
    /// On battery, let the Mac sleep at or below this charge so work isn't lost to a dead battery.
    public var lowBatteryCutoff: Int?

    public init(lowBatteryCutoff: Int? = 10) {
        self.lowBatteryCutoff = lowBatteryCutoff
    }

    public func decide(mode: Mode, snapshot: Snapshot) -> Decision {
        if mode == .off { return .off }
        if let cutoff = lowBatteryCutoff, let battery = snapshot.battery,
           !battery.onAC, battery.percent <= cutoff {
            return .lowBattery(percent: battery.percent)
        }
        if mode == .always { return .always }
        let waits = snapshot.t3.limitWaits.count
        return snapshot.working + waits > 0 ? .working(count: snapshot.working, limitWaits: waits) : .idle
    }
}
