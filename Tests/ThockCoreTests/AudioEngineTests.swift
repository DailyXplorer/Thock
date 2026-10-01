import AVFoundation
import Dispatch
import os
import Testing
@testable import ThockCore

private let press = SoundTrigger(category: .alpha, direction: .down, column: 0.3, row: 3, timing: .immediate)

private final class OfflineRig: Sendable {
    let audio: AudioEngine
    let queue = DispatchQueue(label: "test.audio")

    init(sampleRate: Double = 48_000, pack: String = "holypanda", voices: Int = 32) throws {
        let engine = AVAudioEngine()
        try engine.enableManualRenderingMode(.offline, format: Self.format(sampleRate), maximumFrameCount: 4_096)
        audio = AudioEngine(queue: queue, engine: engine, voices: voices, seed: 3)
        audio.setPack(try PackLoader.load(directory: Fixtures.bundledPack(pack)))
        audio.start()
        sync()
    }

    static func format(_ sampleRate: Double) -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    }

    func sync() {
        queue.sync {}
    }

    func play(_ trigger: SoundTrigger = press, age nanoseconds: UInt64 = 0, timestamp: UInt64? = nil) {
        queue.sync {
            audio.play(trigger, eventTimestamp: timestamp ?? HostClock.now - HostClock.ticks(nanoseconds: nanoseconds))
        }
    }

    func renderPeak(frames: AVAudioFrameCount = 4_096) throws -> Float {
        try queue.sync {
            let engine = audio.engine
            let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: AudioEngine.ioBufferFrames)!
            var peak: Float = 0
            for _ in 0..<frames / AudioEngine.ioBufferFrames {
                let status = try engine.renderOffline(AudioEngine.ioBufferFrames, to: buffer)
                #expect(status == .success)
                peak = max(peak, buffer.peak)
            }
            return peak
        }
    }

    func simulateConfigurationChange(sampleRate: Double? = nil) throws {
        try queue.sync {
            let engine = audio.engine
            if let sampleRate {
                engine.stop()
                engine.disableManualRenderingMode()
                try engine.enableManualRenderingMode(.offline, format: Self.format(sampleRate), maximumFrameCount: 4_096)
            }
            NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: engine)
        }
        sync()
    }

    var pack: LoadedPack? { queue.sync { audio.pack } }
    var attachedNodes: Int { queue.sync { audio.engine.attachedNodes.count } }
    var isRunning: Bool { queue.sync { audio.engine.isRunning } }
}

struct AudioEngineTests {
    @Test func playsAKeystrokeAt48kHz() throws {
        let rig = try OfflineRig()
        #expect(rig.isRunning)
        #expect(rig.pack?.sampleRate == 48_000)
        #expect(try rig.renderPeak() == 0)
        rig.play()
        #expect(try rig.renderPeak() > 0.05)
        #expect(rig.audio.stats.played == 1)
    }

    @Test func rebuildConvertsTheBuffersWhenTheRateDropsTo44_1kHz() throws {
        let rig = try OfflineRig()
        let before = try #require(rig.pack)
        let frames48 = before.samples(for: SoundSlot(.alpha, .down), row: 3)[0].count
        let rebuilds = rig.audio.stats.rebuilds

        try rig.simulateConfigurationChange(sampleRate: 44_100)

        let after = try #require(rig.pack)
        #expect(after !== before)
        #expect(after.sampleRate == 44_100)
        let frames44 = after.samples(for: SoundSlot(.alpha, .down), row: 3)[0].count
        #expect(abs(frames44 - frames48 * 441 / 480) <= 2)
        #expect(rig.isRunning)
        #expect(rig.audio.stats.rebuilds == rebuilds + 1)
        #expect(rig.audio.stats.sampleRate == 44_100)
        rig.play()
        #expect(try rig.renderPeak() > 0.05)
    }

    @Test func rebuildIsIdempotent() throws {
        let rig = try OfflineRig()
        try rig.simulateConfigurationChange(sampleRate: 44_100)
        let pack = try #require(rig.pack)
        let nodes = rig.attachedNodes

        try rig.simulateConfigurationChange()
        try rig.simulateConfigurationChange()

        #expect(rig.pack === pack)
        #expect(rig.attachedNodes == nodes)
        #expect(nodes == 1 + 2)
        #expect(rig.isRunning)
        rig.play()
        #expect(try rig.renderPeak() > 0.05)
    }

    @Test func dropsEventsThatWaitedMoreThan250ms() throws {
        let rig = try OfflineRig()
        rig.play(age: 300_000_000)
        #expect(try rig.renderPeak() == 0)
        rig.play(age: 50_000_000)
        #expect(try rig.renderPeak() > 0.05)
        let stats = rig.audio.stats
        #expect(stats.stale == 1)
        #expect(stats.played == 1)
    }

