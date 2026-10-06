import Foundation
import NoSideMediaManager

public enum CompanionJobServiceError: LocalizedError { case jobNotFound, invalidOperation, alreadyApplied, tvdbNotConfigured, tmdbNotConfigured, invalidSelection, incompleteMultiPartSelection, completedMovieAuditRequired, tvFolderNotFound, incompleteTVDecisions, duplicateTVDecision, unextractableTitles([String]), unextractableArtwork([String]); public var errorDescription: String? { switch self { case .jobNotFound: "The requested MMM job was not found."; case .invalidOperation: "This MMM job cannot perform that operation."; case .alreadyApplied: "This job is already applied. Use rollback only if it is genuinely needed."; case .tvdbNotConfigured: "Enter a TVDB API key in Settings on the Mac first."; case .tmdbNotConfigured: "Enter a TMDB API key in Settings on the Mac first."; case .invalidSelection: "The selected items are no longer eligible for this package. Re-run the audit."; case .incompleteMultiPartSelection: "Select every part of each shared multi-part movie before freezing it."; case .completedMovieAuditRequired: "Complete a Movie audit before freezing a package."; case .tvFolderNotFound: "Choose a TV folder from the configured TV library."; case .incompleteTVDecisions: "Every current local TV video needs an explicit canonical episode or an explicit exclusion before packaging."; case .duplicateTVDecision: "Each duplicate TV episode group needs exactly one included file."; case .unextractableTitles(let names): "MMM could no longer extract a title from these selected video file(s): \(names.joined(separator: ", "))."; case .unextractableArtwork(let names): "MMM could no longer extract poster artwork from: \(names.joined(separator: ", "))." } } }

