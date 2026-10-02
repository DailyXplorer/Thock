public struct KeySet: Sendable, Equatable {
    private var words: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)

    public init() {}

    public static func == (lhs: KeySet, rhs: KeySet) -> Bool {
        lhs.words == rhs.words
    }

    public var isEmpty: Bool { words == (0, 0, 0, 0) }

    public var count: Int {
        words.0.nonzeroBitCount + words.1.nonzeroBitCount + words.2.nonzeroBitCount + words.3.nonzeroBitCount
    }

    public func contains(_ keycode: UInt16) -> Bool {
        guard keycode < 256 else { return false }
        return word(keycode >> 6) & bit(keycode) != 0
    }

    @discardableResult
    public mutating func insert(_ keycode: UInt16) -> Bool {
        guard keycode < 256, !contains(keycode) else { return false }
        setWord(keycode >> 6, word(keycode >> 6) | bit(keycode))
        return true
    }

    @discardableResult
    public mutating func remove(_ keycode: UInt16) -> Bool {
        guard contains(keycode) else { return false }
        setWord(keycode >> 6, word(keycode >> 6) & ~bit(keycode))
        return true
    }

    public mutating func removeAll() {
        words = (0, 0, 0, 0)
    }

    private func bit(_ keycode: UInt16) -> UInt64 { 1 << UInt64(keycode & 63) }

    private func word(_ index: UInt16) -> UInt64 {
        switch index {
        case 0: words.0
        case 1: words.1
        case 2: words.2
        default: words.3
        }
    }

    private mutating func setWord(_ index: UInt16, _ value: UInt64) {
        switch index {
        case 0: words.0 = value
        case 1: words.1 = value
        case 2: words.2 = value
        default: words.3 = value
        }
    }
}
