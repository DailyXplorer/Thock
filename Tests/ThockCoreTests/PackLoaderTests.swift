import AVFoundation
import Testing
@testable import ThockCore

private let alphaDown = SoundSlot(.alpha, .down)
private let bundledPacks = ["holypanda", "cream", "mxbrown", "mxblack", "mxblue", "boxnavy", "bluealps", "topre"]

struct PackLoaderTests {
    @Test func parsesVariantAndRowFileNames() {
        #expect(PackFileName("space_up_12.caf") == PackFileName(slot: SoundSlot(.space, .up), row: nil, variant: 12))
        #expect(PackFileName("alpha_down_1.caf") == PackFileName(slot: alphaDown, row: nil, variant: 1))
        #expect(PackFileName("alpha_down_r0.caf") == PackFileName(slot: alphaDown, row: 0, variant: 1))
        #expect(PackFileName("alpha_down_r4_3.wav") == PackFileName(slot: alphaDown, row: 4, variant: 3))
        #expect(PackFileName("enter_up_2.wav")?.slot == SoundSlot(.enter, .up))
        #expect(PackFileName("tab_down_3.AIFF")?.variant == 3)
        for invalid in ["alpha_down.caf", "letters_down_1.caf", "alpha_side_1.caf", "alpha_down_1.mp3", "alpha_down_x.caf",
                        "alpha_down_r5.caf", "alpha_down_r.caf", "alpha_down_rx.caf", "alpha_down_1_2.caf", "alpha_down_r1_x.caf", "pack.json"] {
            #expect(PackFileName(invalid) == nil, "\(invalid)")
        }
    }

    @Test(arguments: bundledPacks)
    func bundledPackIsARowRecordedKbsimPack(id: String) throws {
        let source = try PackLoader.load(directory: Fixtures.bundledPack(id))
        #expect(source.id == id)
        #expect(source.info.author == "Thomas Lai (kbsim)")
        #expect(source.info.license == "MIT")
        #expect(source.info.source?.hasPrefix("https://github.com/tplai/kbsim/") == true)
        let peak = source.clips.joined().reduce(Float(0)) { max($0, abs($1)) }
        #expect(abs(20 * log10(peak) - -1) < 0.01)
        let rows = (0..<KeyMap.rowCount).map { source.clips(for: alphaDown, row: $0) }
        #expect(rows.allSatisfy { $0.count == 1 })
        #expect(Set(rows.map { $0[0] }).count == KeyMap.rowCount)
        #expect(source.clips(for: SoundSlot(.alpha, .up), row: 2).count == 1)
        #expect(source.clips(for: SoundSlot(.tab, .down), row: 2) == rows[2])
        #expect(source.clips(for: SoundSlot(.modifier, .down), row: 4) == rows[4])
    }

    @Test(arguments: bundledPacks)
    func bundledClipsStartOnTheirAttackAndEndSilent(id: String) throws {
        let source = try PackLoader.load(directory: Fixtures.bundledPack(id))
        let pack = PackLoader.render(source, sampleRate: 48_000)
        for (index, clip) in source.clips.enumerated() {
            #expect(clip.count > 480, "\(id) clip \(index) is longer than 10 ms")
            #expect(clip.first == 0 && clip.last == 0, "\(id) clip \(index) fades in and out")
            let samples = Array(UnsafeBufferPointer(start: pack.clips[index].samples, count: pack.clips[index].count))
            let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
            let attack = try #require(samples.firstIndex { abs($0) >= peak * 0.031_6 })
            #expect(attack <= 72, "\(id) clip \(index) starts \(attack) frames late")
        }
    }

    @Test func trimsBeforeTheAttackAndAfterTheTailWithFades() throws {
        let lead = [Float](repeating: 0, count: 1_000) + [Float](repeating: 0.01, count: 200)
        let body = [Float](repeating: 0.5, count: 1_000)
        let tail = [Float](repeating: 0.001, count: 500)
        let directory = try Fixtures.temporaryPack(files: ["alpha_down_1.caf": lead + body + tail])

        let clip = try PackLoader.load(directory: directory).clips[0]
        #expect(clip.count == 48 + 1_000)
        #expect(clip[0] == 0)
        #expect(abs(clip[48] - 0.891_251) < 1e-4)
        #expect(clip.last == 0)

        let gentle = try PackLoader.load(directory: directory, onsetThreshold: -40).clips[0]
        #expect(gentle.count == 48 + 200 + 1_000)
    }

    @Test func normalizesThePackAsAWholeKeepingRelativeLevels() throws {
        let directory = try Fixtures.temporaryPack(files: [
            "alpha_down_1.caf": [0.5, -0.25, 0.1],
            "space_down_1.caf": [0.25, 0.1],
        ])
        let source = try PackLoader.load(directory: directory)
        let target: Float = 0.891_251
        #expect(abs(source.clips(for: alphaDown, row: 0)[0][0] - target) < 1e-4)
        #expect(abs(source.clips(for: SoundSlot(.space, .down), row: 0)[0][0] - target / 2) < 1e-4)
    }

    private func lengths(_ source: PackSource, _ slot: SoundSlot) -> [[Int]] {
        (0..<KeyMap.rowCount).map { source.clips(for: slot, row: $0).map(\.count) }
    }

