internal import CRing
import AVFoundation
import Darwin

struct Variation {
    var rate: Float
    var attenuation: Float
    var dulling: Float

    static let press = Variation(rate: 0.015, attenuation: 2.5, dulling: 0.3)
    static let release = Variation(rate: 0.025, attenuation: 4, dulling: 0.6)
}

struct VoiceCommand {
    var samples: UnsafePointer<Float>?
    var eventTime: UInt64
    var length: UInt32
    var rate: Float
    var gain: Float
    var pan: Int16
    var dulling: Int16
}

final class Sampler: @unchecked Sendable {
    static let marginSeconds = 0.001
    static let ceiling: Float = 0.891
    static let limiterReleaseSeconds = 0.08
    static let dullingCutoff = 3_000.0

    let node: AVAudioSourceNode
    private let context: RenderContext
    private var state: UnsafeMutablePointer<RenderState> { context.state }
    private var commands: UnsafeMutableRawPointer { context.commands }

    init(voiceCount: Int = 32) {
        precondition(MemoryLayout<VoiceCommand>.size <= Int(THOCK_RING_SLOT_SIZE))
        let context = RenderContext(voiceCount: voiceCount)
        self.context = context
        node = AVAudioSourceNode { isSilence, _, frameCount, output in
            Sampler.render(context.state, context.commands, Int(frameCount), output, isSilence)
        }
    }

    var stats: (cut: UInt64, late: UInt64, peakVoices: Int) {
        (state.pointee.cut, state.pointee.late, state.pointee.peakVoices)
    }

    func reset(sampleRate: Double) {
        var command = VoiceCommand(samples: nil, eventTime: 0, length: 0, rate: 0, gain: 0, pan: 0, dulling: 0)
        while thock_ring_pop(commands, &command, MemoryLayout<VoiceCommand>.size) {}
        let state = state
        for index in 0..<state.pointee.voiceCount {
            state.pointee.voices[index] = Voice()
        }
        state.pointee.sampleRate = sampleRate
        state.pointee.ticksPerFrame = Double(HostClock.ticks(nanoseconds: 1_000_000_000)) / sampleRate
        state.pointee.marginFrames = Int(sampleRate * Self.marginSeconds)
        state.pointee.limiterGain = 1
        state.pointee.limiterRelease = Float(1 - exp(-1 / (Self.limiterReleaseSeconds * sampleRate)))
        state.pointee.dullingCoefficient = Float(1 - exp(-2 * Double.pi * Self.dullingCutoff / sampleRate))
    }

    func setManualCycleHost(_ host: UInt64) {
        state.pointee.manualCycleHost = host
    }

    @discardableResult
    func play(_ command: VoiceCommand) -> Bool {
        withUnsafePointer(to: command) { thock_ring_push(commands, $0, MemoryLayout<VoiceCommand>.size) }
    }

