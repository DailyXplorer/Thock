import AVFoundation
import AudioToolbox
import os

public struct MuteReasons: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let manual = MuteReasons(rawValue: 1 << 0)
    public static let systemOutputMuted = MuteReasons(rawValue: 1 << 1)
    public static let microphoneInUse = MuteReasons(rawValue: 1 << 2)
    public static let excludedApp = MuteReasons(rawValue: 1 << 3)
}

public struct SuspendReasons: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let sleep = SuspendReasons(rawValue: 1 << 0)
    public static let screenLocked = SuspendReasons(rawValue: 1 << 1)
    public static let sessionInactive = SuspendReasons(rawValue: 1 << 2)
}

public struct AudioStats: Sendable, Equatable {
    public var isRunning = false
    public var sampleRate: Double = 0
    public var packID: String?
    public var played: UInt64 = 0
    public var stale: UInt64 = 0
    public var stolen: UInt64 = 0
    public var late: UInt64 = 0
    public var invalidTimestamps: UInt64 = 0
    public var rebuilds: UInt64 = 0
    public var ioBufferFrames: UInt32 = 0
    public var outputLatencyMs: Double = 0
    public var latencyP50Us: Double?
    public var latencyP99Us: Double?
    public var latencySamples = 0
}

public final class AudioEngine: @unchecked Sendable {
    public static let staleLimit: UInt64 = 250_000_000
    public static let ioBufferFrames: UInt32 = 128

    public let queue: DispatchQueue
    let engine: AVAudioEngine
    let sampler: Sampler
    private let logger = Logger(subsystem: AppIdentity.subsystem, category: "audio")
    private let metrics = OSAllocatedUnfairLock(initialState: Metrics())

    private var started = false
    private var suspended: SuspendReasons = []
    private var muted: MuteReasons = []
    private var source: PackSource?
    private(set) var pack: LoadedPack?
    private var lastPick = ContiguousArray<Int>(repeating: -1, count: SoundKey.count)
    private var random: RandomSource
    private var lastSoundEnd: UInt64 = 0
    private var queuedVoicesEnd: UInt64 = 0
    private var spatial = true
    private var mouseSounds = false
    private var selectedOutput: String?
    private var measuringLatency = false
    private let staleLimitTicks = HostClock.ticks(nanoseconds: AudioEngine.staleLimit)
    private let invalidAgeTicks = HostClock.ticks(nanoseconds: 10_000_000_000)
    private var configurationObserver: NSObjectProtocol?

    private struct Metrics {
        var stats = AudioStats()
        var latency = LatencyHistogram()
    }

