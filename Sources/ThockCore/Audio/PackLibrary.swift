import Foundation

public struct PackEntry: Sendable, Hashable, Identifiable {
    public let id: String
    public let info: PackInfo
    public let url: URL
    public let isImported: Bool
}

public enum PackImportError: Error, Equatable, LocalizedError {
    case notAFolder
    case invalidManifest
    case invalid(PackLoaderError)

    public var errorDescription: String? {
        switch self {
        case .notAFolder: "A pack must be a folder."
        case .invalidManifest: "pack.json can't be read: it must contain name, author and license."
        case .invalid(.missingManifest): "The folder has no pack.json."
        case .invalid(.missingAlphaDown): "The pack must contain at least alpha_down_1 (.caf, .wav or .aiff)."
        case .invalid(.silent): "Every sound in the pack is silent."
        case .invalid(.unreadable(let name)): "Unreadable audio file: \(name)."
        }
    }
}

public struct PackLibrary: Sendable {
    public let bundledRoot: URL?
    public let importedRoot: URL

    public init(bundledRoot: URL?, importedRoot: URL) {
        self.bundledRoot = bundledRoot
        self.importedRoot = importedRoot
    }

    public func all() -> [PackEntry] {
        entries(in: bundledRoot, imported: false) + entries(in: importedRoot, imported: true)
    }

    @discardableResult
    public func importPack(from source: URL) throws -> PackEntry {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PackImportError.notAFolder
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: source.path)
        guard files.contains("pack.json") else { throw PackImportError.invalid(.missingManifest) }
        guard let info = Self.info(at: source) else { throw PackImportError.invalidManifest }

        try FileManager.default.createDirectory(at: importedRoot, withIntermediateDirectories: true)
        let staging = importedRoot.appendingPathComponent(".import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            for name in files where name == "pack.json" || PackFileName(name) != nil {
                try FileManager.default.copyItem(at: source.appendingPathComponent(name), to: staging.appendingPathComponent(name))
            }
            do {
                _ = try PackLoader.load(directory: staging)
            } catch let error as PackLoaderError {
                throw PackImportError.invalid(error)
            }
            let id = uniqueID(for: source.lastPathComponent)
            let destination = importedRoot.appendingPathComponent(id)
            try FileManager.default.moveItem(at: staging, to: destination)
            return PackEntry(id: id, info: info, url: destination, isImported: true)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    public func delete(_ entry: PackEntry) throws {
        guard entry.isImported, entry.url.deletingLastPathComponent().standardizedFileURL == importedRoot.standardizedFileURL else { return }
        try FileManager.default.removeItem(at: entry.url)
    }

    func uniqueID(for folderName: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = String(folderName.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        let base = "import-" + (cleaned.isEmpty ? "pack" : cleaned.lowercased())
        let taken = Set(all().map(\.id))
        var id = base
        var suffix = 2
        while taken.contains(id) || FileManager.default.fileExists(atPath: importedRoot.appendingPathComponent(id).path) {
            id = "\(base)-\(suffix)"
            suffix += 1
        }
        return id
    }

    private func entries(in root: URL?, imported: Bool) -> [PackEntry] {
        guard let root, let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                                                    options: .skipsHiddenFiles) else { return [] }
        return folders.compactMap { folder in
            Self.info(at: folder).map { PackEntry(id: folder.lastPathComponent, info: $0, url: folder, isImported: imported) }
        }
        .sorted { $0.info.name.localizedStandardCompare($1.info.name) == .orderedAscending }
    }

    private static func info(at folder: URL) -> PackInfo? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("pack.json")) else { return nil }
        return try? JSONDecoder().decode(PackInfo.self, from: data)
    }
}
