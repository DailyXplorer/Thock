import AVFoundation

public struct PackInfo: Codable, Sendable, Hashable {
    public var name: String
    public var author: String
    public var license: String
    public var source: String?
}

public struct SoundSlot: Hashable, Sendable {
    public static let count = SoundCategory.allCases.count * 2

    public let index: Int

    public init(_ category: SoundCategory, _ direction: Direction) {
        index = Int(category.rawValue) * 2 + Int(direction.rawValue)
    }

    public var category: SoundCategory { SoundCategory(rawValue: UInt8(index / 2))! }
    public var direction: Direction { Direction(rawValue: UInt8(index % 2))! }

    public static let all = (0..<count).map { SoundSlot(index: $0) }

    private init(index: Int) {
        self.index = index
    }
}

public struct SoundKey: Hashable, Sendable {
    public static let count = SoundSlot.count * KeyMap.rowCount

    public let index: Int

    public init(_ slot: SoundSlot, row: Int) {
        index = slot.index * KeyMap.rowCount + row
    }

    public init(_ trigger: SoundTrigger) {
        self.init(SoundSlot(trigger.category, trigger.direction), row: Int(trigger.row))
    }
}

public struct PackFileName: Equatable, Sendable {
    public static let extensions: Set<String> = ["caf", "wav", "aiff", "aif"]

    public var slot: SoundSlot
    public var row: Int?
    public var variant: Int

    init(slot: SoundSlot, row: Int?, variant: Int) {
        self.slot = slot
        self.row = row
        self.variant = variant
    }

    public init?(_ fileName: String) {
        let url = URL(fileURLWithPath: fileName)
        guard Self.extensions.contains(url.pathExtension.lowercased()) else { return nil }
        let parts = url.deletingPathExtension().lastPathComponent.split(separator: "_")
        guard parts.count == 3 || parts.count == 4,
              let category = SoundCategory.allCases.first(where: { "\($0)" == parts[0] }),
              let direction: Direction = parts[1] == "down" ? .down : parts[1] == "up" ? .up : nil else { return nil }
        slot = SoundSlot(category, direction)
        if parts[2].first == "r" {
            guard let row = Int(parts[2].dropFirst()), (0..<KeyMap.rowCount).contains(row) else { return nil }
            self.row = row
            guard let variant = parts.count == 4 ? Int(parts[3]) : 1 else { return nil }
            self.variant = variant
        } else {
            guard parts.count == 3, let variant = Int(parts[2]) else { return nil }
            row = nil
            self.variant = variant
        }
    }
}

public struct PackSource: Sendable {
    public static let sampleRate = 48_000.0

    public let id: String
    public let info: PackInfo
    public let clips: [[Float]]
    public let choices: [[Int]]

    public func clips(for slot: SoundSlot, row: Int) -> [[Float]] {
        choices[SoundKey(slot, row: row).index].map { clips[$0] }
    }
}

public final class LoadedPack: @unchecked Sendable {
    struct Clip {
        let samples: UnsafePointer<Float>
        let count: Int
    }

    public let id: String
    public let info: PackInfo
    public let sampleRate: Double
    let clips: ContiguousArray<Clip>
    let choices: ContiguousArray<ContiguousArray<Int>>
    private let storage: UnsafeMutableBufferPointer<Float>

    init(source: PackSource, clips: [[Float]], sampleRate: Double) {
        id = source.id
        info = source.info
        self.sampleRate = sampleRate
        choices = ContiguousArray(source.choices.map { ContiguousArray($0) })
        storage = .allocate(capacity: max(1, clips.reduce(0) { $0 + $1.count }))
        var offset = 0
        var placed = ContiguousArray<Clip>()
        for clip in clips {
            _ = UnsafeMutableBufferPointer(rebasing: storage[offset..<offset + clip.count]).initialize(from: clip)
            placed.append(Clip(samples: UnsafePointer(storage.baseAddress! + offset), count: clip.count))
            offset += clip.count
        }
        self.clips = placed
    }

    deinit {
        storage.deallocate()
    }

    public func samples(for slot: SoundSlot, row: Int) -> [[Float]] {
        choices[SoundKey(slot, row: row).index].map { Array(UnsafeBufferPointer(start: clips[$0].samples, count: clips[$0].count)) }
    }
}
