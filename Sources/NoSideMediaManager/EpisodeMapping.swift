import Foundation

public struct LocalEpisodeFile: Sendable, Equatable, Identifiable {
    public let url: URL
    public let season: Int
    public let episode: Int
    public let folderSeason: Int?
    public let metadataTitle: String?
    public var id: URL { url }

    public init(url: URL, season: Int, episode: Int, folderSeason: Int? = nil, metadataTitle: String? = nil) { self.url = url; self.season = season; self.episode = episode; self.folderSeason = folderSeason; self.metadataTitle = metadataTitle }
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

    /// Includes video containers whose filenames lack `SxxEyy`. Embedded M4V
    /// titles such as `Series 3, Episode 1` become reviewed proposals; files
    /// with no episode number remain in the review as episode zero, which can
    /// never auto-match a TVDB episode.
    @MainActor
    public static func scanIncludingEmbeddedMetadata(directory: URL, fileManager: FileManager = .default) async throws -> [LocalEpisodeFile] {
        let direct = try scan(directory: directory, fileManager: fileManager)
        let directPaths = Set(direct.map { $0.url.standardizedFileURL.path })
        var results = direct
        for url in MediaFileInspector.videoFiles(in: directory, fileManager: fileManager) where !directPaths.contains(url.standardizedFileURL.path) {
            let folderSeason = season(in: url.deletingLastPathComponent().lastPathComponent)
            let info = try? await MediaFileInspector.inspect(url)
            if let title = info?.title, let match = embeddedEpisode(in: title) {
                results.append(LocalEpisodeFile(url: url, season: match.season, episode: match.episode, folderSeason: folderSeason, metadataTitle: title))
            } else {
                results.append(LocalEpisodeFile(url: url, season: folderSeason ?? 0, episode: 0, folderSeason: folderSeason, metadataTitle: info?.title))
            }
        }
        return results.sorted { $0.url.path < $1.url.path }
    }

    private static func season(in folderName: String) -> Int? {
        let folderMatch = folderExpression.firstMatch(in: folderName, range: NSRange(folderName.startIndex..., in: folderName))
        return folderMatch.flatMap { match in Range(match.range(at: 1), in: folderName).flatMap { Int(folderName[$0]) } }
    }

    private static func embeddedEpisode(in title: String) -> (season: Int, episode: Int)? {
        let expression = try! NSRegularExpression(pattern: #"(?i)series\s*(\d{1,3})\s*,?\s*episode\s*(\d{1,3})"#)
        guard let match = expression.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let seasonRange = Range(match.range(at: 1), in: title), let episodeRange = Range(match.range(at: 2), in: title),
              let season = Int(title[seasonRange]), let episode = Int(title[episodeRange]) else { return nil }
        return (season, episode)
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
            guard !conflict else { return EpisodeMapping(local: local, canonical: nil) }
            let numbered = local.episode > 0 ? index[key(season: local.season, episode: local.episode)] : nil
            let titleMatched = local.metadataTitle.flatMap { title in
                let matches = canonicalEpisodes.filter { $0.season == local.season && titlesMatch(title, $0.title) }
                return matches.count == 1 ? matches[0] : nil
            }
            return EpisodeMapping(local: local, canonical: numbered ?? titleMatched)
        }
    }

    private static func key(season: Int, episode: Int) -> String { "\(season):\(episode)" }

    private static func titlesMatch(_ local: String, _ canonical: String) -> Bool { normalizedTitle(local) == normalizedTitle(canonical) }

    private static func normalizedTitle(_ value: String) -> String {
        var text = value.lowercased()
        text = text.replacingOccurrences(of: #"series\s*\d+\s*,?\s*"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"semi[-\s]*final\s*[-:]?\s*"#, with: "", options: .regularExpression)
        return text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.map(singular).joined(separator: " ")
    }

    private static func singular(_ word: String) -> String {
        if word.hasSuffix("ies"), word.count > 3 { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("s"), word.count > 3 { return String(word.dropLast()) }
        return word
    }
}
