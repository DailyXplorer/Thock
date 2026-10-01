import AVFoundation
import Testing
@testable import ThockCore

struct SamplerTests {
    @Test func aLoneVoiceEndingMidBufferIsStillHeard() throws {
        let sampleRate = 48_000.0
        let frames: AVAudioFrameCount = 256
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let engine = AVAudioEngine()
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: frames)
        let sampler = Sampler()
        sampler.reset(sampleRate: sampleRate)
        engine.attach(sampler.node)
        engine.connect(sampler.node, to: engine.mainMixerNode, format: format)
        try engine.start()

        let length = 64
        let samples = UnsafeMutablePointer<Float>.allocate(capacity: length)
        defer { samples.deallocate() }
        samples.initialize(repeating: 0.5, count: length)

        let cycleHost = HostClock.now
        sampler.setManualCycleHost(cycleHost)
        let oneBuffer = HostClock.ticks(nanoseconds: UInt64(Double(frames) / sampleRate * 1_000_000_000))
        #expect(sampler.play(VoiceCommand(samples: samples, eventTime: cycleHost - oneBuffer, length: UInt32(length),
                                          rate: 1, gain: 1, pan: 0, dulling: 0)))

        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        #expect(try engine.renderOffline(frames, to: buffer) == .success)
        let left = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
        let sounding = left.filter { $0 != 0 }.count
        #expect(sounding >= length - 2)
        #expect(left.max() ?? 0 > 0.4)
    }
}
