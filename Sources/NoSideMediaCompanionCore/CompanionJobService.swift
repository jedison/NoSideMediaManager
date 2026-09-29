import Foundation
import NoSideMediaManager

public enum CompanionJobServiceError: LocalizedError { case jobNotFound, invalidOperation, alreadyApplied, tvdbNotConfigured, invalidSelection, incompleteMultiPartSelection, completedMovieAuditRequired, tvFolderNotFound, unextractableTitles([String]); public var errorDescription: String? { switch self { case .jobNotFound: "The requested MMM job was not found."; case .invalidOperation: "This MMM job cannot perform that operation."; case .alreadyApplied: "This job is already applied. Use rollback only if it is genuinely needed."; case .tvdbNotConfigured: "Enter a TVDB API key in Settings on the Mac first."; case .invalidSelection: "The selected items are no longer eligible for this package. Re-run the audit."; case .incompleteMultiPartSelection: "Select every part of each shared multi-part movie before freezing it."; case .completedMovieAuditRequired: "Complete a Movie audit before freezing a package."; case .tvFolderNotFound: "Choose a TV folder from the configured TV library."; case .unextractableTitles(let names): "MMM could no longer extract a title from these selected video file(s): \(names.joined(separator: ", ")). Re-audit them, or use the TMDB review workflow." } } }

