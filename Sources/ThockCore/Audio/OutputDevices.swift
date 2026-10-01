import AudioToolbox
import CoreAudio
import Dispatch

public struct OutputDevice: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    let deviceID: AudioDeviceID
}

public enum OutputDevices {
    public static func all() -> [OutputDevice] {
        var address = AudioObjectPropertyAddress(selector: kAudioHardwarePropertyDevices, scope: kAudioObjectPropertyScopeGlobal)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasOutputStreams(id), let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            return OutputDevice(id: uid, name: name, deviceID: id)
        }
    }

    public static var defaultOutput: AudioDeviceID? {
        let id: AudioDeviceID? = value(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice)
        return id == kAudioObjectUnknown ? nil : id
    }

    public static func device(uid: String) -> AudioDeviceID? {
        all().first { $0.id == uid }?.deviceID
    }

    public static func isMuted(_ device: AudioDeviceID) -> Bool {
        let muted: UInt32? = value(device, kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)
        return muted == 1
    }

    static func outputLatencyFrames(_ device: AudioDeviceID) -> UInt32 {
        let deviceLatency: UInt32 = value(device, kAudioDevicePropertyLatency, scope: kAudioObjectPropertyScopeOutput) ?? 0
        let safetyOffset: UInt32 = value(device, kAudioDevicePropertySafetyOffset, scope: kAudioObjectPropertyScopeOutput) ?? 0
        var streamLatency: UInt32 = 0
        if let stream: AudioStreamID = firstOutputStream(device) {
            streamLatency = value(stream, kAudioStreamPropertyLatency) ?? 0
        }
        return deviceLatency + safetyOffset + streamLatency
    }

    private static func hasOutputStreams(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(selector: kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func firstOutputStream(_ device: AudioDeviceID) -> AudioStreamID? {
        var address = AudioObjectPropertyAddress(selector: kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        var size = UInt32(MemoryLayout<AudioStreamID>.size)
        var stream: AudioStreamID = 0
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &stream)
        return status == noErr && size > 0 ? stream : nil
    }

    private static func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                 scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> T? {
        var address = AudioObjectPropertyAddress(selector: selector, scope: scope)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<T>.size, alignment: MemoryLayout<T>.alignment)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.load(as: T.self)
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(selector: selector, scope: kAudioObjectPropertyScopeGlobal)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var result: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &result) == noErr, let result else { return nil }
        return result.takeRetainedValue() as String
    }
}

@MainActor
public final class OutputDeviceMonitor {
    private let onDevicesChanged: @MainActor () -> Void
    private let onSystemMuteChanged: @MainActor (Bool) -> Void
    private var hardwareListener: AudioObjectPropertyListenerBlock?
    private var muteListener: AudioObjectPropertyListenerBlock?
    private var mutedDevice: AudioDeviceID?

    public init(onDevicesChanged: @escaping @MainActor () -> Void, onSystemMuteChanged: @escaping @MainActor (Bool) -> Void) {
        self.onDevicesChanged = onDevicesChanged
        self.onSystemMuteChanged = onSystemMuteChanged
    }

    public func start() {
        guard hardwareListener == nil else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.watchDefaultOutputMute()
                self.onDevicesChanged()
            }
        }
        hardwareListener = listener
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var address = AudioObjectPropertyAddress(selector: selector, scope: kAudioObjectPropertyScopeGlobal)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
        watchDefaultOutputMute()
    }

    private func watchDefaultOutputMute() {
        let device = OutputDevices.defaultOutput
        if device != mutedDevice {
            if let mutedDevice, let muteListener {
                var address = Self.muteAddress
                AudioObjectRemovePropertyListenerBlock(mutedDevice, &address, .main, muteListener)
            }
            mutedDevice = device
            if let device {
                let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.reportMute() }
                }
                muteListener = listener
                var address = Self.muteAddress
                AudioObjectAddPropertyListenerBlock(device, &address, .main, listener)
            }
        }
        reportMute()
    }

    private func reportMute() {
        onSystemMuteChanged(mutedDevice.map(OutputDevices.isMuted) ?? false)
    }

    private static let muteAddress = AudioObjectPropertyAddress(selector: kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)
}

extension AudioObjectPropertyAddress {
    init(selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) {
        self.init(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}
