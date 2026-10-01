import CoreGraphics

public enum InputKind: UInt8, Sendable {
    case keyDown
    case keyUp
    case flagsChanged
    case mouseDown
    case mouseUp
    case reset

    init?(_ type: CGEventType) {
        switch type {
        case .keyDown: self = .keyDown
        case .keyUp: self = .keyUp
        case .flagsChanged: self = .flagsChanged
        case .leftMouseDown, .rightMouseDown: self = .mouseDown
        case .leftMouseUp, .rightMouseUp: self = .mouseUp
        default: return nil
        }
    }
}

public struct RawInputEvent: Sendable, Equatable {
    public var timestamp: UInt64
    public var flags: UInt64
    public var sourceStateID: Int64
    public var sourcePID: Int32
    public var keycode: UInt16
    public var kind: InputKind
    public var isAutorepeat: Bool

    public init(kind: InputKind, keycode: UInt16 = 0, flags: UInt64 = 0, isAutorepeat: Bool = false,
                sourceStateID: Int64 = Int64(CGEventSourceStateID.hidSystemState.rawValue),
                sourcePID: Int32 = 0, timestamp: UInt64 = 0) {
        self.timestamp = timestamp
        self.flags = flags
        self.sourceStateID = sourceStateID
        self.sourcePID = sourcePID
        self.keycode = keycode
        self.kind = kind
        self.isAutorepeat = isAutorepeat
    }

    public static let reset = RawInputEvent(kind: .reset)
}
