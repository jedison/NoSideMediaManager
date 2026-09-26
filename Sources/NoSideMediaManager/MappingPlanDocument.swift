import Foundation

public struct MappingPlanDocument: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public var sourcePath: String
        public var canonicalEpisodeID: Int?
        public var destinationPath: String?
        public var downloadArtwork: Bool
        public init(sourcePath: String, canonicalEpisodeID: Int?, destinationPath: String? = nil, downloadArtwork: Bool = true) { self.sourcePath = sourcePath; self.canonicalEpisodeID = canonicalEpisodeID; self.destinationPath = destinationPath; self.downloadArtwork = downloadArtwork }
    }
    public let formatVersion: Int
    public let seriesTVDBID: Int
    public let libraryPath: String
    public var entries: [Entry]
    public init(seriesTVDBID: Int, libraryPath: String, entries: [Entry]) { self.formatVersion = 1; self.seriesTVDBID = seriesTVDBID; self.libraryPath = libraryPath; self.entries = entries }

    public static func proposed(seriesID: Int, library: URL, mappings: [EpisodeMapping]) -> MappingPlanDocument {
        MappingPlanDocument(seriesTVDBID: seriesID, libraryPath: library.path, entries: mappings.map { Entry(sourcePath: $0.local.url.path, canonicalEpisodeID: $0.canonical?.tvdbID) })
    }
    public func write(to url: URL) throws { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(self).write(to: url, options: .atomic) }
    public static func read(from url: URL) throws -> MappingPlanDocument { try JSONDecoder().decode(MappingPlanDocument.self, from: Data(contentsOf: url)) }
}
