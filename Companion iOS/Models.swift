import Foundation

struct CompanionServerInfo: Codable, Equatable { let name: String; let version: String; let libraryRoot: String; let requiresAuthentication: Bool }
enum CompanionJobState: String, Codable, Equatable, Hashable { case ready, applied, rolledBack }
struct CompanionJob: Codable, Identifiable, Equatable, Hashable { let id: String; let title: String; let mediaKind: String; let provider: String; let moves: Int; let generatedFiles: Int; let unavailableArtwork: Int; let state: CompanionJobState; let createdAt: Date? }
enum CompanionOperation: String, Codable { case dryRun = "dry-run", apply, rollback }
struct CompanionOperationResult: Codable, Equatable { let jobID: String; let operation: CompanionOperation; let succeeded: Bool; let log: String }
struct CompanionMovieAuditItem: Codable, Identifiable, Equatable { let videoPath: String; let nfoTitle: String?; let nfoYear: String?; let nfoIsValid: Bool?; let tmdbID: Int?; let embeddedTitle: String?; let hasEmbeddedArtwork: Bool; let state: String; let folderState: String; var id: String { videoPath }; var isMultiPart: Bool { folderState == "sharedMultiPart" }; var preservationReady: Bool { state == "complete" && folderState == "needsNormalization" && nfoIsValid == true && tmdbID != nil }; var multiPartReady: Bool { state == "complete" && isMultiPart && nfoIsValid == true && tmdbID != nil }; var sidecarReady: Bool { state == "embeddedMetadataNeedsSidecars" && !(embeddedTitle?.isEmpty ?? true) }; var artworkRepairReady: Bool { state == "incompleteSidecars" && nfoIsValid == true && tmdbID != nil && hasEmbeddedArtwork }; var requiresTMDBMatch: Bool { state == "bareNeedsTMDB" }; var cannotExtractTitle: Bool { state == "embeddedMetadataNeedsSidecars" && !sidecarReady } }
struct CompanionTVFolder: Codable, Identifiable, Equatable { let name: String; var id: String { name } }
struct CompanionTVEpisode: Codable, Identifiable, Equatable { let videoPath: String; let season: Int; let episode: Int; let folderSeason: Int?; var id: String { videoPath }; var episodeLabel: String { season > 0 && episode > 0 ? "S\(season)E\(episode)" : "Unnumbered" } }
struct CompanionTVDuplicate: Codable, Identifiable, Equatable { let season: Int; let episode: Int; let videoPaths: [String]; var id: String { "S\(season)E\(episode)" } }
struct CompanionTVAuditInner: Codable, Equatable { let items: [CompanionTVEpisode]; let duplicates: [CompanionTVDuplicate]; let unnumberedCount: Int; let folderSeasonConflicts: Int }
struct CompanionTVAuditReport: Codable, Equatable { let folder: String; let report: CompanionTVAuditInner }
struct CompanionTVEpisodeChoice: Codable, Identifiable, Equatable { let tvdbID: Int; let season: Int; let episode: Int; let title: String; var id: Int { tvdbID } }
struct CompanionTVMappingReviewItem: Codable, Identifiable, Equatable { let videoPath: String; let localSeason: Int; let localEpisode: Int; let folderSeason: Int?; let embeddedTitle: String?; let proposedEpisode: CompanionTVEpisodeChoice?; var id: String { videoPath } }
struct CompanionTVMappingReview: Codable, Equatable { let folder: String; let seriesTVDBID: Int; let seriesTitle: String; let mappings: [CompanionTVMappingReviewItem]; let unmatchedCount: Int }
struct CompanionMovieAuditReport: Codable, Equatable { let items: [CompanionMovieAuditItem]; let totalVideos: Int; let ignoredVideos: Int?; let byState: [String: Int]; let byFolderState: [String: Int]; let invalidNFOs: Int }
struct CompanionMovieAuditSnapshot: Codable, Equatable { let phase: String; let completedVideos: Int; let totalVideos: Int; let startedAt: Date?; let completedAt: Date?; let report: CompanionMovieAuditReport?; let error: String? }
struct CompanionMoviePackageRequest: Codable { let videoPaths: [String] }
struct TVSeriesSearchResult: Codable, Identifiable, Equatable { let tvdbID: Int; let title: String; let overview: String?; let year: String?; var id: Int { tvdbID } }