    @Test func playsEventsWhoseTimestampIsNotOnTheHostClock() throws {
        let rig = try OfflineRig()
        rig.play(timestamp: 0)
        rig.play(timestamp: HostClock.now + HostClock.ticks(nanoseconds: 60_000_000_000))
        #expect(try rig.renderPeak() > 0.05)
        #expect(rig.audio.stats.invalidTimestamps == 2)
        #expect(rig.audio.stats.stale == 0)
    }

    @Test func muteSilencesWithoutStoppingTheEngine() throws {
        let rig = try OfflineRig()
        rig.audio.setMuted([.microphoneInUse, .excludedApp])
        rig.play()
        #expect(try rig.renderPeak() == 0)
        #expect(rig.isRunning)
        rig.audio.setMuted([])
        rig.play()
        #expect(try rig.renderPeak() > 0.05)
    }

    @Test func mouseClicksAreSilentUntilEnabled() throws {
        let rig = try OfflineRig()
        let click = SoundTrigger(category: .mouse, direction: .down, column: 0.03, row: 2, timing: .immediate)
        rig.play(click)
        #expect(try rig.renderPeak() == 0)
        rig.audio.setMouseSounds(true)
        rig.play(click)
        #expect(try rig.renderPeak() > 0.05)
    }

    @Test func staysStoppedUntilEverySuspensionClears() throws {
        let rig = try OfflineRig()
        rig.audio.setSuspended(.sleep, true)
        rig.audio.setSuspended(.screenLocked, true)
        rig.sync()
        #expect(!rig.isRunning)
        rig.audio.setSuspended(.sleep, false)
        rig.sync()
        #expect(!rig.isRunning)
        rig.audio.setSuspended(.screenLocked, false)
        rig.sync()
        #expect(rig.isRunning)
        rig.play()
        #expect(try rig.renderPeak() > 0.05)
    }

    @Test func capsLockReleaseFollowsThePress() throws {
        func secondWindowPeak(queueRelease: Bool) throws -> Float {
            let rig = try OfflineRig()
            rig.play(SoundTrigger(category: .modifier, direction: .down, column: 0.1, row: 3, timing: .immediate))
            if queueRelease {
                rig.play(SoundTrigger(category: .modifier, direction: .up, column: 0.1, row: 3, timing: .afterPress))
            }
            _ = try rig.renderPeak()
            #expect(rig.audio.stats.played == (queueRelease ? 2 : 1))
            return try rig.renderPeak()
        }
        let tailOnly = try secondWindowPeak(queueRelease: false)
        let withRelease = try secondWindowPeak(queueRelease: true)
        #expect(withRelease > tailOnly * 2)
    }

