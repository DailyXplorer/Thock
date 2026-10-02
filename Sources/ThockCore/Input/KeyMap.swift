public enum SoundCategory: UInt8, Sendable, CaseIterable {
    case alpha
    case space
    case enter
    case backspace
    case tab
    case modifier
    case arrow
    case punctuation
    case mouse
}

public enum ModifierKind: Sendable, Equatable {
    case none
    case flag(device: UInt64, generic: UInt64)
    case capsLock
}

public struct KeyEntry: Sendable, Equatable {
    public var category: SoundCategory
    public var column: Float
    public var row: UInt8
    public var modifier: ModifierKind
}

public enum KeyMap {
    public static let leftMouseButton: UInt16 = 0xF0
    public static let rightMouseButton: UInt16 = 0xF1
    public static let rowCount = 5

    static let deviceModifierMask: UInt64 = 0x207F

    public static func entry(for keycode: UInt16) -> KeyEntry {
        keycode < 256 ? table[Int(keycode)] : fallback
    }

    // The table follows ANSI positions. ISO keyboards report the key left of 1 as 10 and the key
    // right of left Shift as 50, the reverse of what those positions mean on ANSI.
    public static func positionalKeycode(_ keycode: UInt16, isISO: Bool) -> UInt16 {
        guard isISO else { return keycode }
        switch keycode {
        case 10: return 50
        case 50: return 10
        default: return keycode
        }
    }

    static let fallback = KeyEntry(category: .alpha, column: 0.5, row: 2, modifier: .none)

    private static let width: Float = 15

    private static let table: ContiguousArray<KeyEntry> = {
        var table = ContiguousArray(repeating: fallback, count: 256)
        var row: UInt8 = 0
        func set(_ category: SoundCategory, _ x: Float, _ keycodes: [UInt16], modifier: ModifierKind = .none) {
            for keycode in keycodes {
                table[Int(keycode)] = KeyEntry(category: category, column: min(max(x / width, 0), 1), row: row, modifier: modifier)
            }
        }
        func run(_ category: SoundCategory, startX: Float, _ keycodes: [UInt16]) {
            for (offset, keycode) in keycodes.enumerated() {
                set(category, startX + Float(offset), [keycode])
            }
        }

        row = 0
        run(.alpha, startX: 0.5, [53, 122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111])
        set(.alpha, 14.5, [105, 107, 113, 106, 64, 79, 80, 90])

        row = 1
        set(.punctuation, 0.5, [50])
        run(.alpha, startX: 1.5, [18, 19, 20, 21, 23, 22, 26, 28, 25, 29])
        set(.punctuation, 11.5, [27])
        set(.punctuation, 12.5, [24])
        set(.backspace, 14, [51])
        set(.arrow, 14.5, [114, 115, 116])

        row = 2
        set(.tab, 0.75, [48])
        run(.alpha, startX: 2, [12, 13, 14, 15, 17, 16, 32, 34, 31, 35])
        set(.punctuation, 12, [33])
        set(.punctuation, 13, [30])
        set(.punctuation, 14.25, [42])
        set(.backspace, 14.5, [117])
        set(.arrow, 14.5, [119, 121])

        row = 3
        set(.modifier, 0.9, [57], modifier: .capsLock)
        run(.alpha, startX: 2.25, [0, 1, 2, 3, 5, 4, 38, 40, 37])
        set(.punctuation, 11.25, [41])
        set(.punctuation, 12.25, [39])
        set(.enter, 14, [36])

        row = 4
        set(.modifier, 1.1, [56], modifier: .flag(device: 0x02, generic: 0x20000))
        set(.punctuation, 1.75, [10])
        run(.alpha, startX: 2.75, [6, 7, 8, 9, 11, 45, 46])
        set(.punctuation, 9.75, [43])
        set(.punctuation, 10.75, [47])
        set(.punctuation, 11.75, [44])
        set(.modifier, 13.6, [60], modifier: .flag(device: 0x04, generic: 0x20000))

        set(.modifier, 0.5, [63, 179], modifier: .flag(device: 0x800000, generic: 0x800000))
        set(.modifier, 1.5, [59], modifier: .flag(device: 0x01, generic: 0x40000))
        set(.modifier, 2.5, [58], modifier: .flag(device: 0x20, generic: 0x80000))
        set(.modifier, 3.75, [55], modifier: .flag(device: 0x08, generic: 0x100000))
        set(.space, 7, [49])
        set(.modifier, 10.25, [54], modifier: .flag(device: 0x10, generic: 0x100000))
        set(.modifier, 11.5, [61], modifier: .flag(device: 0x40, generic: 0x80000))
        set(.modifier, 12, [62], modifier: .flag(device: 0x2000, generic: 0x40000))
        set(.arrow, 12.5, [123])
        set(.arrow, 13.5, [125, 126])
        set(.arrow, 14.5, [124])

        row = 1
        set(.alpha, 15, [71, 81, 75, 67])
        row = 2
        set(.alpha, 15, [89, 91, 92, 78])
        row = 3
        set(.alpha, 15, [86, 87, 88, 69])
        row = 4
        set(.alpha, 15, [83, 84, 85, 82, 65])
        set(.enter, 15, [76])

        row = 2
        set(.mouse, 0.5, [leftMouseButton, rightMouseButton])
        return table
    }()
}
