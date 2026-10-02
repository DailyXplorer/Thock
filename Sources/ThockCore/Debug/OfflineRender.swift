import AVFoundation
import Dispatch

public struct TypedEvent: Sendable, Equatable {
    public var time: Double
    public var keycode: UInt16
    public var isDown: Bool
}

public enum TypingScript {
    static let backspace: UInt16 = 51
    static let keycodes: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38,
        "k": 40, "n": 45, "m": 46, ",": 43, ".": 47, " ": 49, "\n": 36,
    ]

    public static func standard(seed: UInt64 = 7) -> [TypedEvent] {
        var random = RandomSource(seed: seed)
        var events: [TypedEvent] = []
        var time = 0.3
        type("the quick brown fox jumps over the lazy dog, then types this line again.", wordsPerMinute: 100,
             at: &time, into: &events, random: &random)
        time += 0.6
        type("fast typing should sound like a real keyboard, not a machine gun.", wordsPerMinute: 140,
             at: &time, into: &events, random: &random)
        time += 0.25
        for _ in 0..<8 {
            press(backspace, at: time, hold: 0.04 + 0.03 * Double(random.unit()), into: &events)
            time += 0.06 + 0.02 * Double(random.unit())
        }
        time += 0.2
        type("keyboard.\n", wordsPerMinute: 140, at: &time, into: &events, random: &random)
        time += 0.6
        for (index, keycode) in [UInt16(0), 1, 2, 3, 49].enumerated() {
            press(keycode, at: time + 0.003 * Double(index), hold: 0.1, into: &events)
        }
        return events.sorted { $0.time < $1.time }
    }

    static func type(_ text: String, wordsPerMinute: Double, at time: inout Double, into events: inout [TypedEvent],
                     random: inout RandomSource) {
        let interval = 60 / (wordsPerMinute * 5)
        var lastUp: [UInt16: Double] = [:]
        for character in text {
            let keycode = keycodes[character]!
            time = max(time, (lastUp[keycode] ?? 0) + 0.015)
            let hold = 0.06 + 0.06 * Double(random.unit())
            press(keycode, at: time, hold: hold, into: &events)
            lastUp[keycode] = time + hold
            time += interval * (0.6 + 0.8 * Double(random.unit())) * (character == " " ? 1.2 : 1)
        }
    }

    static func press(_ keycode: UInt16, at time: Double, hold: Double, into events: inout [TypedEvent]) {
        events.append(TypedEvent(time: time, keycode: keycode, isDown: true))
        events.append(TypedEvent(time: time + hold, keycode: keycode, isDown: false))
    }
}

public struct RenderReport: Sendable {
    public var seconds: Double
    public var sounds: Int
    public var peakDecibels: Float
    public var clippedSamples: Int
    public var cutSounds: UInt64
    public var peakVoices: Int
    public var onsetDelayMeanMs: Double
    public var onsetDelayMinMs: Double
    public var onsetDelayMaxMs: Double
    public var intervalErrorMeanMs: Double
    public var intervalErrorMaxMs: Double
    public var mergedOnsets: Int

    public var summary: String {
        func f(_ value: Double, _ digits: Int = 2) -> String { String(format: "%.\(digits)f", value) }
        return """
        sounds \(sounds) over \(f(seconds, 1)) s
        peak \(f(Double(peakDecibels))) dBFS, clipped samples \(clippedSamples)
        cut sounds \(cutSounds), peak simultaneous voices \(peakVoices)
        onset delay mean \(f(onsetDelayMeanMs)) ms, min \(f(onsetDelayMinMs)) ms, max \(f(onsetDelayMaxMs)) ms
        interval error mean \(f(intervalErrorMeanMs)) ms, max \(f(intervalErrorMaxMs)) ms, merged onsets \(mergedOnsets)
        """
    }
}

public final class OfflineRender {
    public let sampleRate: Double
    public let cycleFrames = AVAudioFrameCount(AudioEngine.ioBufferFrames)
    private let source: PackSource

    public init(pack: PackSource, sampleRate: Double = 48_000) {
        source = pack
        self.sampleRate = sampleRate
    }

    public func render(_ events: [TypedEvent], seed: UInt64 = 1) throws -> (left: [Float], right: [Float], report: RenderReport) {
        let session = try Session(source: source, sampleRate: sampleRate, seed: seed)
        let seconds = (events.last?.time ?? 0) + 1
        let cycles = Int((seconds * sampleRate) / Double(cycleFrames)) + 1
        var left: [Float] = []
        var right: [Float] = []
        left.reserveCapacity(cycles * Int(cycleFrames))
        right.reserveCapacity(cycles * Int(cycleFrames))
        var next = 0
        for cycle in 0..<cycles {
            let start = cycle * Int(cycleFrames)
            var batch: [TypedEvent] = []
            while next < events.count, frame(events[next].time) <= start {
                batch.append(events[next])
                next += 1
            }
            try session.render(cycle: cycle, events: batch, frame: frame, into: &left, &right)
        }

        let triggered = session.triggeredFrames
        let delays = try measureOnsetDelays(at: triggered)
        let onsets = zip(triggered, delays).map { $0 + $1 }
        let delayMs = zip(onsets, triggered).map { Double($0 - $1) / sampleRate * 1_000 }
        var intervalErrors: [Double] = []
        var merged = 0
        for i in 1..<max(1, triggered.count) {
            let eventGap = triggered[i] - triggered[i - 1]
            let onsetGap = onsets[i] - onsets[i - 1]
            intervalErrors.append(Double(abs(onsetGap - eventGap)) / sampleRate * 1_000)
            if onsetGap == 0, Double(eventGap) >= sampleRate * 0.0005 { merged += 1 }
        }
        let peak = max(left.reduce(0) { max($0, abs($1)) }, right.reduce(0) { max($0, abs($1)) })
        let report = RenderReport(
            seconds: Double(left.count) / sampleRate,
            sounds: triggered.count,
            peakDecibels: 20 * log10(max(peak, 1e-9)),
            clippedSamples: left.count(where: { abs($0) > 1 }) + right.count(where: { abs($0) > 1 }),
            cutSounds: session.audio.stats.stolen,
            peakVoices: session.audio.sampler.stats.peakVoices,
            onsetDelayMeanMs: delayMs.reduce(0, +) / Double(max(1, delayMs.count)),
            onsetDelayMinMs: delayMs.min() ?? 0,
            onsetDelayMaxMs: delayMs.max() ?? 0,
            intervalErrorMeanMs: intervalErrors.reduce(0, +) / Double(max(1, intervalErrors.count)),
            intervalErrorMaxMs: intervalErrors.max() ?? 0,
            mergedOnsets: merged)
        return (left, right, report)
    }

