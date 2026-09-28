import Foundation
import NoSideMediaManager

public enum CompanionJobServiceError: LocalizedError { case jobNotFound, invalidOperation, alreadyApplied; public var errorDescription: String? { switch self { case .jobNotFound: "The requested MMM job was not found."; case .invalidOperation: "This MMM job cannot perform that operation."; case .alreadyApplied: "This job is already applied. Use rollback only if it is genuinely needed." } } }

/// The only component allowed to invoke a frozen job script. It resolves job
/// IDs from manifests under one configured directory, preventing path injection.
public actor CompanionJobService {
    private let configuration: CompanionConfiguration
    public init(configuration: CompanionConfiguration) { self.configuration = configuration }
    public func serverInfo() -> CompanionServerInfo { .init(version: configuration.version, libraryRoot: configuration.libraryRoot.path) }
    public func jobs() -> [CompanionJob] { manifests().map { CompanionJob(manifest: $0.1, state: state(for: $0.0, manifest: $0.1)) }.sorted { $0.id > $1.id } }
    public func run(jobID: String, operation: CompanionOperation) throws -> CompanionOperationResult {
        guard let (directory, manifest) = manifests().first(where: { $0.1.jobID == jobID }) else { throw CompanionJobServiceError.jobNotFound }
        if state(for: directory, manifest: manifest) == .applied && operation != .rollback { throw CompanionJobServiceError.alreadyApplied }
        let scriptName: String; var arguments = [String]()
        switch operation { case .dryRun: scriptName = "apply.sh"; arguments.append("--dry-run"); case .apply: scriptName = "apply.sh"; case .rollback: scriptName = "rollback.sh" }
        let script = directory.appendingPathComponent(scriptName)
        guard FileManager.default.isExecutableFile(atPath: script.path) else { throw CompanionJobServiceError.invalidOperation }
        arguments.append(configuration.libraryRoot.path)
        let process = Process(); let output = Pipe(); process.executableURL = script; process.arguments = arguments; process.standardOutput = output; process.standardError = output
        try process.run(); process.waitUntilExit(); let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return CompanionOperationResult(jobID: manifest.jobID, operation: operation, succeeded: process.terminationStatus == 0, log: text)
    }
    private func manifests() -> [(URL, PortableJobManifest)] {
        guard let children = try? FileManager.default.contentsOfDirectory(at: configuration.jobsRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        return children.compactMap { directory in let url = directory.appendingPathComponent("manifest.json"); guard let data = try? Data(contentsOf: url), let manifest = try? JSONDecoder().decode(PortableJobManifest.self, from: data) else { return nil }; return (directory, manifest) }
    }
    private func state(for directory: URL, manifest: PortableJobManifest) -> CompanionJobState {
        let backup = configuration.libraryRoot.appendingPathComponent(".noside-mmm-backups").appendingPathComponent(manifest.jobID)
        if FileManager.default.fileExists(atPath: backup.path) { return .applied }
        for name in ["apply.log", "full-apply.log"] {
            let log = directory.appendingPathComponent(name)
            if let text = try? String(contentsOf: log), text.contains("Applied \(manifest.jobID).") { return .applied }
        }
        return .ready
    }
}
