public struct MuteRules: Codable, Sendable, Equatable {
    public var microphoneInUse = true
    public var excludedApp = true
    public var systemOutputMuted = true

    public init() {}
}

public struct MuteSignals: Sendable, Equatable {
    public var enabled = true
    public var microphoneInUse = false
    public var excludedAppInFront = false
    public var systemOutputMuted = false

    public init() {}

    public func reasons(under rules: MuteRules) -> MuteReasons {
        var reasons: MuteReasons = []
        if !enabled { reasons.insert(.manual) }
        if rules.microphoneInUse, microphoneInUse { reasons.insert(.microphoneInUse) }
        if rules.excludedApp, excludedAppInFront { reasons.insert(.excludedApp) }
        if rules.systemOutputMuted, systemOutputMuted { reasons.insert(.systemOutputMuted) }
        return reasons
    }
}
