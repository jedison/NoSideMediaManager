import Foundation

public struct LocalEpisodeFile: Sendable, Equatable, Identifiable {
    public let url: URL
    public let season: Int
    public let episode: Int
    public let folderSeason: Int?
    public var id: URL { url }

    public init(url: URL, season: Int, episode: Int, folderSeason: Int? = nil) { self.url = url; self.season = season; self.episode = episode; self.folderSeason = folderSeason }
}

public enum EpisodeFolderScanner {
    private static let expression = try! NSRegularExpression(pattern: #"(?i)(?:S)(\d{1,3})(?:E)(\d{1,3})"#)
    private static let folderExpression = try! NSRegularExpression(pattern: #"(?i)season\s*(\d{1,3})"#)
    private static let extensions: Set<String> = ["m4v", "mkv", "mp4", "avi", "mov"]

    public static func scan(directory: URL, fileManager: FileManager = .default) throws -> [LocalEpisodeFile] {
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        return enumerator.compactMap { item in
            guard let url = item as? URL, extensions.contains(url.pathExtension.lowercased()),
                  let match = expression.firstMatch(in: url.lastPathComponent, range: NSRange(url.lastPathComponent.startIndex..., in: url.lastPathComponent)),
                  let seasonRange = Range(match.range(at: 1), in: url.lastPathComponent), let episodeRange = Range(match.range(at: 2), in: url.lastPathComponent),
                  let season = Int(url.lastPathComponent[seasonRange]), let episode = Int(url.lastPathComponent[episodeRange]) else { return nil }
            let folderName = url.deletingLastPathComponent().lastPathComponent
            let folderMatch = folderExpression.firstMatch(in: folderName, range: NSRange(folderName.startIndex..., in: folderName))
            let folderSeason = folderMatch.flatMap { match in Range(match.range(at: 1), in: folderName).flatMap { Int(folderName[$0]) } }
            return LocalEpisodeFile(url: url, season: season, episode: episode, folderSeason: folderSeason)
        }.sorted { $0.url.path < $1.url.path }
    }
}

public struct EpisodeMapping: Sendable, Equatable, Identifiable {
    public let local: LocalEpisodeFile
    public let canonical: TVEpisode?
    public var id: URL { local.url }
}

public enum EpisodeMappingPlanner {
    /// Number-for-number proposal only. Divergent releases (including GBBO)
    /// remain unmatched until the user explicitly chooses a canonical episode.
    public static func propose(localFiles: [LocalEpisodeFile], canonicalEpisodes: [TVEpisode]) -> [EpisodeMapping] {
        let index = Dictionary(uniqueKeysWithValues: canonicalEpisodes.map { (key(season: $0.season, episode: $0.number), $0) })
        return localFiles.map { local in
            // Folder and filename disagreement is a release-order signal, not
            // something safe to auto-resolve (GBBO is the reference case).
            let conflict = local.folderSeason.map { $0 != local.season } ?? false
            return EpisodeMapping(local: local, canonical: conflict ? nil : index[key(season: local.season, episode: local.episode)])
        }
    }

    private static func key(season: Int, episode: Int) -> String { "\(season):\(episode)" }
}