/// The only component allowed to invoke a frozen job script. It resolves job
/// IDs from manifests under one configured directory, preventing path injection.
public actor CompanionJobService {
    private let configuration: CompanionConfiguration
    private var movieAuditSnapshot = CompanionMovieAuditSnapshot()
    private var movieAuditTask: Task<Void, Never>?
    private var tvAuditSnapshots = [String: CompanionTVAuditSnapshot]()
    private var tvAuditTasks = [String: Task<Void, Never>]()
    public init(configuration: CompanionConfiguration) {
        self.configuration = configuration
        let cache = configuration.jobsRoot.appendingPathComponent(".noside-mmm-last-movie-audit.json")
        if let data = try? Data(contentsOf: cache), let saved = try? JSONDecoder().decode(CompanionMovieAuditSnapshot.self, from: data), saved.phase == .complete {
            movieAuditSnapshot = saved
        }
    }
    public func serverInfo() -> CompanionServerInfo { .init(version: configuration.version, libraryRoot: configuration.libraryRoot.path) }
    public func jobs() -> [CompanionJob] { manifests().map { directory, manifest in CompanionJob(manifest: manifest, state: state(for: directory, manifest: manifest), createdAt: (try? directory.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? nil) }.sorted { ($0.createdAt ?? .distantPast, $0.id) > ($1.createdAt ?? .distantPast, $1.id) } }
    /// Resolves a manifest ID to its inspected, frozen package directory. The
    /// UI may reveal it, but never receives a caller-supplied filesystem path.
    public func packageDirectory(jobID: String) -> URL? {
        manifests().first(where: { $0.1.jobID == jobID })?.0
    }
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
    public func startTVAudit(folder: String) throws -> CompanionTVAuditSnapshot {
        guard let selected = tvFolders().first(where: { $0.name == folder }) else { throw CompanionJobServiceError.tvFolderNotFound }
        loadTVAuditIfNeeded(folder: selected.name)
        if let snapshot = tvAuditSnapshots[selected.name], snapshot.phase == .running { return snapshot }
        let snapshot = CompanionTVAuditSnapshot(folder: selected.name, phase: .running, startedAt: Date())
        tvAuditSnapshots[selected.name] = snapshot
        let directory = configuration.tvLibraryRoot.appendingPathComponent(selected.name, isDirectory: true)
        tvAuditTasks[selected.name] = Task { [weak self, directory, folder = selected.name] in
            do { await self?.completeTVAudit(folder: folder, report: try await TVLibraryAudit.inspect(directory: directory)) }
            catch { await self?.failTVAudit(folder: folder, error: error.localizedDescription) }
        }
        return snapshot
    }
    public func tvAuditStatus(folder: String) throws -> CompanionTVAuditSnapshot {
        guard tvFolders().contains(where: { $0.name == folder }) else { throw CompanionJobServiceError.tvFolderNotFound }
        loadTVAuditIfNeeded(folder: folder)
        return tvAuditSnapshots[folder] ?? CompanionTVAuditSnapshot(folder: folder)
    }
    private func completeTVAudit(folder: String, report: TVLibraryAuditReport) {
        let snapshot = CompanionTVAuditSnapshot(folder: folder, phase: .complete, startedAt: tvAuditSnapshots[folder]?.startedAt, completedAt: Date(), report: .init(folder: folder, report: report))
        tvAuditSnapshots[folder] = snapshot
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: tvAuditCacheURL(folder), options: .atomic) }
        tvAuditTasks[folder] = nil
    }
    private func failTVAudit(folder: String, error: String) { tvAuditSnapshots[folder] = .init(folder: folder, phase: .failed, startedAt: tvAuditSnapshots[folder]?.startedAt, completedAt: Date(), error: error); tvAuditTasks[folder] = nil }
    private func tvAuditCacheURL(_ folder: String) -> URL { configuration.jobsRoot.appendingPathComponent(".noside-mmm-last-tv-audit-" + folder.utf8.map { String(format: "%02x", $0) }.joined() + ".json") }
    private func loadTVAuditIfNeeded(folder: String) {
        guard tvAuditSnapshots[folder] == nil,
              let data = try? Data(contentsOf: tvAuditCacheURL(folder)),
              let saved = try? JSONDecoder().decode(CompanionTVAuditSnapshot.self, from: data),
              saved.phase == .complete else { return }
        tvAuditSnapshots[folder] = saved
    }
    public func reviewTV(seriesID: Int, folder: String) async throws -> CompanionTVMappingReview {
        guard let selected = tvFolders().first(where: { $0.name == folder }) else { throw CompanionJobServiceError.tvFolderNotFound }
        guard let credentials = configuration.tvdbCredentials else { throw CompanionJobServiceError.tvdbNotConfigured }
        let client = TVDBClient(credentials: credentials)
        async let localFiles = EpisodeFolderScanner.scanIncludingEmbeddedMetadata(directory: configuration.tvLibraryRoot.appendingPathComponent(selected.name, isDirectory: true))
        async let series = client.series(id: seriesID)
        async let episodes = client.episodes(forSeriesID: seriesID)
        let canonical = try await episodes
        let mappings = EpisodeMappingPlanner.propose(localFiles: try await localFiles, canonicalEpisodes: canonical)
        return CompanionTVMappingReview(folder: selected.name, series: try await series, mappings: mappings, canonicalEpisodes: canonical)
    }
    public func freezeTVPackage(_ request: CompanionTVPackageRequest) async throws -> CompanionJob {
        guard let selected = tvFolders().first(where: { $0.name == request.folder }) else { throw CompanionJobServiceError.tvFolderNotFound }
        guard let credentials = configuration.tvdbCredentials else { throw CompanionJobServiceError.tvdbNotConfigured }
        let root = configuration.tvLibraryRoot.appendingPathComponent(selected.name, isDirectory: true)
        let localFiles = try await EpisodeFolderScanner.scanIncludingEmbeddedMetadata(directory: root)
        let currentPaths = Set(localFiles.map { $0.url.path })
        let byPath = Dictionary(uniqueKeysWithValues: request.decisions.map { ($0.videoPath, $0) })
        guard byPath.count == request.decisions.count, Set(byPath.keys) == currentPaths else { throw CompanionJobServiceError.incompleteTVDecisions }
        let source = TVDBClient(credentials: credentials)
        async let series = source.series(id: request.seriesTVDBID)
        let episodes = try await source.episodes(forSeriesID: request.seriesTVDBID)
        let episodesByID = Dictionary(uniqueKeysWithValues: episodes.map { ($0.tvdbID, $0) })
        let excluded = Set(request.decisions.filter(\.excluded).map(\.videoPath))
        guard request.decisions.filter({ !$0.excluded }).allSatisfy({ $0.canonicalEpisodeID.flatMap { episodesByID[$0] } != nil }) else { throw CompanionJobServiceError.incompleteTVDecisions }
        let audit = TVLibraryAudit.report(for: localFiles)
        for duplicate in audit.duplicates {
            let included = duplicate.videoPaths.filter { !excluded.contains($0) }
            guard included.count == 1 else { throw CompanionJobServiceError.duplicateTVDecision }
        }
        let mappings = localFiles.compactMap { local -> ApprovedEpisodeMapping? in
            guard let decision = byPath[local.url.path], !decision.excluded, let id = decision.canonicalEpisodeID, let canonical = episodesByID[id] else { return nil }
            return ApprovedEpisodeMapping(local: local, canonical: canonical, downloadArtwork: decision.downloadArtwork)
        }
        guard !mappings.isEmpty else { throw CompanionJobServiceError.invalidSelection }
        let destinations = Dictionary(uniqueKeysWithValues: mappings.map { mapping in
            let requested = byPath[mapping.local.url.path]?.destinationPath
            return (mapping.local.url, URL(fileURLWithPath: requested ?? mapping.local.url.path))
        })
        let output = configuration.jobsRoot.appendingPathComponent("NoSide-MMM-TVDB-\(request.seriesTVDBID)-phone-job", isDirectory: true)
        let manifest = try await PortableJobBundle.create(at: output, showRoot: root, series: try await series, mappings: mappings, destinations: destinations, downloadArtwork: true, notes: ["Every discovered local video was explicitly mapped or excluded in microMM Companion."] + excluded.sorted().map { "Excluded local video after Companion review: \($0)" })
        return CompanionJob(manifest: manifest)
    }
    public func searchTV(query: String) async throws -> [TVSeriesSearchResult] { guard let credentials = configuration.tvdbCredentials else { throw CompanionJobServiceError.tvdbNotConfigured }; return try await TVDBClient(credentials: credentials).searchSeries(named: query) }
    private func tmdb() throws -> TMDBClient { guard let key = configuration.tmdbAPIKey, !key.isEmpty else { throw CompanionJobServiceError.tmdbNotConfigured }; return TMDBClient(apiKey: key) }
    public func searchMovies(query: String) async throws -> [CompanionTMDBMovie] { try await tmdb().searchMovies(named: query).map(CompanionTMDBMovie.init) }
    public func freezeTMDBPackage(videoPath: String, tmdbID: Int) async throws -> CompanionJob { let item = try completedMovieAuditItems().first { $0.videoPath == videoPath }; guard item?.state == .bareNeedsTMDB else { throw CompanionJobServiceError.invalidSelection }; let movie = try await tmdb().movie(id: tmdbID); let source = URL(fileURLWithPath: videoPath); let plan = MoviePlanDocument(libraryPath: configuration.libraryRoot.path, entries: [.init(sourcePath: videoPath, tmdbID: tmdbID)]); let destination = try plan.normalized(movies: [tmdbID: movie], oneFolderPerMovie: true).entries[0].destinationPath.map(URL.init(fileURLWithPath:))!; let bundle = configuration.jobsRoot.appendingPathComponent("NoSide-MMM-TMDB-\(UUID().uuidString.lowercased())-job", isDirectory: true); return CompanionJob(manifest: try await PortableJobBundle.createMovie(at: bundle, libraryRoot: configuration.libraryRoot, movie: movie, source: source, destination: destination, notes: ["TMDB match was selected and frozen from microMM."])) }
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
    public func freezeArtworkRepairPackage(videoPaths: [String]) async throws -> CompanionJob {
        let requested = Set(videoPaths); guard !requested.isEmpty else { throw CompanionJobServiceError.invalidSelection }
        let selected = try completedMovieAuditItems().filter { requested.contains($0.videoPath) }
        guard selected.count == requested.count, selected.allSatisfy(\.isArtworkRepairReady) else { throw CompanionJobServiceError.invalidSelection }
        var repairs = [EmbeddedArtworkRepairItem](); var missingArtwork = [String]()
        for item in selected {
            let source = URL(fileURLWithPath: item.videoPath)
            let metadata = try await MediaFileInspector.extractMovieMetadata(source)
            guard let artwork = metadata.artwork else { missingArtwork.append(source.lastPathComponent); continue }
            repairs.append(.init(source: source, artwork: artwork))
        }
        guard missingArtwork.isEmpty else { throw CompanionJobServiceError.unextractableArtwork(missingArtwork.sorted()) }
        let bundle = configuration.jobsRoot.appendingPathComponent("NoSide-MMM-Artwork-Repair-\(UUID().uuidString.lowercased())-job", isDirectory: true)
        return CompanionJob(manifest: try PortableJobBundle.createEmbeddedArtworkRepairs(at: bundle, libraryRoot: configuration.libraryRoot, items: repairs))
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
        let result = CompanionOperationResult(jobID: manifest.jobID, operation: operation, succeeded: process.terminationStatus == 0, log: text)
        appendHistory(.init(operation: operation, succeeded: result.succeeded, log: text), in: directory)
        return result
    }
    public func history(jobID: String) throws -> [CompanionOperationHistoryEntry] {
        guard let (directory, _) = manifests().first(where: { $0.1.jobID == jobID }) else { throw CompanionJobServiceError.jobNotFound }
        return (try? JSONDecoder().decode([CompanionOperationHistoryEntry].self, from: Data(contentsOf: directory.appendingPathComponent("operation-history.json")))) ?? []
    }
    private func appendHistory(_ entry: CompanionOperationHistoryEntry, in directory: URL) {
        let url = directory.appendingPathComponent("operation-history.json")
        var entries = (try? JSONDecoder().decode([CompanionOperationHistoryEntry].self, from: Data(contentsOf: url))) ?? []
        entries.append(entry)
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: url, options: .atomic) }
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
