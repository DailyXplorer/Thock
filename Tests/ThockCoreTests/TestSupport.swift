import AVFoundation
import Foundation
@testable import ThockCore

private final class BundleToken {}

enum Fixtures {
    static func bundledPack(_ id: String) -> URL {
        Bundle(for: BundleToken.self).url(forResource: "Packs", withExtension: nil)!.appendingPathComponent(id)
    }

    static func temporaryPack(manifest: Bool = true, files: [String: [Float]], sampleRate: Double = 48_000, channels: UInt32 = 1) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("thock-pack-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if manifest {
            try Data(#"{"name":"Test","author":"Tests","license":"CC0-1.0"}"#.utf8).write(to: directory.appendingPathComponent("pack.json"))
        }
        for (name, samples) in files {
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
            buffer.frameLength = AVAudioFrameCount(samples.count)
            for channel in 0..<Int(channels) {
                for (i, sample) in samples.enumerated() {
                    buffer.floatChannelData![channel][i] = sample
                }
            }
            let file = try AVAudioFile(forWriting: directory.appendingPathComponent(name), settings: format.settings,
                                       commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buffer)
        }
        return directory
    }
}

extension AVAudioPCMBuffer {
    var samples: [Float] {
        Array(UnsafeBufferPointer(start: floatChannelData![0], count: Int(frameLength)))
    }

    var peak: Float {
        (0..<Int(format.channelCount)).map { channel in
            UnsafeBufferPointer(start: floatChannelData![channel], count: Int(frameLength)).reduce(0) { max($0, abs($1)) }
        }.max() ?? 0
    }
}

enum AllocationCounter {
    private typealias Hook = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void
    private static let allocateFlag: UInt32 = 2

    nonisolated(unsafe) private static let counter: UnsafeMutablePointer<Int> = {
        let pointer = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        pointer.initialize(to: 0)
        return pointer
    }()
    nonisolated(unsafe) private static let target: UnsafeMutablePointer<pthread_t?> = {
        let pointer = UnsafeMutablePointer<pthread_t?>.allocate(capacity: 1)
        pointer.initialize(to: nil)
        return pointer
    }()
    nonisolated(unsafe) private static var kept: AnyObject?

    static func keep(_ object: AnyObject?) {
        kept = object
    }

    static func count(_ body: () -> Void) -> Int {
        let slot = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger")!.assumingMemoryBound(to: Hook?.self)
        counter.pointee = 0
        target.pointee = pthread_self()
        slot.pointee = { type, _, _, _, _, _ in
            if type & AllocationCounter.allocateFlag != 0, let thread = AllocationCounter.target.pointee,
               pthread_equal(pthread_self(), thread) != 0 {
                AllocationCounter.counter.pointee += 1
            }
        }
        body()
        slot.pointee = nil
        target.pointee = nil
        return counter.pointee
    }
}
