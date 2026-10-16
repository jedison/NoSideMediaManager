import Foundation

/// A portable, human-editable regional/streaming mapping preset. Unlike a
/// review plan it deliberately stores paths relative to the selected show
/// root, so it remains usable when that show moves between machines/volumes.
public struct TVMappingPreset: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public var sourceRelativePath: String
        public var canonicalEpisodeID: Int?
        public var destinationRelativePath: String?
        public var downloadArtwork: Bool
        public var excluded: Bool
    }
    public let formatVersion: Int
    public var name: String
    public let seriesTVDBID: Int
    public var entries: [Entry]
    public init(name: String, seriesTVDBID: Int, entries: [Entry]) { formatVersion = 1; self.name = name; self.seriesTVDBID = seriesTVDBID; self.entries = entries }

    public static func from(plan: MappingPlanDocument, named name: String, showRoot: URL) throws -> TVMappingPreset {
        let root = showRoot.standardizedFileURL.path + "/"
        let entries = try plan.entries.map { entry -> Entry in
            guard entry.sourcePath.hasPrefix(root) else { throw MappingPlanError.pathOutsideRoot }
            let source = String(entry.sourcePath.dropFirst(root.count))
            let destination = entry.destinationPath.map { path -> String in path.hasPrefix(root) ? String(path.dropFirst(root.count)) : path }
            return Entry(sourceRelativePath: source, canonicalEpisodeID: entry.canonicalEpisodeID, destinationRelativePath: destination, downloadArtwork: entry.downloadArtwork, excluded: entry.excluded == true)
        }
        return TVMappingPreset(name: name, seriesTVDBID: plan.seriesTVDBID, entries: entries)
    }
    public func plan(at showRoot: URL) -> MappingPlanDocument {
        MappingPlanDocument(seriesTVDBID: seriesTVDBID, libraryPath: showRoot.path, entries: entries.map { entry in
            .init(sourcePath: showRoot.appendingPathComponent(entry.sourceRelativePath).path, canonicalEpisodeID: entry.canonicalEpisodeID, destinationPath: entry.destinationRelativePath.map { showRoot.appendingPathComponent($0).path }, downloadArtwork: entry.downloadArtwork, excluded: entry.excluded)
        })
    }
    public func write(to url: URL) throws { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(self).write(to: url, options: .atomic) }
    public static func read(from url: URL) throws -> TVMappingPreset { try JSONDecoder().decode(TVMappingPreset.self, from: Data(contentsOf: url)) }
}