    func measureOnsetDelays(at frames: [Int]) throws -> [Int] {
        let cycle = Int(cycleFrames)
        let session = try Session(source: source, sampleRate: sampleRate, seed: 1)
        var delays: [Int] = []
        var left: [Float] = []
        var right: [Float] = []
        for offset in frames.map({ $0 % cycle }) {
            session.restart()
            left.removeAll(keepingCapacity: true)
            right.removeAll(keepingCapacity: true)
            let eventFrame = 2 * cycle + offset
            let event = TypedEvent(time: Double(eventFrame) / sampleRate, keycode: 0, isDown: true)
            var pending = true
            for index in 0..<8 {
                let due = pending && eventFrame <= index * cycle
                if due { pending = false }
                try session.render(cycle: index, events: due ? [event] : [], frame: frame, into: &left, &right)
            }
            guard let onset = left.indices.first(where: { left[$0] != 0 || right[$0] != 0 }) else {
                throw OfflineRenderError.silentProbe
            }
            delays.append(onset - eventFrame)
        }
        return delays
    }

    private func frame(_ time: Double) -> Int {
        Int((time * sampleRate).rounded())
    }
}

public enum OfflineRenderError: Error {
    case silentProbe
}

private final class Session {
    let audio: AudioEngine
    let pipeline: InputPipeline
    let queue = DispatchQueue(label: "com.louis.thock.render")
    let clock: Clock
    let sampleRate: Double
    let buffer: AVAudioPCMBuffer
    private(set) var triggeredFrames: [Int] = []

    final class Clock: @unchecked Sendable {
        let origin = HostClock.now
        var now: UInt64 = 0
        var triggers: [UInt64] = []
    }

    init(source: PackSource, sampleRate: Double, seed: UInt64) throws {
        self.sampleRate = sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let engine = AVAudioEngine()
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4_096)
        buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(AudioEngine.ioBufferFrames))!
        let audio = AudioEngine(queue: queue, engine: engine, voices: 32, seed: seed)
        let clock = Clock()
        self.audio = audio
        self.clock = clock
        pipeline = InputPipeline(queue: queue) { trigger, timestamp in
            clock.triggers.append(timestamp)
            audio.play(trigger, eventTimestamp: timestamp, now: clock.now)
        }
        audio.setPack(source)
        audio.start()
        queue.sync {}
    }

    func restart() {
        queue.sync {
            audio.reconfigure(reason: "restart")
        }
    }

    func render(cycle: Int, events: [TypedEvent], frame: (Double) -> Int, into left: inout [Float], _ right: inout [Float]) throws {
        let cycleFrames = Int(AudioEngine.ioBufferFrames)
        let hostTicks = { (frames: Int) in HostClock.ticks(nanoseconds: UInt64(Double(frames) / self.sampleRate * 1e9)) }
        if !events.isEmpty {
            for event in events {
                pipeline.ring.push(RawInputEvent(kind: event.isDown ? .keyDown : .keyUp, keycode: event.keycode,
                                                 timestamp: clock.origin + hostTicks(frame(event.time))))
            }
            clock.now = clock.origin + hostTicks(cycle * cycleFrames)
            clock.triggers.removeAll(keepingCapacity: true)
            queue.sync { pipeline.drain() }
            for timestamp in clock.triggers {
                let nanoseconds = HostClock.nanoseconds(timestamp - clock.origin)
                triggeredFrames.append(Int((Double(nanoseconds) / 1e9 * sampleRate).rounded()))
            }
        }
        let cycleHost = clock.origin + hostTicks(cycle * cycleFrames)
        try queue.sync {
            audio.sampler.setManualCycleHost(cycleHost)
            guard try audio.engine.renderOffline(AVAudioFrameCount(cycleFrames), to: buffer) == .success else {
                throw OfflineRenderError.silentProbe
            }
        }
        let frames = Int(buffer.frameLength)
        left.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![0], count: frames))
        right.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![1], count: frames))
    }
}

public enum WAVWriter {
    public static func write(left: [Float], right: [Float], sampleRate: Double, to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(left.count))!
        buffer.frameLength = AVAudioFrameCount(left.count)
        for (channel, samples) in [left, right].enumerated() {
            let data = buffer.floatChannelData![channel]
            for i in samples.indices {
                data[i] = min(max(samples[i], -1), 1)
            }
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 24, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }
}
