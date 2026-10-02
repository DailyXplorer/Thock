import Testing
@testable import ThockCore

private let shiftFlag: UInt64 = 0x20000
private let leftShiftBit: UInt64 = 0x02
private let rightShiftBit: UInt64 = 0x04
private let capsLockFlag: UInt64 = 0x10000
private let fnFlag: UInt64 = 0x800000

private func down(_ keycode: UInt16, repeat isAutorepeat: Bool = false) -> RawInputEvent {
    RawInputEvent(kind: .keyDown, keycode: keycode, isAutorepeat: isAutorepeat)
}

private func up(_ keycode: UInt16) -> RawInputEvent {
    RawInputEvent(kind: .keyUp, keycode: keycode)
}

private func flags(_ keycode: UInt16, _ flags: UInt64) -> RawInputEvent {
    RawInputEvent(kind: .flagsChanged, keycode: keycode, flags: flags)
}

private func run(_ events: [RawInputEvent], on machine: inout KeyStateMachine) -> [SoundTrigger] {
    events.flatMap { machine.reduce($0) }
}

private func sounds(_ events: [RawInputEvent]) -> [String] {
    var machine = KeyStateMachine()
    return run(events, on: &machine).map(\.label)
}

private extension SoundTrigger {
    var label: String { "\(category) \(direction)\(timing == .afterPress ? " afterPress" : "")" }
}

struct KeyStateMachineTests {
    @Test func holdingDeleteFiveSecondsPlaysOneDownAndOneUp() {
        let repeats = Array(repeating: down(51, repeat: true), count: 150)
        #expect(sounds([down(51)] + repeats + [up(51)]) == ["backspace down", "backspace up"])
    }

