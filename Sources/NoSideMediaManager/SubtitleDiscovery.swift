import Foundation

public struct SubtitleSearchRequest: Sendable, Equatable { public let episode: TVEpisode; public let releaseHint: String?; public let languages: [String]; public init(episode: TVEpisode, releaseHint: String? = nil, languages: [String] = ["en", "fr"]) { self.episode = episode; self.releaseHint = releaseHint; self.languages = languages } }
public struct SubtitleCandidate: Sendable, Equatable, Identifiable { public let id: String; public let provider: String; public let language: String; public let episodeTitle: String; public let season: Int; public let episode: Int; public let format: String; public let release: String?; public let downloadURL: URL?; public init(id: String, provider: String, language: String, episodeTitle: String, season: Int, episode: Int, format: String, release: String? = nil, downloadURL: URL? = nil) { self.id=id; self.provider=provider; self.language=language; self.episodeTitle=episodeTitle; self.season=season; self.episode=episode; self.format=format; self.release=release; self.downloadURL=downloadURL } }
public protocol SubtitleSearchProvider: Sendable { var providerName: String { get }; func search(_ request: SubtitleSearchRequest) async throws -> [SubtitleCandidate] }
public enum SubtitleDiscovery {
    public static func reviewedCandidates(_ candidates: [SubtitleCandidate], for request: SubtitleSearchRequest) -> [SubtitleCandidate] {
        candidates.filter { request.languages.contains($0.language) && ["srt", "ass", "ssa", "vtt"].contains($0.format.lowercased()) && $0.season == request.episode.season && $0.episode == request.episode.number && normalized($0.episodeTitle) == normalized(request.episode.title) }
    }
    private static func normalized(_ value: String) -> String { value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined() }
}
