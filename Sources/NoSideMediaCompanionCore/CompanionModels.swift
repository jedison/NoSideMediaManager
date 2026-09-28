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

public struct CompanionConfiguration: Sendable {
    public let jobsRoot: URL; public let libraryRoot: URL; public let token: String; public let version: String
    public init(jobsRoot: URL, libraryRoot: URL, token: String, version: String) { self.jobsRoot = jobsRoot.standardizedFileURL; self.libraryRoot = libraryRoot.standardizedFileURL; self.token = token; self.version = version }
}
