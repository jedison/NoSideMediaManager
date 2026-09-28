import Foundation

struct CompanionServerInfo: Codable, Equatable { let name: String; let version: String; let libraryRoot: String; let requiresAuthentication: Bool }
struct CompanionJob: Codable, Identifiable, Equatable, Hashable { let id: String; let title: String; let mediaKind: String; let provider: String; let moves: Int; let generatedFiles: Int; let unavailableArtwork: Int }
enum CompanionOperation: String, Codable { case dryRun = "dry-run", apply, rollback }
struct CompanionOperationResult: Codable, Equatable { let jobID: String; let operation: CompanionOperation; let succeeded: Bool; let log: String }
struct CompanionMovieAuditSummary: Codable, Equatable { let totalVideos: Int; let byState: [String: Int]; let invalidNFOs: Int }
struct TVSeriesSearchResult: Codable, Identifiable, Equatable { let tvdbID: Int; let title: String; let overview: String?; let year: String?; var id: Int { tvdbID } }
