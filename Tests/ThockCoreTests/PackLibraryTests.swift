import Foundation
import Testing
@testable import ThockCore

private let bundledIDs = ["bluealps", "mxblack", "mxblue", "mxbrown", "holypanda", "boxnavy", "cream", "topre"]

struct PackLibraryTests {
    private let library: PackLibrary

    init() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("thock-library-\(UUID().uuidString)")
        library = PackLibrary(bundledRoot: Fixtures.bundledPack("holypanda").deletingLastPathComponent(),
                              importedRoot: root.appendingPathComponent("Packs"))
    }

    @Test func listsBundledPacksByName() {
        #expect(library.all().map(\.id) == bundledIDs)
        #expect(library.all().allSatisfy { !$0.isImported })
    }

    @Test func importsAWavPackAndListsItAfterTheBundledOnes() throws {
        let source = try Fixtures.temporaryPack(files: ["alpha_down_1.wav": [0.5, 0.25], "alpha_down_r4.wav": [0.4], "space_up_2.wav": [0.3]])
        try Data("notes".utf8).write(to: source.appendingPathComponent("README.txt"))

        let entry = try library.importPack(from: source)

        #expect(entry.id.hasPrefix("import-thock-pack-"))
        #expect(entry.info.name == "Test")
        #expect(library.all().map(\.id) == bundledIDs + [entry.id])
        let copied = try FileManager.default.contentsOfDirectory(atPath: entry.url.path).sorted()
        #expect(copied == ["alpha_down_1.wav", "alpha_down_r4.wav", "pack.json", "space_up_2.wav"])
        #expect(try PackLoader.load(directory: entry.url).id == entry.id)
    }

    @Test func importingTheSameFolderTwiceKeepsBoth() throws {
        let source = try Fixtures.temporaryPack(files: ["alpha_down_1.caf": [0.5]])
        let first = try library.importPack(from: source)
        let second = try library.importPack(from: source)
        #expect(second.id == first.id + "-2")
        #expect(library.all().filter(\.isImported).count == 2)
    }

    @Test func rejectsInvalidPacksAndLeavesNothingBehind() throws {
        let noManifest = try Fixtures.temporaryPack(manifest: false, files: ["alpha_down_1.caf": [0.5]])
        #expect(throws: PackImportError.invalid(.missingManifest)) { try library.importPack(from: noManifest) }

        let noAlpha = try Fixtures.temporaryPack(files: ["space_down_1.caf": [0.5]])
        #expect(throws: PackImportError.invalid(.missingAlphaDown)) { try library.importPack(from: noAlpha) }

        let badManifest = try Fixtures.temporaryPack(files: ["alpha_down_1.caf": [0.5]])
        try Data(#"{"name":"No author"}"#.utf8).write(to: badManifest.appendingPathComponent("pack.json"))
        #expect(throws: PackImportError.invalidManifest) { try library.importPack(from: badManifest) }

        let file = noAlpha.appendingPathComponent("space_down_1.caf")
        #expect(throws: PackImportError.notAFolder) { try library.importPack(from: file) }

        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: library.importedRoot.path)) ?? []
        #expect(leftovers.isEmpty)
    }

    @Test func deletesOnlyImportedPacks() throws {
        let entry = try library.importPack(from: Fixtures.temporaryPack(files: ["alpha_down_1.caf": [0.5]]))
        try library.delete(entry)
        #expect(!FileManager.default.fileExists(atPath: entry.url.path))
        #expect(library.all().count == bundledIDs.count)

        let bundled = try #require(library.all().first)
        try library.delete(bundled)
        #expect(FileManager.default.fileExists(atPath: bundled.url.path))
    }
}

struct MuteRulesTests {
    @Test func eachRuleCanBeTurnedOffButNotTheManualSwitch() {
        var signals = MuteSignals()
        signals.microphoneInUse = true
        signals.excludedAppInFront = true
        signals.systemOutputMuted = true
        #expect(signals.reasons(under: MuteRules()) == [.microphoneInUse, .excludedApp, .systemOutputMuted])

        var rules = MuteRules()
        rules.microphoneInUse = false
        rules.systemOutputMuted = false
        #expect(signals.reasons(under: rules) == [.excludedApp])

        rules.excludedApp = false
        signals.enabled = false
        #expect(signals.reasons(under: rules) == [.manual])
        #expect(MuteSignals().reasons(under: MuteRules()).isEmpty)
    }
}

struct KeyComboTests {
    @Test func defaultIsControlOptionCommandK() {
        #expect(KeyCombo.defaultToggle.displayString == "⌃⌥⌘K")
        #expect(KeyCombo.defaultToggle.keyCode == 40)
    }

    @Test func recordsShortcutsWithCommandOrControlOnly() throws {
        let combo = try KeyCombo.from(keyCode: 49, modifiers: [.command, .shift], characters: " ").get()
        #expect(combo.displayString == "⇧⌘Space")
        #expect(try KeyCombo.from(keyCode: 0, modifiers: [.control], characters: "q").get().displayString == "⌃Q")
        #expect(throws: KeyCombo.Rejection.needsCommandOrControl) { try KeyCombo.from(keyCode: 0, modifiers: [.option, .shift], characters: "a").get() }
        #expect(throws: KeyCombo.Rejection.needsCommandOrControl) { try KeyCombo.from(keyCode: 0, modifiers: [], characters: "a").get() }
    }

    @Test func survivesAPersistenceRoundTrip() throws {
        let data = try JSONEncoder().encode(KeyCombo.defaultToggle)
        #expect(try JSONDecoder().decode(KeyCombo.self, from: data) == .defaultToggle)
    }
}