    private static func render(_ state: UnsafeMutablePointer<RenderState>, _ commands: UnsafeMutableRawPointer, _ frames: Int,
                               _ output: UnsafeMutablePointer<AudioBufferList>, _ isSilence: UnsafeMutablePointer<ObjCBool>) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(output)
        guard let left = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
        let right = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) ?? left : left
        left.update(repeating: 0, count: frames)
        if right != left { right.update(repeating: 0, count: frames) }

        let cycleHost = state.pointee.manualCycleHost != 0 ? state.pointee.manualCycleHost : mach_absolute_time()
        var command = VoiceCommand(samples: nil, eventTime: 0, length: 0, rate: 0, gain: 0, pan: 0, dulling: 0)
        while thock_ring_pop(commands, &command, MemoryLayout<VoiceCommand>.size) {
            start(command, state, cycleHost: cycleHost, frames: frames)
        }

        var playing = 0
        let voices = state.pointee.voices
        for index in 0..<state.pointee.voiceCount where voices[index].samples != nil {
            playing += 1
            mix(&voices[index], state, left, right, frames)
        }
        state.pointee.peakVoices = max(state.pointee.peakVoices, playing)

        guard playing > 0 || state.pointee.limiterGain < 1 else {
            isSilence.pointee = true
            return noErr
        }
        limit(state, left, right, frames)
        return noErr
    }

    private static func start(_ command: VoiceCommand, _ state: UnsafeMutablePointer<RenderState>, cycleHost: UInt64, frames: Int) {
        guard let samples = command.samples, command.length > 1 else { return }
        let sinceCycle = Double(Int64(bitPattern: command.eventTime &- cycleHost)) / state.pointee.ticksPerFrame
        var offset = Int(sinceCycle.rounded()) + frames + state.pointee.marginFrames
        if offset < 0 {
            state.pointee.late += 1
            offset = 0
        }

        let voices = state.pointee.voices
        var chosen = -1
        var quietest = Float.infinity
        for index in 0..<state.pointee.voiceCount {
            let voice = voices[index]
            guard voice.samples != nil else {
                chosen = index
                break
            }
            let remaining = voice.delay > 0 ? 1 : Float(1 - voice.position / Double(voice.length))
            let loudness = remaining * max(voice.left, voice.right)
            if loudness < quietest {
                quietest = loudness
                chosen = index
            }
        }
        if voices[chosen].samples != nil { state.pointee.cut += 1 }

        let pan = Float(command.pan) / 32_767
        voices[chosen] = Voice(samples: samples, length: Int(command.length), position: 0, rate: Double(command.rate),
                               left: command.gain * min(1, 1 - pan), right: command.gain * min(1, 1 + pan),
                               dulling: Float(command.dulling) / 32_767, lowpass: 0, delay: offset)
    }

    private static func mix(_ voice: inout Voice, _ state: UnsafeMutablePointer<RenderState>,
                            _ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, _ frames: Int) {
        guard voice.delay < frames, let x = voice.samples else {
            voice.delay -= frames
            return
        }
        let count = voice.length
        let coefficient = state.pointee.dullingCoefficient
        var position = voice.position
        var lowpass = voice.lowpass
        var frame = voice.delay
        voice.delay = 0
        while frame < frames {
            let i = Int(position)
            guard i < count - 1 else {
                voice.samples = nil
                return
            }
            let t = Float(position - Double(i))
            let xm1 = i > 0 ? x[i - 1] : 0
            let x0 = x[i]
            let x1 = x[i + 1]
            let x2 = i + 2 < count ? x[i + 2] : 0
            let c1 = 0.5 * (x1 - xm1)
            let c2 = xm1 - 2.5 * x0 + 2 * x1 - 0.5 * x2
            let c3 = 0.5 * (x2 - xm1) + 1.5 * (x0 - x1)
            var sample = ((c3 * t + c2) * t + c1) * t + x0
            lowpass += coefficient * (sample - lowpass)
            sample += voice.dulling * (lowpass - sample)
            left[frame] += sample * voice.left
            right[frame] += sample * voice.right
            position += voice.rate
            frame += 1
        }
        voice.position = position
        voice.lowpass = lowpass
    }

    private static func limit(_ state: UnsafeMutablePointer<RenderState>, _ left: UnsafeMutablePointer<Float>,
                              _ right: UnsafeMutablePointer<Float>, _ frames: Int) {
        var gain = state.pointee.limiterGain
        let release = state.pointee.limiterRelease
        let stereo = left != right
        for frame in 0..<frames {
            gain += (1 - gain) * release
            let peak = max(abs(left[frame]), abs(right[frame])) * gain
            if peak > ceiling {
                gain *= ceiling / peak
            }
            left[frame] *= gain
            if stereo { right[frame] *= gain }
        }
        state.pointee.limiterGain = gain > 0.999_9 ? 1 : gain
    }
}

private struct Voice {
    var samples: UnsafePointer<Float>?
    var length = 0
    var position = 0.0
    var rate = 1.0
    var left: Float = 0
    var right: Float = 0
    var dulling: Float = 0
    var lowpass: Float = 0
    var delay = 0
}

private struct RenderState {
    let voices: UnsafeMutablePointer<Voice>
    let voiceCount: Int
    var sampleRate = 48_000.0
    var ticksPerFrame = 1.0
    var marginFrames = 48
    var manualCycleHost: UInt64 = 0
    var limiterGain: Float = 1
    var limiterRelease: Float = 0
    var dullingCoefficient: Float = 0
    var cut: UInt64 = 0
    var late: UInt64 = 0
    var peakVoices = 0
}

private final class RenderContext: @unchecked Sendable {
    let state: UnsafeMutablePointer<RenderState>
    let commands: UnsafeMutableRawPointer

    init(voiceCount: Int) {
        let voices = UnsafeMutablePointer<Voice>.allocate(capacity: voiceCount)
        voices.initialize(repeating: Voice(), count: voiceCount)
        state = UnsafeMutablePointer<RenderState>.allocate(capacity: 1)
        state.initialize(to: RenderState(voices: voices, voiceCount: voiceCount))
        commands = thock_ring_create(256)!
    }

    deinit {
        state.pointee.voices.deallocate()
        state.deallocate()
        thock_ring_destroy(commands)
    }
}