    public init(queue: DispatchQueue, engine: AVAudioEngine = AVAudioEngine(), voices: Int = 32, seed: UInt64 = HostClock.now) {
        self.queue = queue
        self.engine = engine
        random = RandomSource(seed: seed)
        sampler = Sampler(voiceCount: voices)
        engine.attach(sampler.node)
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            queue.async { self.reconfigure(reason: "configuration change") }
        }
    }

    deinit {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
    }

    public var stats: AudioStats {
        metrics.withLock { metrics in
            var stats = metrics.stats
            stats.latencyP50Us = metrics.latency.percentile(0.5)
            stats.latencyP99Us = metrics.latency.percentile(0.99)
            stats.latencySamples = metrics.latency.count
            (stats.stolen, stats.late, _) = sampler.stats
            return stats
        }
    }

    public func start() {
        queue.async {
            guard !self.started else { return }
            self.started = true
            self.reconfigure(reason: "start")
        }
    }

    public func setPack(_ source: PackSource) {
        queue.async {
            self.source = source
            let sampleRate = self.outputSampleRate
            if let retired = self.pack {
                let now = HostClock.now
                let playing = self.queuedVoicesEnd > now ? HostClock.nanoseconds(self.queuedVoicesEnd - now) : 0
                self.queue.asyncAfter(deadline: .now() + .nanoseconds(Int(playing)) + 1) { withExtendedLifetime(retired) {} }
            }
            self.pack = PackLoader.render(source, sampleRate: sampleRate > 0 ? sampleRate : PackSource.sampleRate)
            self.lastPick.withUnsafeMutableBufferPointer { $0.update(repeating: -1) }
            self.metrics.withLock { $0.stats.packID = source.id }
        }
    }

    public func setVolume(_ volume: Float) {
        queue.async { self.engine.mainMixerNode.outputVolume = min(max(volume, 0), 1) }
    }

    public func setSpatialization(_ enabled: Bool) {
        queue.async { self.spatial = enabled }
    }

    public func setMouseSounds(_ enabled: Bool) {
        queue.async { self.mouseSounds = enabled }
    }

    public func setMuted(_ reasons: MuteReasons) {
        queue.async { self.muted = reasons }
    }

    public func setSuspended(_ reason: SuspendReasons, _ on: Bool) {
        queue.async {
            let wasSuspended = !self.suspended.isEmpty
            if on { self.suspended.insert(reason) } else { self.suspended.remove(reason) }
            guard wasSuspended != !self.suspended.isEmpty else { return }
            self.reconfigure(reason: on ? "suspend" : "resume")
        }
    }

    public func setOutputDevice(uid: String?) {
        queue.async {
            self.selectedOutput = uid
            self.reconfigure(reason: "output selected")
        }
    }

    public func refreshRoute() {
        queue.async {
            guard self.started, !self.engine.isInManualRenderingMode, self.routedDevice != self.currentDevice else { return }
            self.reconfigure(reason: "route change")
        }
    }

    public func setLatencyMeasurement(_ enabled: Bool) {
        queue.async {
            self.measuringLatency = enabled
            self.metrics.withLock { $0.latency.reset() }
        }
    }

    public func play(_ trigger: SoundTrigger, eventTimestamp: UInt64) {
        play(trigger, eventTimestamp: eventTimestamp, now: HostClock.now)
    }

    func play(_ trigger: SoundTrigger, eventTimestamp: UInt64, now: UInt64) {
        guard let pack, muted.isEmpty, engine.isRunning, mouseSounds || trigger.category != .mouse else { return }
        let age = now &- eventTimestamp
        let timestampValid = eventTimestamp != 0 && eventTimestamp <= now && age < invalidAgeTicks
        if timestampValid, age > staleLimitTicks {
            metrics.withLock { $0.stats.stale += 1 }
            return
        }

        let key = SoundKey(trigger).index
        let choices = pack.choices[key]
        guard !choices.isEmpty else { return }
        let pick = random.index(count: choices.count, avoiding: lastPick[key])
        lastPick[key] = pick
        let clip = pack.clips[choices[pick]]

        let variation = trigger.direction == .down ? Variation.press : Variation.release
        let rate = 1 + random.spread(variation.rate)
        let duration = HostClock.ticks(nanoseconds: UInt64(Double(clip.count) / Double(rate) / pack.sampleRate * 1e9))
        let start: UInt64
        switch trigger.timing {
        case .immediate:
            start = timestampValid ? eventTimestamp : now
            lastSoundEnd = start &+ duration
        case .afterPress:
            start = lastSoundEnd
        }
        queuedVoicesEnd = max(queuedVoicesEnd, max(start, now) &+ duration)
        let pan = spatial ? (trigger.column * 2 - 1) * 0.6 : 0
        let queued = sampler.play(VoiceCommand(
            samples: clip.samples, eventTime: start, length: UInt32(clip.count), rate: rate,
            gain: random.attenuation(upTo: variation.attenuation), pan: Int16(pan * 32_767),
            dulling: Int16(random.unit() * variation.dulling * 32_767)))

        let scheduled = measuringLatency ? HostClock.now : 0
        metrics.withLock { metrics in
            if queued { metrics.stats.played += 1 }
            if !timestampValid {
                metrics.stats.invalidTimestamps += 1
            } else if scheduled != 0 {
                metrics.latency.record(nanoseconds: HostClock.nanoseconds(scheduled &- eventTimestamp))
            }
        }
    }

    var outputSampleRate: Double {
        engine.isInManualRenderingMode ? engine.manualRenderingFormat.sampleRate : engine.outputNode.outputFormat(forBus: 0).sampleRate
    }

    func reconfigure(reason: StaticString) {
        engine.stop()
        guard started, suspended.isEmpty else {
            publishState()
            return
        }
        if !engine.isInManualRenderingMode {
            applyOutputDevice()
            setIOBufferSize()
        }

        let sampleRate = outputSampleRate
        guard sampleRate > 0 else {
            logger.error("No output device, engine left stopped")
            publishState()
            return
        }
        if let source, pack?.sampleRate != sampleRate {
            pack = PackLoader.render(source, sampleRate: sampleRate)
        }

        let mixer = engine.mainMixerNode
        sampler.reset(sampleRate: sampleRate)
        engine.connect(sampler.node, to: mixer, format: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2))
        let output = engine.isInManualRenderingMode ? engine.manualRenderingFormat : engine.outputNode.outputFormat(forBus: 0)
        engine.connect(mixer, to: engine.outputNode,
                       format: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: max(1, min(output.channelCount, 2))))
        engine.prepare()
        do {
            try engine.start()
            logger.notice("Engine started (\(reason, privacy: .public)) at \(sampleRate, privacy: .public) Hz")
        } catch {
            logger.error("Engine start failed (\(reason, privacy: .public)): \(error.localizedDescription, privacy: .public)")
        }
        metrics.withLock { $0.stats.rebuilds += 1 }
        publishState()
    }

    private func publishState() {
        let running = engine.isRunning
        let sampleRate = running ? outputSampleRate : 0
        var bufferFrames: UInt32 = 0
        var latencyMs = 0.0
        if running, !engine.isInManualRenderingMode, let device = currentDevice, let unit = engine.outputNode.audioUnit {
            bufferFrames = Self.property(unit, kAudioDevicePropertyBufferFrameSize) ?? 0
            latencyMs = Double(bufferFrames + OutputDevices.outputLatencyFrames(device)) / sampleRate * 1_000
        }
        let (frames, latency) = (bufferFrames, latencyMs)
        metrics.withLock {
            $0.stats.isRunning = running
            $0.stats.sampleRate = sampleRate
            $0.stats.ioBufferFrames = frames
            $0.stats.outputLatencyMs = latency
        }
    }

    private var routedDevice: AudioDeviceID? {
        selectedOutput.flatMap(OutputDevices.device(uid:)) ?? OutputDevices.defaultOutput
    }

    private var currentDevice: AudioDeviceID? {
        engine.outputNode.audioUnit.flatMap { Self.property($0, kAudioOutputUnitProperty_CurrentDevice) }
    }

    private func applyOutputDevice() {
        guard var device = routedDevice, device != currentDevice, let unit = engine.outputNode.audioUnit else { return }
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                          &device, UInt32(MemoryLayout<AudioDeviceID>.size))
        if status != noErr {
            logger.error("Selecting the output device failed: \(status, privacy: .public)")
        }
    }

    private func setIOBufferSize() {
        guard let unit = engine.outputNode.audioUnit else { return }
        var frames = Self.ioBufferFrames
        AudioUnitSetProperty(unit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0,
                             &frames, UInt32(MemoryLayout<UInt32>.size))
    }

    private static func property<T: FixedWidthInteger>(_ unit: AudioUnit, _ id: AudioUnitPropertyID) -> T? {
        var value: T = 0
        var size = UInt32(MemoryLayout<T>.size)
        return AudioUnitGetProperty(unit, id, kAudioUnitScope_Global, 0, &value, &size) == noErr ? value : nil
    }
}
