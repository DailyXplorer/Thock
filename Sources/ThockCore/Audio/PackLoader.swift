import AVFoundation

public enum PackLoaderError: Error, Equatable {
    case missingManifest
    case missingAlphaDown
    case silent
    case unreadable(String)
}

public enum PackLoader {
    public static let defaultOnsetThreshold: Float = -20
    static let tailThreshold: Float = -45
    static let preRollFrames = 48
    static let fadeOutFrames = 240
    public static let targetPeak: Float = -1

    public static func load(directory: URL, onsetThreshold: Float = defaultOnsetThreshold) throws -> PackSource {
        let manifestURL = directory.appendingPathComponent("pack.json")
        guard let manifest = try? Data(contentsOf: manifestURL) else { throw PackLoaderError.missingManifest }
        let info = try JSONDecoder().decode(PackInfo.self, from: manifest)

        typealias Entry = (variant: Int, clip: Int)
        var clips: [[Float]] = []
        var shared = [[Entry]](repeating: [], count: SoundSlot.count)
        var perRow = [[Entry]](repeating: [], count: SoundKey.count)
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() {
            guard let file = PackFileName(name) else { continue }
            let samples = trim(try decodeMono(directory.appendingPathComponent(name)), onsetThreshold: onsetThreshold)
            guard !samples.isEmpty else { continue }
            clips.append(samples)
            let entry = (file.variant, clips.count - 1)
            if let row = file.row {
                perRow[SoundKey(file.slot, row: row).index].append(entry)
            } else {
                shared[file.slot.index].append(entry)
            }
        }

        func ordered(_ entries: [Entry]) -> [Int] {
            entries.sorted { $0.variant < $1.variant }.map(\.clip)
        }
        func recorded(_ slot: SoundSlot, row: Int) -> [Int] {
            let own = ordered(perRow[SoundKey(slot, row: row).index])
            if !own.isEmpty { return own }
            let any = ordered(shared[slot.index])
            if !any.isEmpty { return any }
            for distance in 1..<KeyMap.rowCount {
                for other in [row - distance, row + distance] where (0..<KeyMap.rowCount).contains(other) {
                    let nearest = ordered(perRow[SoundKey(slot, row: other).index])
                    if !nearest.isEmpty { return nearest }
                }
            }
            return []
        }

        var choices = [[Int]](repeating: [], count: SoundKey.count)
        for slot in SoundSlot.all {
            for row in 0..<KeyMap.rowCount {
                let own = recorded(slot, row: row)
                choices[SoundKey(slot, row: row).index] = own.isEmpty ? recorded(SoundSlot(.alpha, slot.direction), row: row) : own
            }
        }
        guard !choices[SoundKey(SoundSlot(.alpha, .down), row: 0).index].isEmpty else { throw PackLoaderError.missingAlphaDown }

        let peak = clips.joined().reduce(Float(0)) { max($0, abs($1)) }
        guard peak > 0 else { throw PackLoaderError.silent }
        let gain = decibelsToAmplitude(targetPeak) / peak
        return PackSource(id: directory.lastPathComponent, info: info, clips: clips.map { $0.map { $0 * gain } }, choices: choices)
    }

    static func monoFormat(sampleRate: Double) -> AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
    }

    public static func render(_ source: PackSource, sampleRate: Double) -> LoadedPack {
        LoadedPack(source: source, clips: source.clips.map { resample($0, from: PackSource.sampleRate, to: sampleRate) },
                   sampleRate: sampleRate)
    }

    static func trim(_ samples: [Float], onsetThreshold: Float) -> [Float] {
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        guard peak > 0,
              let onset = samples.firstIndex(where: { abs($0) >= peak * decibelsToAmplitude(onsetThreshold) }),
              let last = samples.lastIndex(where: { abs($0) >= peak * decibelsToAmplitude(tailThreshold) }) else { return [] }
        let start = max(0, onset - preRollFrames)
        var clip = Array(samples[start...max(last, onset)])
        let fadeIn = onset - start
        for i in 0..<fadeIn {
            clip[i] *= Float(i) / Float(fadeIn)
        }
        let fadeOut = min(fadeOutFrames, clip.count / 4)
        for i in 0..<fadeOut {
            clip[clip.count - fadeOut + i] *= Float(fadeOut - 1 - i) / Float(fadeOut)
        }
        return clip
    }

    static func decibelsToAmplitude(_ decibels: Float) -> Float {
        pow(10, decibels / 20)
    }

    private static func decodeMono(_ url: URL) throws -> [Float] {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw PackLoaderError.unreadable(url.lastPathComponent)
        }
        let format = file.processingFormat
        guard file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else { return [] }
        try file.read(into: buffer)
        let frames = Int(buffer.frameLength)
        let channels = Int(format.channelCount)
        guard let data = buffer.floatChannelData else { throw PackLoaderError.unreadable(url.lastPathComponent) }
        var mono = [Float](repeating: 0, count: frames)
        for channel in 0..<channels {
            for i in 0..<frames {
                mono[i] += data[channel][i] / Float(channels)
            }
        }
        return resample(mono, from: format.sampleRate, to: PackSource.sampleRate)
    }

    static func resample(_ samples: [Float], from inputRate: Double, to outputRate: Double) -> [Float] {
        guard inputRate != outputRate, !samples.isEmpty else { return samples }
        let input = makeBuffer(samples, format: monoFormat(sampleRate: inputRate))
        let outputFormat = monoFormat(sampleRate: outputRate)
        let capacity = AVAudioFrameCount((Double(samples.count) * outputRate / inputRate).rounded(.up)) + 64
        guard let converter = AVAudioConverter(from: input.format, to: outputFormat),
              let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return samples }
        converter.sampleRateConverterQuality = AVAudioQuality.high.rawValue
        nonisolated(unsafe) var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .endOfStream
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, let data = output.floatChannelData else { return samples }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
    }

    private static func makeBuffer(_ samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(samples.count, 1)))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress {
                buffer.floatChannelData![0].update(from: base, count: samples.count)
            }
        }
        return buffer
    }
}
