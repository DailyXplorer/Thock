import AppKit
import Carbon.HIToolbox

public struct KeyCombo: Codable, Sendable, Hashable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32
    public var keyLabel: String

    public init(keyCode: UInt32, carbonModifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.keyLabel = keyLabel
    }

    public static let defaultToggle = KeyCombo(keyCode: UInt32(kVK_ANSI_K),
                                               carbonModifiers: UInt32(controlKey | optionKey | cmdKey), keyLabel: "K")

    public enum Rejection: Error, Equatable {
        case needsCommandOrControl
    }

    public static func from(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String?) -> Result<KeyCombo, Rejection> {
        var carbon: UInt32 = 0
        if modifiers.contains(.control) { carbon |= UInt32(controlKey) }
        if modifiers.contains(.option) { carbon |= UInt32(optionKey) }
        if modifiers.contains(.shift) { carbon |= UInt32(shiftKey) }
        if modifiers.contains(.command) { carbon |= UInt32(cmdKey) }
        guard carbon & UInt32(controlKey | cmdKey) != 0 else { return .failure(.needsCommandOrControl) }
        let label = specialKeyLabels[Int(keyCode)] ?? characters.map { $0.uppercased() }.flatMap { $0.isEmpty ? nil : $0 } ?? "?"
        return .success(KeyCombo(keyCode: UInt32(keyCode), carbonModifiers: carbon, keyLabel: label))
    }

    public var displayString: String {
        var text = ""
        if carbonModifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + keyLabel
    }

    private static let specialKeyLabels: [Int: String] = [
        kVK_Space: "Espace", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}

@MainActor
public final class HotKey {
    private static let signature: OSType = 0x5448_4F4B

    private let action: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    public init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @discardableResult
    public func register(_ combo: KeyCombo) -> Bool {
        unregister()
        installHandler()
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, EventHotKeyID(signature: Self.signature, id: 1),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        hotKeyRef = ref
        return true
    }

    public func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandler() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }
}