    @Test func fastOverlappingTypingPlaysEveryPressAndRelease() {
        var machine = KeyStateMachine()
        let triggers = run([down(0), down(1), up(0), down(2), up(1), down(49), up(2), up(49)], on: &machine)
        #expect(triggers.map(\.label) == [
            "alpha down", "alpha down", "alpha up", "alpha down", "alpha up", "space down", "alpha up", "space up",
        ])
        #expect(machine.pressed.isEmpty)
    }

    @Test func leftAndRightShiftAreTrackedIndependently() {
        var machine = KeyStateMachine()
        let triggers = run([
            flags(56, shiftFlag | leftShiftBit),
            flags(60, shiftFlag | leftShiftBit | rightShiftBit),
            flags(56, shiftFlag | rightShiftBit),
            flags(60, 0),
        ], on: &machine)
        #expect(triggers.map(\.label) == ["modifier down", "modifier down", "modifier up", "modifier up"])
        #expect(triggers[0].column < triggers[1].column)
        #expect(triggers[2].column == triggers[0].column)
        #expect(machine.pressed.isEmpty)
    }

    @Test func shiftFallsBackToTheGenericFlagWhenTheKeyboardReportsNoSide() {
        #expect(sounds([flags(56, shiftFlag), down(0), up(0), flags(56, 0)]) == [
            "modifier down", "alpha down", "alpha up", "modifier up",
        ])
    }

    @Test func releasingOneShiftWithoutSideBitsWhileTheOtherIsHeldDoesNotStickIt() {
        var machine = KeyStateMachine()
        let triggers = run([
            flags(56, shiftFlag),
            flags(60, shiftFlag),
            flags(56, shiftFlag),
            flags(60, 0),
            flags(56, shiftFlag),
        ], on: &machine)
        #expect(triggers.map(\.label) == [
            "modifier down", "modifier down", "modifier up", "modifier up", "modifier down",
        ])
        #expect(triggers[2].column == triggers[0].column)
        #expect(triggers[3].column == triggers[1].column)
        #expect(machine.pressed.contains(56) && machine.pressed.count == 1)
    }

    @Test func genericFlagDroppingWithoutSideBitsReleasesBothSides() {
        var machine = KeyStateMachine()
        let triggers = run([flags(56, shiftFlag), flags(60, shiftFlag), flags(60, 0)], on: &machine)
        #expect(triggers.map(\.label) == ["modifier down", "modifier down", "modifier up", "modifier up"])
        #expect(triggers[2].column == triggers[0].column)
        #expect(triggers[3].column == triggers[1].column)
        #expect(machine.pressed.isEmpty)
        #expect(run([flags(56, shiftFlag)], on: &machine).map(\.label) == ["modifier down"])
    }

    @Test func releasingOneSideWithSideBitsKeepsTheOtherHeld() {
        var machine = KeyStateMachine()
        let triggers = run([
            flags(56, shiftFlag | leftShiftBit),
            flags(60, shiftFlag | leftShiftBit | rightShiftBit),
            flags(60, shiftFlag | leftShiftBit),
        ], on: &machine)
        #expect(triggers.map(\.label) == ["modifier down", "modifier down", "modifier up"])
        #expect(triggers[2].column == triggers[1].column)
        #expect(machine.pressed.contains(56) && machine.pressed.count == 1)
    }

    @Test func fnUsesTheSecondaryFnFlag() {
        #expect(sounds([flags(63, fnFlag), flags(63, 0)]) == ["modifier down", "modifier up"])
    }

    @Test func capsLockPlaysPressThenShortReleaseOnEveryToggle() {
        var machine = KeyStateMachine()
        let triggers = run([flags(57, capsLockFlag), flags(57, 0)], on: &machine)
        #expect(triggers.map(\.label) == [
            "modifier down", "modifier up afterPress", "modifier down", "modifier up afterPress",
        ])
        #expect(machine.pressed.isEmpty)
    }

    @Test func repeatedKeyDownWithoutAutorepeatMeansALostKeyUpAndIsPlayed() {
        #expect(sounds([down(0), down(0), up(0), up(0)]) == ["alpha down", "alpha down", "alpha up"])
    }

    @Test func autorepeatIsSilentEvenForAKeyNeverSeenGoingDown() {
        #expect(sounds([down(0, repeat: true), down(0, repeat: true), up(0)]) == [])
        #expect(sounds([down(0, repeat: true), up(0), down(0), up(0)]) == ["alpha down", "alpha up"])
    }

    @Test func resetEventForgetsHeldKeysSoNoGhostReleasePlays() {
        let events = [down(0), flags(56, shiftFlag | leftShiftBit), RawInputEvent.reset, up(0), flags(56, 0), down(1)]
        #expect(sounds(events) == ["alpha down", "modifier down", "alpha down"])
    }

    @Test func resetMethodClearsHeldKeys() {
        var machine = KeyStateMachine()
        _ = run([down(0), down(36)], on: &machine)
        #expect(machine.pressed.count == 2)
        machine.reset()
        #expect(run([up(0), up(36)], on: &machine) == [])
    }

    @Test func mouseButtonsPlayDownAndUpIndependently() {
        let events = [
            RawInputEvent(kind: .mouseDown, keycode: KeyMap.leftMouseButton),
            RawInputEvent(kind: .mouseDown, keycode: KeyMap.rightMouseButton),
            RawInputEvent(kind: .mouseUp, keycode: KeyMap.leftMouseButton),
            RawInputEvent(kind: .mouseUp, keycode: KeyMap.rightMouseButton),
            RawInputEvent(kind: .mouseUp, keycode: KeyMap.rightMouseButton),
        ]
        #expect(sounds(events) == ["mouse down", "mouse down", "mouse up", "mouse up"])
    }

    @Test func isoKeyLeftOfZIsPunctuationOnTheLeftSide() {
        var machine = KeyStateMachine()
        let triggers = run([down(10), up(10), down(35)], on: &machine)
        #expect(triggers.map(\.label) == ["punctuation down", "punctuation up", "alpha down"])
        #expect(triggers[0].column < 0.2)
        #expect(triggers[2].column > 0.6)
    }

    @Test func unknownKeycodeStillSoundsAsAlpha() {
        #expect(sounds([down(200), up(200)]) == ["alpha down", "alpha up"])
    }
}

struct KeySetTests {
    @Test func tracksKeycodesAcrossAllFourWords() {
        var set = KeySet()
        let inserted = [0, 63, 64, 255, 64, 256].map { set.insert($0) }
        #expect(inserted == [true, true, true, true, false, false])
        #expect(set.count == 4)
        #expect(set.contains(255) && !set.contains(254))
        let removed = [63, 63].map { set.remove($0) }
        #expect(removed == [true, false])
        #expect(set.count == 3)
        set.removeAll()
        #expect(set.isEmpty)
    }
}