/// The only component allowed to invoke a frozen job script. It resolves job
/// IDs from manifests under one configured directory, preventing path injection.
public actor CompanionJobService {
    private let configuration: CompanionConfiguration
    private var movieAuditSnapshot = CompanionMovieAuditSnapshot()
    private var movieAuditTask: Task<Void, Never>?
    public init(configuration: CompanionConfiguration) {
        self.configuration = configuration
        let cache = configuration.jobsRoot.appendingPathComponent(".noside-mmm-last-movie-audit.json")
        if let data = try? Data(contentsOf: cache), let saved = try? JSONDecoder().decode(CompanionMovieAuditSnapshot.self, from: data), saved.phase == .complete {
            movieAuditSnapshot = saved
        }
    }
    public func serverInfo() -> CompanionServerInfo { .init(version: configuration.version, libraryRoot: configuration.libraryRoot.path) }
    public func jobs() -> [CompanionJob] { manifests().map { directory, manifest in CompanionJob(manifest: manifest, state: state(for: directory, manifest: manifest), createdAt: (try? directory.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? nil) }.sorted { ($0.createdAt ?? .distantPast, $0.id) > ($1.createdAt ?? .distantPast, $1.id) } }
    public func startMovieAudit() -> CompanionMovieAuditSnapshot {
        if movieAuditSnapshot.phase == .running { return movieAuditSnapshot }
        movieAuditSnapshot = .init(phase: .running, startedAt: Date())
        let root = configuration.libraryRoot
        movieAuditTask = Task { [weak self, root] in
            let report = await MovieLibraryAudit.health(directory: root) { completed, total in
                Task { await self?.updateMovieAuditProgress(completed: completed, total: total) }
            }
            await self?.completeMovieAudit(report: report)
        }
        return movieAuditSnapshot
    }
    public func movieAuditStatus() -> CompanionMovieAuditSnapshot { movieAuditSnapshot }
    private func updateMovieAuditProgress(completed: Int, total: Int) {
        guard movieAuditSnapshot.phase == .running else { return }
        movieAuditSnapshot = .init(phase: .running, completedVideos: completed, totalVideos: total, startedAt: movieAuditSnapshot.startedAt)
    }
    private func completeMovieAudit(report: MovieLibraryHealthReport) {
        movieAuditSnapshot = .init(phase: .complete, completedVideos: report.items.count, totalVideos: report.items.count, startedAt: movieAuditSnapshot.startedAt, completedAt: Date(), report: .init(report: report))
        let cache = configuration.jobsRoot.appendingPathComponent(".noside-mmm-last-movie-audit.json")
        if let data = try? JSONEncoder().encode(movieAuditSnapshot) { try? data.write(to: cache, options: .atomic) }
        movieAuditTask = nil
    }
    public func tvFolders() -> [CompanionTVFolder] { ((try? FileManager.default.contentsOfDirectory(at: configuration.tvLibraryRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.map { CompanionTVFolder(name: $0.lastPathComponent) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    public func tvAudit(folder: String) async throws -> CompanionTVAuditReport { guard let selected = tvFolders().first(where: { $0.name == folder }) else { throw CompanionJobServiceError.tvFolderNotFound }; let report = try await TVLibraryAudit.inspect(directory: configuration.tvLibraryRoot.appendingPathComponent(selected.name, isDirectory: true)); return .init(folder: selected.name, report: report) }
    public func reviewTV(seriesID: Int, folder: String) async throws -> CompanionTVMappingReview {
        guard let selected = tvFolders().first(where: { $0.name == folder }) else { throw CompanionJobServiceError.tvFolderNotFound }
        guard let credentials = configuration.tvdbCredentials else { throw CompanionJobServiceError.tvdbNotConfigured }
        let client = TVDBClient(credentials: credentials)
        async let localFiles = EpisodeFolderScanner.scanIncludingEmbeddedMetadata(directory: configuration.tvLibraryRoot.appendingPathComponent(selected.name, isDirectory: true))
        async let series = client.series(id: seriesID)
        async let episodes = client.episodes(forSeriesID: seriesID)
        let mappings = EpisodeMappingPlanner.propose(localFiles: try await localFiles, canonicalEpisodes: try await episodes)
        return CompanionTVMappingReview(folder: selected.name, series: try await series, mappings: mappings)
    }
    public func searchTV(query: String) async throws -> [TVSeriesSearchResult] { guard let credentials = configuration.tvdbCredentials else { throw CompanionJobServiceError.tvdbNotConfigured }; return try await TVDBClient(credentials: credentials).searchSeries(named: query) }
    public func freezePreservationPackage(videoPaths: [String]) async throws -> CompanionJob {
        let requested = Set(videoPaths); guard !requested.isEmpty else { throw CompanionJobServiceError.invalidSelection }
        let selected = try completedMovieAuditItems().filter { requested.contains($0.videoPath) }
        guard selected.count == requested.count, selected.allSatisfy(\.isPreservationReady) else { throw CompanionJobServiceError.invalidSelection }
        let bundle = configuration.jobsRoot.appendingPathComponent("NoSide-MMM-Preservation-\(UUID().uuidString.lowercased())-job", isDirectory: true)
        let manifest = try PortableJobBundle.createExistingMoviePreservation(at: bundle, plan: MoviePlanDocument.preservationProposal(library: configuration.libraryRoot, items: selected))
        return CompanionJob(manifest: manifest)
    }
    public func freezeMultiPartPackage(videoPaths: [String]) throws -> CompanionJob {
        let requested = Set(videoPaths); guard !requested.isEmpty else { throw CompanionJobServiceError.invalidSelection }
        let all = try completedMovieAuditItems()
        let selected = all.filter { requested.contains($0.videoPath) }
        guard selected.count == requested.count, selected.allSatisfy(\.isMultiPartPreservationReady) else { throw CompanionJobServiceError.invalidSelection }
        guard MoviePlanDocument.isCompleteMultiPartSelection(selected, from: all) else { throw CompanionJobServiceError.incompleteMultiPartSelection }
        let bundle = configuration.jobsRoot.appendingPathComponent("NoSide-MMM-Multipart-\(UUID().uuidString.lowercased())-job", isDirectory: true)
        return CompanionJob(manifest: try PortableJobBundle.createExistingMoviePreservation(at: bundle, plan: MoviePlanDocument.preservationProposal(library: configuration.libraryRoot, items: selected)))
    }
    public func freezeSidecarPackage(videoPaths: [String]) async throws -> CompanionJob {
        let requested = Set(videoPaths); guard !requested.isEmpty else { throw CompanionJobServiceError.invalidSelection }
        let selected = try completedMovieAuditItems().filter { requested.contains($0.videoPath) }
        guard selected.count == requested.count, selected.allSatisfy({ $0.state == .embeddedMetadataNeedsSidecars }) else { throw CompanionJobServiceError.invalidSelection }
        var extracted = [EmbeddedMovieBundleItem](); var missingTitles = [String]()
        for item in selected { let source = URL(fileURLWithPath: item.videoPath); let metadata = try await MediaFileInspector.extractMovieMetadata(source); guard let title = metadata.title, !title.isEmpty else { missingTitles.append(source.lastPathComponent); continue }; extracted.append(.init(source: source, title: title, creationDate: metadata.creationDate, artwork: metadata.artwork)) }
        guard missingTitles.isEmpty else { throw CompanionJobServiceError.unextractableTitles(missingTitles.sorted()) }
        let bundle = configuration.jobsRoot.appendingPathComponent("NoSide-MMM-Sidecars-\(UUID().uuidString.lowercased())-job", isDirectory: true)
        return CompanionJob(manifest: try PortableJobBundle.createEmbeddedMovies(at: bundle, libraryRoot: configuration.libraryRoot, items: extracted))
    }
    private func completedMovieAuditItems() throws -> [MovieAuditItem] {
        guard movieAuditSnapshot.phase == .complete, let report = movieAuditSnapshot.report else { throw CompanionJobServiceError.completedMovieAuditRequired }
        return report.items
    }
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
        if FileManager.default.fileExists(atPath: backup.appendingPathComponent("rolled-back").path) { return .rolledBack }
        if FileManager.default.fileExists(atPath: backup.path) {
            // Legacy packages did not leave an explicit marker. If every file
            // recorded as created has gone, their retained backup represents a
            // completed rollback rather than an active apply.
            let created = backup.appendingPathComponent("created-files.txt")
            if let text = try? String(contentsOf: created) {
                let files = text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
                if !files.isEmpty && files.allSatisfy({ !FileManager.default.fileExists(atPath: configuration.libraryRoot.appendingPathComponent($0).path) }) { return .rolledBack }
            }
            return .applied
        }
        for name in ["apply.log", "full-apply.log"] {
            let log = directory.appendingPathComponent(name)
            if let text = try? String(contentsOf: log), text.contains("Applied \(manifest.jobID).") { return .applied }
        }
        return .ready
    }
}