    @Test func eachRowPlaysItsOwnFileElseTheSharedVariantsElseTheNearestRow() throws {
        let rowsOnly = try PackLoader.load(directory: Fixtures.temporaryPack(files: [
            "alpha_down_r0.caf": [Float](repeating: 0.5, count: 10),
            "alpha_down_r3.caf": [Float](repeating: 0.5, count: 30),
            "alpha_down_r3_2.caf": [Float](repeating: 0.5, count: 31),
        ]))
        #expect(lengths(rowsOnly, alphaDown) == [[10], [10], [30, 31], [30, 31], [30, 31]])
        #expect(lengths(rowsOnly, SoundSlot(.punctuation, .down)) == lengths(rowsOnly, alphaDown))

        let mixed = try PackLoader.load(directory: Fixtures.temporaryPack(files: [
            "alpha_down_r0.caf": [Float](repeating: 0.5, count: 10),
            "alpha_down_1.caf": [Float](repeating: 0.5, count: 50),
            "alpha_down_2.caf": [Float](repeating: 0.5, count: 51),
            "space_down_r4.caf": [Float](repeating: 0.5, count: 70),
        ]))
        #expect(lengths(mixed, alphaDown) == [[10], [50, 51], [50, 51], [50, 51], [50, 51]])
        #expect(lengths(mixed, SoundSlot(.space, .down)) == [[70], [70], [70], [70], [70]])
    }

    @Test func variantPacksWithoutRowsPlayTheSameVariantsOnEveryRow() throws {
        let source = try PackLoader.load(directory: Fixtures.temporaryPack(files: [
            "alpha_down_1.caf": [Float](repeating: 0.5, count: 10),
            "alpha_down_2.caf": [Float](repeating: 0.5, count: 11),
            "alpha_up_1.caf": [Float](repeating: 0.5, count: 20),
            "enter_down_1.caf": [Float](repeating: 0.5, count: 40),
        ]))
        let everyRow = { (lengths: [Int]) in [[Int]](repeating: lengths, count: KeyMap.rowCount) }
        #expect(lengths(source, alphaDown) == everyRow([10, 11]))
        #expect(lengths(source, SoundSlot(.space, .down)) == everyRow([10, 11]))
        #expect(lengths(source, SoundSlot(.mouse, .up)) == everyRow([20]))
        #expect(lengths(source, SoundSlot(.enter, .down)) == everyRow([40]))
        #expect(lengths(source, SoundSlot(.enter, .up)) == everyRow([20]))
        #expect(source.clips.count == 4)
    }

    @Test func rejectsPacksWithoutAlphaDownOrManifest() throws {
        let noAlpha = try Fixtures.temporaryPack(files: ["space_down_1.caf": [0.5]])
        #expect(throws: PackLoaderError.missingAlphaDown) { try PackLoader.load(directory: noAlpha) }
        let noManifest = try Fixtures.temporaryPack(manifest: false, files: ["alpha_down_1.caf": [0.5]])
        #expect(throws: PackLoaderError.missingManifest) { try PackLoader.load(directory: noManifest) }
        let oneRow = try Fixtures.temporaryPack(files: ["alpha_down_r2.caf": [0.5]])
        #expect(try PackLoader.load(directory: oneRow).clips.count == 1)
    }

    @Test func decodesStereo44kFilesToMono48k() throws {
        let tone = (0..<4_410).map { Float(sin(Double($0) * 2 * .pi * 440 / 44_100) * 0.5) }
        let directory = try Fixtures.temporaryPack(files: ["alpha_down_1.caf": tone], sampleRate: 44_100, channels: 2)
        let samples = try PackLoader.load(directory: directory).clips[0]
        #expect(abs(samples.count - 4_800) <= 4)
    }

    @Test func rendersEveryClipAtTheOutputRate() throws {
        let source = try PackLoader.load(directory: Fixtures.bundledPack("holypanda"))
        let alpha = source.clips(for: alphaDown, row: 3)[0]

        let native = PackLoader.render(source, sampleRate: 48_000)
        #expect(native.sampleRate == 48_000)
        #expect(native.clips.count == source.clips.count)
        #expect(native.samples(for: alphaDown, row: 3) == [alpha])

        let resampled = PackLoader.render(source, sampleRate: 44_100).samples(for: alphaDown, row: 3)[0]
        #expect(abs(resampled.count - alpha.count * 441 / 480) <= 2)
        let peak = { (samples: [Float]) in samples.reduce(Float(0)) { max($0, abs($1)) } }
        #expect(abs(peak(resampled) - peak(alpha)) < 0.1)
    }
}

struct KeyRowTests {
    @Test func keysSitOnTheirPhysicalRowAsInKbsim() {
        let rows: [(keycode: UInt16, row: UInt8)] = [
            (53, 0), (122, 0), (111, 0),
            (50, 1), (18, 1), (29, 1), (51, 1),
            (48, 2), (12, 2), (35, 2), (42, 2),
            (57, 3), (0, 3), (41, 3), (36, 3),
            (56, 4), (10, 4), (6, 4), (60, 4),
            (49, 4), (55, 4), (126, 4), (123, 4),
        ]
        for (keycode, row) in rows {
            #expect(KeyMap.entry(for: keycode).row == row, "keycode \(keycode)")
        }
        var machine = KeyStateMachine()
        let triggers = machine.reduce(RawInputEvent(kind: .keyDown, keycode: 12))
        #expect(triggers.first?.row == 2)
    }
}
