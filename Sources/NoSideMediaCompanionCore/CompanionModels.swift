import Foundation
import NoSideMediaManager

public struct CompanionServerInfo: Codable, Sendable, Equatable {
    public let name: String; public let version: String; public let libraryRoot: String; public let requiresAuthentication: Bool
    public init(name: String = "NoSide MMM Companion", version: String, libraryRoot: String, requiresAuthentication: Bool = true) { self.name = name; self.version = version; self.libraryRoot = libraryRoot; self.requiresAuthentication = requiresAuthentication }
}

public enum CompanionJobState: String, Codable, Sendable, Equatable { case ready, applied }

public struct CompanionJob: Codable, Sendable, Equatable, Identifiable {
    public let id: String; public let title: String; public let mediaKind: String; public let provider: String; public let moves: Int; public let generatedFiles: Int; public let unavailableArtwork: Int; public let state: CompanionJobState
    public init(manifest: PortableJobManifest, state: CompanionJobState = .ready) { id = manifest.jobID; title = manifest.seriesTitle; mediaKind = manifest.mediaKind; provider = manifest.metadataProvider; moves = manifest.moves.count; generatedFiles = manifest.generatedFiles.count; unavailableArtwork = manifest.unavailableArtwork.count; self.state = state }
}

public enum CompanionOperation: String, Codable, Sendable { case dryRun = "dry-run", apply, rollback }
public struct CompanionOperationResult: Codable, Sendable, Equatable { public let jobID: String; public let operation: CompanionOperation; public let succeeded: Bool; public let log: String; public init(jobID: String, operation: CompanionOperation, succeeded: Bool, log: String) { self.jobID = jobID; self.operation = operation; self.succeeded = succeeded; self.log = log } }
public struct CompanionMovieAuditSummary: Codable, Sendable, Equatable { public let totalVideos: Int; public let byState: [String: Int]; public let invalidNFOs: Int; public init(report: MovieLibraryHealthReport) { totalVideos = report.items.count; byState = report.summary; invalidNFOs = report.invalidNFOs.count } }
public struct CompanionMovieAuditReport: Codable, Sendable, Equatable { public let items: [MovieAuditItem]; public let totalVideos: Int; public let byState: [String: Int]; public let byFolderState: [String: Int]; public let invalidNFOs: Int; public init(report: MovieLibraryHealthReport) { items = report.items; totalVideos = report.items.count; byState = report.summary; byFolderState = report.folderSummary; invalidNFOs = report.invalidNFOs.count } }
public struct CompanionMoviePackageRequest: Codable, Sendable, Equatable { public let videoPaths: [String]; public init(videoPaths: [String]) { self.videoPaths = videoPaths } }
public struct CompanionTVFolder: Codable, Sendable, Equatable, Identifiable { public let name: String; public var id: String { name }; public init(name: String) { self.name = name } }
public struct CompanionTVAuditReport: Codable, Sendable, Equatable { public let folder: String; public let report: TVLibraryAuditReport; public init(folder: String, report: TVLibraryAuditReport) { self.folder = folder; self.report = report } }

public struct CompanionConfiguration: Sendable {
    public let jobsRoot: URL; public let libraryRoot: URL; public let tvLibraryRoot: URL; public let token: String; public let version: String; public let tvdbCredentials: TVDBClient.Credentials?
    public init(jobsRoot: URL, libraryRoot: URL, tvLibraryRoot: URL? = nil, token: String, version: String, tvdbCredentials: TVDBClient.Credentials? = nil) { self.jobsRoot = jobsRoot.standardizedFileURL; self.libraryRoot = libraryRoot.standardizedFileURL; self.tvLibraryRoot = (tvLibraryRoot ?? libraryRoot).standardizedFileURL; self.token = token; self.version = version; self.tvdbCredentials = tvdbCredentials }
}
