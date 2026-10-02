import CoreAudio
import Darwin
import Dispatch
import os

@MainActor
public final class MicrophoneMonitor {
    private let onChange: @MainActor (Bool) -> Void
    private let outputDevice: @MainActor () -> AudioDeviceID?
    private let logger = Logger(subsystem: AppIdentity.subsystem, category: "microphone")

    private var systemListener: AudioObjectPropertyListenerBlock?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var watchedInput: AudioDeviceID?
    private var watchedProcesses: [AudioObjectID] = []
    private var lastReported: Bool?

    public init(outputDevice: @escaping @MainActor () -> AudioDeviceID?, onChange: @escaping @MainActor (Bool) -> Void) {
        self.outputDevice = outputDevice
        self.onChange = onChange
    }

    public var isRunning: Bool { systemListener != nil }

    public func start() {
        guard systemListener == nil else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        systemListener = listener
        for selector in Self.systemSelectors {
            var address = AudioObjectPropertyAddress(selector: selector, scope: kAudioObjectPropertyScopeGlobal)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
        let input = Self.defaultInput
        let readable = input.flatMap { Self.uint32($0, kAudioDevicePropertyDeviceIsRunningSomewhere) } != nil
        var processes = -1
        if #available(macOS 14.2, *) { processes = Self.audioProcesses().count }
        logger.notice("Monitor started: default input \(input != nil, privacy: .public), running state readable \(readable, privacy: .public), audio processes \(processes, privacy: .public)")
        refresh()
    }

    public func stop() {
        guard let systemListener else { return }
        for selector in Self.systemSelectors {
            var address = AudioObjectPropertyAddress(selector: selector, scope: kAudioObjectPropertyScopeGlobal)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, systemListener)
        }
        self.systemListener = nil
        watch(input: nil)
        watch(processes: [])
        lastReported = nil
    }

    public func refresh() {
        guard systemListener != nil else { return }
        let input = Self.defaultInput
        watch(input: input)
        let inUse: Bool
        // A duplex device also runs for playback, so only per-process input state proves recording.
        if let input, Self.hasOutputStreams(input), #available(macOS 14.2, *) {
            let processes = Self.audioProcesses()
            watch(processes: processes)
            inUse = processes.contains(where: Self.recordsInput)
        } else {
            watch(processes: [])
            inUse = input.map { $0 != outputDevice() && Self.isRunningSomewhere($0) } ?? false
        }
        guard inUse != lastReported else { return }
        lastReported = inUse
        logger.notice("Microphone in use: \(inUse, privacy: .public)")
        onChange(inUse)
    }

    private func watch(input: AudioDeviceID?) {
        guard input != watchedInput else { return }
        if let watchedInput, let deviceListener {
            var address = Self.runningSomewhereAddress
            AudioObjectRemovePropertyListenerBlock(watchedInput, &address, .main, deviceListener)
        }
        watchedInput = input
        guard let input else { return }
        let listener = deviceListener ?? { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        deviceListener = listener
        var address = Self.runningSomewhereAddress
        AudioObjectAddPropertyListenerBlock(input, &address, .main, listener)
    }

    private func watch(processes: [AudioObjectID]) {
        guard processes != watchedProcesses else { return }
        guard #available(macOS 14.2, *) else { return }
        let listener = deviceListener ?? { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        deviceListener = listener
        var address = AudioObjectPropertyAddress(selector: kAudioProcessPropertyIsRunningInput, scope: kAudioObjectPropertyScopeGlobal)
        for process in watchedProcesses where !processes.contains(process) {
            AudioObjectRemovePropertyListenerBlock(process, &address, .main, listener)
        }
        for process in processes where !watchedProcesses.contains(process) {
            AudioObjectAddPropertyListenerBlock(process, &address, .main, listener)
        }
        watchedProcesses = processes
    }

    private static var systemSelectors: [AudioObjectPropertySelector] {
        var selectors = [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDefaultOutputDevice]
        if #available(macOS 14.2, *) { selectors.append(kAudioHardwarePropertyProcessObjectList) }
        return selectors
    }

    private static let runningSomewhereAddress = AudioObjectPropertyAddress(
        selector: kAudioDevicePropertyDeviceIsRunningSomewhere, scope: kAudioObjectPropertyScopeGlobal)

    private static var defaultInput: AudioDeviceID? {
        var address = AudioObjectPropertyAddress(selector: kAudioHardwarePropertyDefaultInputDevice, scope: kAudioObjectPropertyScopeGlobal)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func hasOutputStreams(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(selector: kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func isRunningSomewhere(_ device: AudioDeviceID) -> Bool {
        uint32(device, kAudioDevicePropertyDeviceIsRunningSomewhere) == 1
    }

    @available(macOS 14.2, *)
    private static func audioProcesses() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(selector: kAudioHardwarePropertyProcessObjectList, scope: kAudioObjectPropertyScopeGlobal)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return Array(objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    @available(macOS 14.2, *)
    private static func recordsInput(_ process: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(selector: kAudioProcessPropertyPID, scope: kAudioObjectPropertyScopeGlobal)
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &pid) == noErr, pid != getpid() else { return false }
        return uint32(process, kAudioProcessPropertyIsRunningInput) == 1
    }

    private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(selector: selector, scope: kAudioObjectPropertyScopeGlobal)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }
}
