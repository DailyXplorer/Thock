public enum Direction: UInt8, Sendable {
    case down
    case up
}

public struct SoundTrigger: Sendable, Equatable {
    public enum Timing: Sendable {
        case immediate
        case afterPress
    }

    public var category: SoundCategory
    public var direction: Direction
    public var column: Float
    public var row: UInt8
    public var timing: Timing
}

public struct TriggerBatch: RandomAccessCollection, Sendable, Equatable {
    private var first: SoundTrigger?
    private var second: SoundTrigger?

    public init() {}

    public var startIndex: Int { 0 }
    public var endIndex: Int { second != nil ? 2 : first != nil ? 1 : 0 }

    public subscript(position: Int) -> SoundTrigger {
        precondition(position >= startIndex && position < endIndex)
        return (position == 0 ? first : second)!
    }

    mutating func append(_ trigger: SoundTrigger) {
        if first == nil {
            first = trigger
        } else {
            precondition(second == nil, "TriggerBatch holds at most two triggers")
            second = trigger
        }
    }
}

public struct KeyStateMachine: Sendable {
    public private(set) var pressed = KeySet()

    public init() {}

    public mutating func reset() {
        pressed.removeAll()
    }

    public mutating func reduce(_ event: RawInputEvent) -> TriggerBatch {
        var batch = TriggerBatch()
        let entry = KeyMap.entry(for: event.keycode)
        switch event.kind {
        case .reset:
            reset()
        case .keyDown, .mouseDown:
            guard !event.isAutorepeat else { break }
            pressed.insert(event.keycode)
            batch.append(trigger(entry, .down))
        case .keyUp, .mouseUp:
            if pressed.remove(event.keycode) {
                batch.append(trigger(entry, .up))
            }
        case .flagsChanged:
            switch entry.modifier {
            case .capsLock:
                batch.append(trigger(entry, .down))
                batch.append(trigger(entry, .up, timing: .afterPress))
            case let .flag(device, generic):
                let sideIsKnown = device == generic || event.flags & KeyMap.deviceModifierMask != 0
                if sideIsKnown {
                    let isDown = event.flags & device != 0
                    if isDown, pressed.insert(event.keycode) {
                        batch.append(trigger(entry, .down))
                    } else if !isDown, pressed.remove(event.keycode) {
                        batch.append(trigger(entry, .up))
                    }
                } else if event.flags & generic != 0 {
                    // The generic flag stays set while the other side is held, so a change on a held key is its release.
                    if pressed.remove(event.keycode) {
                        batch.append(trigger(entry, .up))
                    } else {
                        pressed.insert(event.keycode)
                        batch.append(trigger(entry, .down))
                    }
                } else {
                    for keycode in UInt16(0)..<256 where pressed.contains(keycode) {
                        let held = KeyMap.entry(for: keycode)
                        if case let .flag(_, heldGeneric) = held.modifier, heldGeneric == generic {
                            pressed.remove(keycode)
                            batch.append(trigger(held, .up))
                        }
                    }
                }
            case .none:
                break
            }
        }
        return batch
    }

    private func trigger(_ entry: KeyEntry, _ direction: Direction, timing: SoundTrigger.Timing = .immediate) -> SoundTrigger {
        SoundTrigger(category: entry.category, direction: direction, column: entry.column, row: entry.row, timing: timing)
    }
}
