import CoreGraphics

public struct SourceFilter: Sendable, Equatable {
    public static let hardwareStateID = Int64(CGEventSourceStateID.hidSystemState.rawValue)

    public var includeSynthetic: Bool

    public init(includeSynthetic: Bool = false) {
        self.includeSynthetic = includeSynthetic
    }

    public func accepts(_ event: RawInputEvent) -> Bool {
        event.kind == .reset || includeSynthetic || event.sourceStateID == Self.hardwareStateID
    }
}
