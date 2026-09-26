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

    /// Combines reviewed season plans into one show-root plan without changing
    /// any media files. All source paths must remain below the supplied root.
    public static func combined(showRoot: URL, documents: [MappingPlanDocument]) throws -> MappingPlanDocument {
        guard let first = documents.first else { throw MappingPlanError.emptyDocuments }
        guard documents.allSatisfy({ $0.seriesTVDBID == first.seriesTVDBID }) else { throw MappingPlanError.mixedSeries }
        let root = showRoot.standardizedFileURL.path + "/"
        let entries = documents.flatMap(\.entries)
        guard entries.allSatisfy({ $0.sourcePath.hasPrefix(root) }) else { throw MappingPlanError.pathOutsideRoot }
        guard Set(entries.map(\.sourcePath)).count == entries.count else { throw MappingPlanError.duplicateSource }
        return MappingPlanDocument(seriesTVDBID: first.seriesTVDBID, libraryPath: showRoot.standardizedFileURL.path, entries: entries.sorted { $0.sourcePath < $1.sourcePath })
    }

    /// Prepares a deterministic, Emby-friendly filename normalization while
    /// retaining folders. Different video extensions intentionally keep the
    /// same stem; only an exact destination-path collision is disambiguated.
    public func normalized(series: TVSeries, episodesByID: [Int: TVEpisode]) throws -> MappingPlanDocument {
        guard entries.allSatisfy({ $0.canonicalEpisodeID != nil }) else { throw MappingPlanError.unresolvedEntries }
        var proposed = try entries.map { entry -> Entry in
            guard let id = entry.canonicalEpisodeID, let episode = episodesByID[id] else { throw MappingPlanError.unresolvedEntries }
            let source = URL(fileURLWithPath: entry.sourcePath)
            let stem = "\(safe(series.title)) - S\(String(format: "%02d", episode.season))E\(String(format: "%02d", episode.number)) - \(safe(episode.title))"
            let destination = source.deletingLastPathComponent().appendingPathComponent(stem).appendingPathExtension(source.pathExtension)
            return Entry(sourcePath: entry.sourcePath, canonicalEpisodeID: id, destinationPath: destination.path, downloadArtwork: entry.downloadArtwork)
        }
        let groups = Dictionary(grouping: proposed.indices, by: { proposed[$0].destinationPath! })
        for indexes in groups.values where indexes.count > 1 {
            for (offset, index) in indexes.sorted(by: { proposed[$0].sourcePath < proposed[$1].sourcePath }).enumerated() {
                let destination = URL(fileURLWithPath: proposed[index].destinationPath!)
                let edition = destination.deletingPathExtension().lastPathComponent + " [Edition \(offset + 1)]"
                proposed[index].destinationPath = destination.deletingLastPathComponent().appendingPathComponent(edition).appendingPathExtension(destination.pathExtension).path
            }
        }
        return MappingPlanDocument(seriesTVDBID: seriesTVDBID, libraryPath: libraryPath, entries: proposed)
    }

    /// Reconstructs the essential metadata from an already normalized plan.
    /// This permits a reviewed job to be frozen while TVDB is unavailable; it
    /// intentionally has no fresh overview, air-date, rating, or artwork URL.
    public func offlineMetadata() throws -> (series: TVSeries, episodes: [Int: TVEpisode]) {
        guard entries.allSatisfy({ $0.canonicalEpisodeID != nil && $0.destinationPath != nil }) else { throw MappingPlanError.unresolvedEntries }
        var title: String?
        var episodes = [Int: TVEpisode]()
        for entry in entries {
            guard let id = entry.canonicalEpisodeID, let destination = entry.destinationPath,
                  let parsed = Self.normalizedName(URL(fileURLWithPath: destination).deletingPathExtension().lastPathComponent) else {
                throw MappingPlanError.invalidNormalizedDestination
            }
            if let title, title != parsed.seriesTitle { throw MappingPlanError.mixedSeries }
            title = parsed.seriesTitle
            episodes[id] = TVEpisode(tvdbID: id, seriesTVDBID: seriesTVDBID, season: parsed.season, number: parsed.number, title: parsed.episodeTitle)
        }
        guard let title else { throw MappingPlanError.emptyDocuments }
        return (TVSeries(tvdbID: seriesTVDBID, title: title), episodes)
    }

    private static func normalizedName(_ value: String) -> (seriesTitle: String, season: Int, number: Int, episodeTitle: String)? {
        let pattern = #"^(.+) - S([0-9]+)E([0-9]+) - (.+)$"#
        guard let match = try? NSRegularExpression(pattern: pattern).firstMatch(in: value, range: NSRange(value.startIndex..., in: value)), match.numberOfRanges == 5 else { return nil }
        func capture(_ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: value) else { return nil }
            return String(value[range])
        }
        guard let seriesTitle = capture(1), let seasonText = capture(2), let episodeText = capture(3), let episodeTitle = capture(4), let season = Int(seasonText), let number = Int(episodeText) else { return nil }
        return (seriesTitle, season, number, episodeTitle)
    }
    public func write(to url: URL) throws { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(self).write(to: url, options: .atomic) }
    public static func read(from url: URL) throws -> MappingPlanDocument { try JSONDecoder().decode(MappingPlanDocument.self, from: Data(contentsOf: url)) }
}

public enum MappingPlanError: LocalizedError, Equatable {
    case emptyDocuments, mixedSeries, pathOutsideRoot, duplicateSource, unresolvedEntries, invalidNormalizedDestination
    public var errorDescription: String? {
        switch self {
        case .emptyDocuments: "No plans were supplied."
        case .mixedSeries: "Plans must belong to the same TVDB series."
        case .pathOutsideRoot: "A plan source path is outside the requested show root."
        case .duplicateSource: "More than one plan contains the same source file."
        case .unresolvedEntries: "Every entry must have a valid TVDB episode before normalization."
        case .invalidNormalizedDestination: "An offline package requires canonical SxxEyy destination filenames."
        }
    }
}

private func safe(_ value: String) -> String {
    let invalid = CharacterSet(charactersIn: "/:\\?*\"<>|")
    let replaced = value.components(separatedBy: invalid).joined(separator: " - ")
    return replaced.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
}
