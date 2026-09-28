import Foundation

/// A provider-independent local-TV audit. Duplicate candidates are reported
/// from local episode numbers only; they are never silently merged or renamed.
public struct TVEpisodeAuditItem: Codable, Sendable, Equatable, Identifiable {
    public let videoPath: String; public let season: Int; public let episode: Int; public let folderSeason: Int?; public let embeddedTitle: String?
    public var id: String { videoPath }
    public var episodeKey: String? { season > 0 && episode > 0 ? "S\(season)E\(episode)" : nil }
    init(_ local: LocalEpisodeFile) { videoPath = local.url.path; season = local.season; episode = local.episode; folderSeason = local.folderSeason; embeddedTitle = local.metadataTitle }
}

public struct TVEpisodeDuplicate: Codable, Sendable, Equatable, Identifiable {
    public let season: Int; public let episode: Int; public let videoPaths: [String]
    public var id: String { "S\(season)E\(episode)" }
}

public struct TVLibraryAuditReport: Codable, Sendable, Equatable {
    public let items: [TVEpisodeAuditItem]; public let duplicates: [TVEpisodeDuplicate]; public let unnumberedCount: Int; public let folderSeasonConflicts: Int
}

public enum TVLibraryAudit {
    @MainActor public static func inspect(directory: URL) async throws -> TVLibraryAuditReport {
        report(for: try await EpisodeFolderScanner.scanIncludingEmbeddedMetadata(directory: directory))
    }
    public static func report(for localFiles: [LocalEpisodeFile]) -> TVLibraryAuditReport {
        let items = localFiles.map(TVEpisodeAuditItem.init)
        let duplicates = Dictionary(grouping: items.filter { $0.season > 0 && $0.episode > 0 }, by: { "\($0.season):\($0.episode)" })
            .compactMap { _, values -> TVEpisodeDuplicate? in
                guard values.count > 1, let first = values.first else { return nil }
                return TVEpisodeDuplicate(season: first.season, episode: first.episode, videoPaths: values.map(\.videoPath).sorted())
            }
            .sorted { ($0.season, $0.episode) < ($1.season, $1.episode) }
        return TVLibraryAuditReport(items: items, duplicates: duplicates, unnumberedCount: items.filter { $0.episodeKey == nil }.count, folderSeasonConflicts: items.filter { item in item.folderSeason.map { folderSeason in folderSeason != item.season } ?? false }.count)
    }
}
