import Foundation
import ThockCore

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: ThockRender <pack-folder> <output.wav>\n".utf8))
    exit(2)
}
let source = try PackLoader.load(directory: URL(fileURLWithPath: arguments[1]))
let output = URL(fileURLWithPath: arguments[2])

func describe(_ name: String, _ slot: SoundSlot) {
    let clips = Set((0..<5).flatMap { source.choices[SoundKey(slot, row: $0).index] }).sorted().map { source.clips[$0] }
    guard !clips.isEmpty else { return }
    let peaks = clips.map { 20 * log10($0.reduce(Float(0)) { max($0, abs($1)) }) }
    let energies = clips.map { 10 * log10($0.reduce(Float(0)) { $0 + $1 * $1 }) }
    let lengths = clips.map { Double($0.count) / PackSource.sampleRate * 1_000 }
    print(String(format: "%@: %d clips, peak %.1f to %.1f dBFS, energy %.1f to %.1f dB, %.0f to %.0f ms", name, clips.count,
                 peaks.min()!, peaks.max()!, energies.min()!, energies.max()!, lengths.min()!, lengths.max()!))
}
print("pack \(source.id)")
describe("alpha down", SoundSlot(.alpha, .down))
describe("alpha up  ", SoundSlot(.alpha, .up))
describe("space down", SoundSlot(.space, .down))
describe("space up  ", SoundSlot(.space, .up))

let start = Date()
let events = TypingScript.standard()
let (left, right, report) = try OfflineRender(pack: source).render(events)
try WAVWriter.write(left: left, right: right, sampleRate: 48_000, to: output)
print(report.summary)
print(String(format: "rendered in %.1f s -> %@", Date().timeIntervalSince(start), output.path))
