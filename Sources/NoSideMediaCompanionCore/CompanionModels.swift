import Foundation
import NoSideMediaManager

public struct CompanionServerInfo: Codable, Sendable, Equatable {
    public let name: String; public let version: String; public let libraryRoot: String; public let requiresAuthentication: Bool
    public init(name: String = "NoSide MMM Companion", version: String, libraryRoot: String, requiresAuthentication: Bool = true) { self.name = name; self.version = version; self.libraryRoot = libraryRoot; self.requiresAuthentication = requiresAuthentication }
}

public enum CompanionJobState: String, Codable, Sendable, Equatable, Hashable { case ready, applied, rolledBack }

public struct CompanionJob: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String; public let title: String; public let mediaKind: String; public let provider: String; public let moves: Int; public let generatedFiles: Int; public let unavailableArtwork: Int; public let state: CompanionJobState; public let createdAt: Date?
    public init(manifest: PortableJobManifest, state: CompanionJobState = .ready, createdAt: Date? = nil) { id = manifest.jobID; title = manifest.seriesTitle; mediaKind = manifest.mediaKind; provider = manifest.metadataProvider; moves = manifest.moves.count; generatedFiles = manifest.generatedFiles.count; unavailableArtwork = manifest.unavailableArtwork.count; self.state = state; self.createdAt = createdAt }
}

public enum CompanionOperation: String, Codable, Sendable { case dryRun = "dry-run", apply, rollback }
public struct CompanionOperationResult: Codable, Sendable, Equatable { public let jobID: String; public let operation: CompanionOperation; public let succeeded: Bool; public let log: String; public init(jobID: String, operation: CompanionOperation, succeeded: Bool, log: String) { self.jobID = jobID; self.operation = operation; self.succeeded = succeeded; self.log = log } }
public struct CompanionMovieAuditSummary: Codable, Sendable, Equatable { public let totalVideos: Int; public let ignoredVideos: Int; public let byState: [String: Int]; public let invalidNFOs: Int; public init(report: MovieLibraryHealthReport) { totalVideos = report.items.count; ignoredVideos = report.ignoredVideoFiles.count; byState = report.summary; invalidNFOs = report.invalidNFOs.count } }
public struct CompanionMovieAuditReport: Codable, Sendable, Equatable { public let items: [MovieAuditItem]; public let totalVideos: Int; public let ignoredVideos: Int; public let byState: [String: Int]; public let byFolderState: [String: Int]; public let invalidNFOs: Int; public init(report: MovieLibraryHealthReport) { items = report.items; totalVideos = report.items.count; ignoredVideos = report.ignoredVideoFiles.count; byState = report.summary; byFolderState = report.folderSummary; invalidNFOs = report.invalidNFOs.count } }
public enum CompanionMovieAuditPhase: String, Codable, Sendable, Equatable { case idle, running, complete, failed }
/// A shared, retained audit. Starting while another caller is already scanning
/// attaches to that scan rather than inspecting every media container again.
public struct CompanionMovieAuditSnapshot: Codable, Sendable, Equatable {
    public let phase: CompanionMovieAuditPhase; public let completedVideos: Int; public let totalVideos: Int; public let startedAt: Date?; public let completedAt: Date?; public let report: CompanionMovieAuditReport?; public let error: String?
    public init(phase: CompanionMovieAuditPhase = .idle, completedVideos: Int = 0, totalVideos: Int = 0, startedAt: Date? = nil, completedAt: Date? = nil, report: CompanionMovieAuditReport? = nil, error: String? = nil) { self.phase = phase; self.completedVideos = completedVideos; self.totalVideos = totalVideos; self.startedAt = startedAt; self.completedAt = completedAt; self.report = report; self.error = error }
}
public struct CompanionMoviePackageRequest: Codable, Sendable, Equatable { public let videoPaths: [String]; public init(videoPaths: [String]) { self.videoPaths = videoPaths } }
public struct CompanionTMDBMovie: Codable, Sendable, Equatable, Identifiable { public let tmdbID: Int; public let title: String; public let year: String?; public let overview: String?; public var id: Int { tmdbID }; public init(_ result: MovieSearchResult) { tmdbID = result.tmdbID; title = result.title; year = result.year; overview = result.overview } }
public struct CompanionTMDBPackageRequest: Codable, Sendable, Equatable { public let videoPath: String; public let tmdbID: Int; public init(videoPath: String, tmdbID: Int) { self.videoPath = videoPath; self.tmdbID = tmdbID } }
public struct CompanionTVFolder: Codable, Sendable, Equatable, Identifiable { public let name: String; public var id: String { name }; public init(name: String) { self.name = name } }
public struct CompanionTVAuditReport: Codable, Sendable, Equatable { public let folder: String; public let report: TVLibraryAuditReport; public init(folder: String, report: TVLibraryAuditReport) { self.folder = folder; self.report = report } }
public struct CompanionTVEpisodeChoice: Codable, Sendable, Equatable, Identifiable { public let tvdbID: Int; public let season: Int; public let episode: Int; public let title: String; public var id: Int { tvdbID }; public init(_ episode: TVEpisode) { tvdbID = episode.tvdbID; season = episode.season; self.episode = episode.number; title = episode.title } }
public struct CompanionTVMappingReviewItem: Codable, Sendable, Equatable, Identifiable { public let videoPath: String; public let localSeason: Int; public let localEpisode: Int; public let folderSeason: Int?; public let embeddedTitle: String?; public let proposedEpisode: CompanionTVEpisodeChoice?; public var id: String { videoPath }; public init(_ mapping: EpisodeMapping) { videoPath = mapping.local.url.path; localSeason = mapping.local.season; localEpisode = mapping.local.episode; folderSeason = mapping.local.folderSeason; embeddedTitle = mapping.local.metadataTitle; proposedEpisode = mapping.canonical.map(CompanionTVEpisodeChoice.init) } }
public struct CompanionTVMappingReview: Codable, Sendable, Equatable { public let folder: String; public let seriesTVDBID: Int; public let seriesTitle: String; public let mappings: [CompanionTVMappingReviewItem]; public let unmatchedCount: Int; public init(folder: String, series: TVSeries, mappings: [EpisodeMapping]) { self.folder = folder; seriesTVDBID = series.tvdbID; seriesTitle = series.title; self.mappings = mappings.map(CompanionTVMappingReviewItem.init); unmatchedCount = mappings.filter { $0.canonical == nil }.count } }

public struct CompanionConfiguration: Sendable {
    public let jobsRoot: URL; public let libraryRoot: URL; public let tvLibraryRoot: URL; public let token: String; public let version: String; public let tvdbCredentials: TVDBClient.Credentials?; public let tmdbAPIKey: String?
    public init(jobsRoot: URL, libraryRoot: URL, tvLibraryRoot: URL? = nil, token: String, version: String, tvdbCredentials: TVDBClient.Credentials? = nil, tmdbAPIKey: String? = nil) { self.jobsRoot = jobsRoot.standardizedFileURL; self.libraryRoot = libraryRoot.standardizedFileURL; self.tvLibraryRoot = (tvLibraryRoot ?? libraryRoot).standardizedFileURL; self.token = token; self.version = version; self.tvdbCredentials = tvdbCredentials; self.tmdbAPIKey = tmdbAPIKey }
}