    @Test func spatializationPansByColumn() throws {
        func channelPeaks(spatial: Bool) throws -> (left: Float, right: Float) {
            let rig = try OfflineRig()
            rig.audio.setSpatialization(spatial)
            rig.play(SoundTrigger(category: .alpha, direction: .down, column: 0, row: 3, timing: .immediate))
            return try rig.queue.sync {
                let engine = rig.audio.engine
                let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: AudioEngine.ioBufferFrames)!
                var peaks: (left: Float, right: Float) = (0, 0)
                for _ in 0..<32 {
                    _ = try engine.renderOffline(AudioEngine.ioBufferFrames, to: buffer)
                    func peak(_ channel: Int) -> Float {
                        UnsafeBufferPointer(start: buffer.floatChannelData![channel], count: Int(buffer.frameLength)).reduce(0) { max($0, abs($1)) }
                    }
                    peaks = (max(peaks.left, peak(0)), max(peaks.right, peak(1)))
                }
                return peaks
            }
        }
        let panned = try channelPeaks(spatial: true)
        #expect(panned.left > panned.right * 2)
        let centered = try channelPeaks(spatial: false)
        #expect(abs(centered.left - centered.right) < 0.01)
    }

    @Test func allocationCounterSeesAllocations() {
        let allocations = AllocationCounter.count { AllocationCounter.keep(NSMutableData(length: 64)) }
        #expect(allocations >= 1)
    }

    @Test func inputPathAllocatesNothing() {
        let queue = DispatchQueue(label: "test.input")
        let played = OSAllocatedUnfairLock(initialState: 0)
        let pipeline = InputPipeline(queue: queue) { _, _ in played.withLock { $0 += 1 } }
        Self.push(keystrokes: 16, into: pipeline.ring)
        queue.sync { pipeline.drain() }
        Self.push(keystrokes: 100, into: pipeline.ring)
        let allocations = queue.sync { AllocationCounter.count { pipeline.drain() } }
        #expect(allocations == 0)
        #expect(played.withLock { $0 } == 232)
    }

    @Test func audioPathAllocatesNothing() throws {
        let rig = try OfflineRig()
        let pipeline = InputPipeline(queue: rig.queue) { [audio = rig.audio] trigger, timestamp in
            audio.play(trigger, eventTimestamp: timestamp)
        }
        Self.push(keystrokes: 16, into: pipeline.ring)
        rig.queue.sync { pipeline.drain() }
        _ = try rig.renderPeak()
        Self.push(keystrokes: 100, into: pipeline.ring)
        let allocations = rig.queue.sync { AllocationCounter.count { pipeline.drain() } }
        #expect(allocations == 0)
        #expect(rig.audio.stats.played == 232)
    }

    @Test func renderBlockAllocatesNothing() throws {
        let rig = try OfflineRig()
        func renderAllocations() -> Int {
            rig.queue.sync {
                let engine = rig.audio.engine
                let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: AudioEngine.ioBufferFrames)!
                return AllocationCounter.count {
                    for _ in 0..<64 {
                        _ = try? engine.renderOffline(AudioEngine.ioBufferFrames, to: buffer)
                    }
                    AllocationCounter.keep(buffer)
                }
            }
        }
        _ = renderAllocations()
        let silent = renderAllocations()
        for column in stride(from: Float(0), to: 1, by: 1 / 12) {
            rig.play(SoundTrigger(category: .space, direction: .down, column: column, row: 4, timing: .immediate))
        }
        let mixing = renderAllocations()
        print("allocations per 64 render cycles (silent, mixing): \(silent), \(mixing)")
        #expect(mixing <= silent)
        #expect(rig.audio.sampler.stats.peakVoices == 12)
    }

    @Test func overlappingStrikesNeverClip() throws {
        let rig = try OfflineRig(pack: "mxblue")
        for _ in 0..<12 {
            rig.play(SoundTrigger(category: .space, direction: .down, column: 0.5, row: 4, timing: .immediate))
        }
        let peak = try rig.renderPeak(frames: 8_192)
        #expect(peak <= Sampler.ceiling + 1e-4)
        #expect(peak > 0.85)
    }

    @Test(arguments: ["holypanda", "mxblue"])
    func fastTypingKeepsItsRhythmWithoutClipping(pack: String) throws {
        let source = try PackLoader.load(directory: Fixtures.bundledPack(pack))
        let report = try OfflineRender(pack: source).render(TypingScript.standard()).report
        #expect(report.sounds == 320)
        #expect(report.clippedSamples == 0)
        #expect(report.peakDecibels <= -0.99)
        #expect(report.cutSounds == 0)
        #expect(report.onsetDelayMaxMs - report.onsetDelayMinMs == 0)
        #expect(report.intervalErrorMaxMs == 0)
        #expect(report.onsetDelayMaxMs < 4)
    }

    @Test func soundsStartAsFarApartAsTheirKeystrokes() throws {
        let source = try PackLoader.load(directory: Fixtures.bundledPack("holypanda"))
        let first = TypedEvent(time: 0.0102, keycode: 0, isDown: true)
        let second = TypedEvent(time: 0.0112, keycode: 1, isDown: true)
        let alone = try OfflineRender(pack: source).render([first]).left
        let both = try OfflineRender(pack: source).render([first, second]).left
        let firstOnset = try #require(alone.firstIndex { $0 != 0 })
        let secondOnset = try #require(both.indices.first { both[$0] != alone[$0] })
        #expect(secondOnset - firstOnset == 48)
    }

    @Test func cutsAVoiceOnlyWhenNoneIsFree() throws {
        let rig = try OfflineRig(voices: 4)
        let space = SoundTrigger(category: .space, direction: .down, column: 0.5, row: 4, timing: .immediate)
        for _ in 0..<4 {
            rig.play(space)
            _ = try rig.renderPeak(frames: 512)
        }
        #expect(rig.audio.stats.stolen == 0)
        #expect(rig.audio.sampler.stats.peakVoices == 4)
        rig.play(space)
        _ = try rig.renderPeak(frames: 512)
        #expect(rig.audio.stats.stolen == 1)
        _ = try rig.renderPeak(frames: 16_384)
        for _ in 0..<4 {
            rig.play(space)
        }
        _ = try rig.renderPeak(frames: 512)
        #expect(rig.audio.stats.stolen == 1)
    }

    private static func push(keystrokes: Int, into ring: EventRing) {
        for i in 0..<keystrokes {
            let keycode = UInt16([0, 1, 2, 49, 36][i % 5])
            ring.push(RawInputEvent(kind: .keyDown, keycode: keycode, timestamp: HostClock.now))
            ring.push(RawInputEvent(kind: .keyUp, keycode: keycode, timestamp: HostClock.now))
        }
    }
}
