import Foundation

public enum SourceFingerprintMode: Sendable, Equatable { case metadata, sha256 }

/// A frozen, transferable change set. It contains no absolute media-library
/// paths: `apply.sh` and `rollback.sh` receive the show root at execution time.
public struct PortableJobManifest: Codable, Sendable, Equatable {
    public struct Move: Codable, Sendable, Equatable {
        public let source: String
        public let destination: String
    }

    public let formatVersion: Int
    public let jobID: String
    public let seriesTVDBID: Int
    public let seriesTitle: String
    public let moves: [Move]
    /// Existing shared NFO/artwork moved independently of a video. Used for
    /// Emby stacked movie parts, which share one metadata/artwork set.
    public let sidecarMoves: [Move]
    public let generatedFiles: [String]
    public let unavailableArtwork: [String]
    public let notes: [String]
    public let mediaKind: String
    public let metadataProvider: String
    /// Best-effort source fingerprints. Empty when the analysis Mac could not
    /// read the media file (for example, a remote-path-only reviewed plan).
    public let sourceFingerprints: [String: String]

    private enum CodingKeys: String, CodingKey { case formatVersion, jobID, seriesTVDBID, seriesTitle, moves, sidecarMoves, generatedFiles, unavailableArtwork, notes, mediaKind, metadataProvider, sourceFingerprints }

    public init(jobID: String, series: TVSeries, moves: [Move], sidecarMoves: [Move] = [], generatedFiles: [String], unavailableArtwork: [String] = [], notes: [String] = [], mediaKind: String = "tv", metadataProvider: String = "tvdb", sourceFingerprints: [String: String] = [:]) {
        self.formatVersion = 1
        self.jobID = jobID
        self.seriesTVDBID = series.tvdbID
        self.seriesTitle = series.title
        self.moves = moves
        self.sidecarMoves = sidecarMoves
        self.generatedFiles = generatedFiles
        self.unavailableArtwork = unavailableArtwork
        self.notes = notes
        self.mediaKind = mediaKind
        self.metadataProvider = metadataProvider
        self.sourceFingerprints = sourceFingerprints
    }

    /// Version-one job packages omitted fields added later for movies and
    /// fingerprints. They remain readable history instead of disappearing.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try values.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        jobID = try values.decode(String.self, forKey: .jobID)
        seriesTVDBID = try values.decodeIfPresent(Int.self, forKey: .seriesTVDBID) ?? 0
        seriesTitle = try values.decodeIfPresent(String.self, forKey: .seriesTitle) ?? "Legacy MMM job"
        moves = try values.decodeIfPresent([Move].self, forKey: .moves) ?? []
        sidecarMoves = try values.decodeIfPresent([Move].self, forKey: .sidecarMoves) ?? []
        generatedFiles = try values.decodeIfPresent([String].self, forKey: .generatedFiles) ?? []
        unavailableArtwork = try values.decodeIfPresent([String].self, forKey: .unavailableArtwork) ?? []
        notes = try values.decodeIfPresent([String].self, forKey: .notes) ?? []
        mediaKind = try values.decodeIfPresent(String.self, forKey: .mediaKind) ?? "tv"
        metadataProvider = try values.decodeIfPresent(String.self, forKey: .metadataProvider) ?? "tvdb"
        sourceFingerprints = try values.decodeIfPresent([String: String].self, forKey: .sourceFingerprints) ?? [:]
    }
}

public enum PortableJobBundleError: LocalizedError, Equatable {
    case unresolvedMapping
    case outputAlreadyExists(URL)
    case pathOutsideShowRoot(URL)
    case integrityManifestFailed

    public var errorDescription: String? {
        switch self {
        case .unresolvedMapping: "Every selected video needs a canonical TVDB episode before a job can be frozen."
        case .outputAlreadyExists(let url): "The job bundle output already exists: \(url.path)"
        case .pathOutsideShowRoot(let url): "A planned path is outside the selected show root: \(url.path)"
        case .integrityManifestFailed: "MMM could not calculate the frozen package integrity manifest."
        }
    }
}

/// Validation failures for a move-only movie preservation plan. These are
/// intentionally distinct from `PortableJobBundleError.unresolvedMapping`,
/// which belongs solely to TVDB episode mapping.
public enum MoviePreservationBundleError: LocalizedError, Equatable {
    case emptyPlan
    case missingTMDBID(sourcePath: String)
    case missingDestinationPath(sourcePath: String)
    case noMoves
    case destinationCollisions([String])

    public var errorDescription: String? {
        switch self {
        case .emptyPlan:
            return "Movie preservation plan has no selected movies."
        case .missingTMDBID(let sourcePath):
            return "Movie preservation entry is missing its reviewed TMDB ID: \(sourcePath)"
        case .missingDestinationPath(let sourcePath):
            return "Movie preservation entry is missing destinationPath: \(sourcePath)"
        case .noMoves:
            return "Movie preservation plan has no moves after review."
        case .destinationCollisions(let destinations):
            let displayed = destinations.prefix(10).joined(separator: ", ")
            let remaining = destinations.count > 10 ? " (and \(destinations.count - 10) more)" : ""
            return "Movie preservation plan has duplicate destinationPath values. Edit the plan so each movie/edition has a distinct destination: \(displayed)\(remaining)"
        }
    }
}

/// Builds a directory which can be copied or zipped without bringing along the
/// media files. The builder only writes inside `bundle`; it never changes
/// `showRoot`.
public enum PortableJobBundle {
    /// Returns the requested job folder unless it is already occupied.  A
    /// reviewed package is evidence and must never be overwritten, so later
    /// attempts become `-v2`, `-v3`, and so on.
    public static func availableOutputURL(for requested: URL, fileManager: FileManager = .default) -> URL {
        guard fileManager.fileExists(atPath: requested.path) else { return requested }
        let parent = requested.deletingLastPathComponent()
        let stem = requested.lastPathComponent
        var revision = 2
        while true {
            let candidate = parent.appendingPathComponent("\(stem)-v\(revision)", isDirectory: true)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            revision += 1
        }
    }

    /// Freezes many independently reviewed movies in one all-or-nothing target
    /// transaction. Each item retains its own movie NFO/poster and TMDB ID.
    @discardableResult
    public static func createMovies(at requestedBundle: URL, libraryRoot: URL, items: [MovieBundleItem], downloadArtwork: Bool = true, fingerprintMode: SourceFingerprintMode = .metadata, notes: [String] = [], fileManager: FileManager = .default) async throws -> PortableJobManifest {
        guard !items.isEmpty else { throw MoviePreservationBundleError.emptyPlan }
        let bundle = availableOutputURL(for: requestedBundle, fileManager: fileManager)
        let root = libraryRoot.standardizedFileURL; let jobID = "mmm-\(UUID().uuidString.lowercased())"; try fileManager.createDirectory(at: bundle.appendingPathComponent("generated"), withIntermediateDirectories: true)
        var moves = [PortableJobManifest.Move](); var generated = [String](); var unavailable = [String](); var locations = [String: URL]()
        for item in items {
            let source = try relative(item.source, to: root); let destination = try relative(item.destination, to: root); locations[source] = item.source
            if source != destination { moves.append(.init(source: source, destination: destination)) }
            let nfo = replacingExtension(destination, with: "nfo"); try write(NFOWriter.movieData(item.movie), relativePath: nfo, in: bundle); generated.append(nfo)
            if downloadArtwork, item.downloadArtwork, let url = item.movie.posterURL {
                let poster = replacingExtension(destination, with: "jpg")
                do { let target = generatedURL(for: poster, in: bundle); try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true); _ = try await ArtworkDownloader.download(url, to: target); generated.append(poster) }
                catch { unavailable.append("\(poster): \(error.localizedDescription)") }
            }
        }
        let facade = TVSeries(tvdbID: 0, title: "Movie library")
        let manifest = PortableJobManifest(jobID: jobID, series: facade, moves: moves, generatedFiles: Array(Set(generated)).sorted(), unavailableArtwork: unavailable.sorted(), notes: notes + ["Every movie has a reviewed TMDB ID in the frozen NFO."], mediaKind: "movie", metadataProvider: "tmdb", sourceFingerprints: fingerprints(for: locations, mode: fingerprintMode))
        try finalize(manifest, in: bundle); return manifest
    }
    @discardableResult
    public static func createEmbeddedMovie(at requestedBundle: URL, libraryRoot: URL, source: URL, title: String, creationDate: String?, artwork: Data?, fileManager: FileManager = .default) throws -> PortableJobManifest {
        let bundle = availableOutputURL(for: requestedBundle, fileManager: fileManager)
        let root = libraryRoot.standardizedFileURL; let jobID = "mmm-\(UUID().uuidString.lowercased())"; let sourceRelative = try relative(source, to: root)
        try fileManager.createDirectory(at: bundle.appendingPathComponent("generated"), withIntermediateDirectories: true)
        let nfoPath = replacingExtension(sourceRelative, with: "nfo"); try write(NFOWriter.embeddedMovieData(title: title, creationDate: creationDate), relativePath: nfoPath, in: bundle)
        var generated = [nfoPath]
        if let artwork { let imagePath = replacingExtension(sourceRelative, with: "jpg"); let target = generatedURL(for: imagePath, in: bundle); try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true); try artwork.write(to: target, options: .atomic); generated.append(imagePath) }
        let facade = TVSeries(tvdbID: 0, title: title)
        let manifest = PortableJobManifest(jobID: jobID, series: facade, moves: [], generatedFiles: generated.sorted(), notes: ["NFO and artwork were extracted from the video container; no TMDB lookup was used."], mediaKind: "movie", metadataProvider: "embedded", sourceFingerprints: fingerprints(for: [sourceRelative: source]))
        try finalize(manifest, in: bundle); return manifest
    }
    /// Freezes sidecars extracted from multiple selected containers as one
    /// package. It only writes NFO/JPG outputs inside the package.
    @discardableResult
    public static func createEmbeddedMovies(at requestedBundle: URL, libraryRoot: URL, items: [EmbeddedMovieBundleItem], fileManager: FileManager = .default) throws -> PortableJobManifest {
        guard !items.isEmpty else { throw MoviePreservationBundleError.emptyPlan }
        let bundle = availableOutputURL(for: requestedBundle, fileManager: fileManager)
        let root = libraryRoot.standardizedFileURL; let jobID = "mmm-\(UUID().uuidString.lowercased())"
        try fileManager.createDirectory(at: bundle.appendingPathComponent("generated"), withIntermediateDirectories: true)
        var generated = [String](); var sources = [String: URL]()
        for item in items {
            let sourceRelative = try relative(item.source, to: root); sources[sourceRelative] = item.source
            let nfoPath = replacingExtension(sourceRelative, with: "nfo")
            try write(NFOWriter.embeddedMovieData(title: item.title, creationDate: item.creationDate, overview: item.overview, genres: item.genres, studio: item.studio, artist: item.artist), relativePath: nfoPath, in: bundle)
            generated.append(nfoPath)
            if let artwork = item.artwork {
                let imagePath = replacingExtension(sourceRelative, with: "jpg")
                let target = generatedURL(for: imagePath, in: bundle)
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try artwork.write(to: target, options: .atomic)
                generated.append(imagePath)
            }
        }
        let facade = TVSeries(tvdbID: 0, title: "Embedded movie metadata")
        let manifest = PortableJobManifest(jobID: jobID, series: facade, moves: [], generatedFiles: Array(Set(generated)).sorted(), notes: ["NFO and artwork were extracted from selected video containers; no TMDB lookup was used."], mediaKind: "movie", metadataProvider: "embedded", sourceFingerprints: fingerprints(for: sources))
        try finalize(manifest, in: bundle)
        return manifest
    }
    /// Freezes extracted poster artwork only. This is for a valid existing NFO
    /// which must be preserved rather than regenerated from the container.
    @discardableResult
    public static func createEmbeddedArtworkRepairs(at requestedBundle: URL, libraryRoot: URL, items: [EmbeddedArtworkRepairItem], fileManager: FileManager = .default) throws -> PortableJobManifest {
        guard !items.isEmpty else { throw MoviePreservationBundleError.emptyPlan }
        let bundle = availableOutputURL(for: requestedBundle, fileManager: fileManager)
        let root = libraryRoot.standardizedFileURL; let jobID = "mmm-\(UUID().uuidString.lowercased())"
        try fileManager.createDirectory(at: bundle.appendingPathComponent("generated"), withIntermediateDirectories: true)
        var generated = [String](); var sources = [String: URL]()
        for item in items {
            let sourceRelative = try relative(item.source, to: root); sources[sourceRelative] = item.source
            let imagePath = replacingExtension(sourceRelative, with: "jpg")
            let target = generatedURL(for: imagePath, in: bundle)
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try item.artwork.write(to: target, options: .atomic)
            generated.append(imagePath)
        }
        let facade = TVSeries(tvdbID: 0, title: "Embedded artwork repair")
        let manifest = PortableJobManifest(jobID: jobID, series: facade, moves: [], generatedFiles: generated.sorted(), notes: ["Poster artwork was extracted from the selected video containers. Existing valid NFO files are preserved unchanged."], mediaKind: "movie", metadataProvider: "embedded", sourceFingerprints: fingerprints(for: sources))
        try finalize(manifest, in: bundle)
        return manifest
    }
    /// Creates a portable single-movie transaction. It writes only `bundle`,
    /// never the reviewed movie folder.
    @discardableResult
    public static func createMovie(at requestedBundle: URL, libraryRoot: URL, movie: Movie, source: URL, destination: URL, downloadArtwork: Bool = true, notes: [String] = [], fileManager: FileManager = .default) async throws -> PortableJobManifest {
        let bundle = availableOutputURL(for: requestedBundle, fileManager: fileManager)
        let root = libraryRoot.standardizedFileURL; let jobID = "mmm-\(UUID().uuidString.lowercased())"
        let sourceRelative = try relative(source, to: root); let destinationRelative = try relative(destination, to: root)
        try fileManager.createDirectory(at: bundle.appendingPathComponent("generated"), withIntermediateDirectories: true)
        let nfoPath = replacingExtension(destinationRelative, with: "nfo")
        try write(NFOWriter.movieData(movie), relativePath: nfoPath, in: bundle)
        var generated = [nfoPath]; var unavailable = [String]()
        if downloadArtwork, let url = movie.posterURL {
            let posterPath = replacingExtension(destinationRelative, with: "jpg")
            do { _ = try await ArtworkDownloader.download(url, to: generatedURL(for: posterPath, in: bundle)); generated.append(posterPath) }
            catch { unavailable.append("\(posterPath): \(error.localizedDescription)") }
        }
        generated.sort()
        let facade = TVSeries(tvdbID: movie.tmdbID, title: movie.title)
        let moves = sourceRelative == destinationRelative ? [] : [PortableJobManifest.Move(source: sourceRelative, destination: destinationRelative)]
        let manifest = PortableJobManifest(jobID: jobID, series: facade, moves: moves, generatedFiles: generated, unavailableArtwork: unavailable, notes: notes, mediaKind: "movie", metadataProvider: "tmdb", sourceFingerprints: fingerprints(for: [sourceRelative: source]))
        try finalize(manifest, in: bundle)
        return manifest
    }
    /// Freezes a move-only, one-folder-per-movie transaction for films which
    /// already have valid local NFO metadata.  Unlike the TMDB authoring flow,
    /// this deliberately does not rewrite NFO XML or replace artwork: the
    /// reviewed sidecars are moved byte-for-byte with their video.
    @discardableResult
    public static func createExistingMoviePreservation(at requestedBundle: URL, plan: MoviePlanDocument, fingerprintMode: SourceFingerprintMode = .metadata, fileManager: FileManager = .default) throws -> PortableJobManifest {
        guard !plan.entries.isEmpty else { throw MoviePreservationBundleError.emptyPlan }
        let bundle = availableOutputURL(for: requestedBundle, fileManager: fileManager)
        let root = URL(fileURLWithPath: plan.libraryPath).standardizedFileURL
        var sources = [String: URL](); var moves = [PortableJobManifest.Move]()
        for entry in plan.entries {
            guard entry.tmdbID != nil else { throw MoviePreservationBundleError.missingTMDBID(sourcePath: entry.sourcePath) }
            guard let destinationPath = entry.destinationPath, !destinationPath.isEmpty else { throw MoviePreservationBundleError.missingDestinationPath(sourcePath: entry.sourcePath) }
            let source = URL(fileURLWithPath: entry.sourcePath)
            let destination = URL(fileURLWithPath: destinationPath)
            let sourceRelative = try relative(source, to: root)
            let destinationRelative = try relative(destination, to: root)
            guard sourceRelative != destinationRelative else { continue }
            sources[sourceRelative] = source
            moves.append(.init(source: sourceRelative, destination: destinationRelative))
        }
        guard !moves.isEmpty else { throw MoviePreservationBundleError.noMoves }
        let sidecarMoves = sharedMultiPartSidecarMoves(plan: plan, root: root, fileManager: fileManager)
        let destinations = Dictionary(grouping: (moves + sidecarMoves).map(\.destination), by: { $0 })
            .compactMap { destination, occurrences in occurrences.count > 1 ? destination : nil }
            .sorted()
        guard destinations.isEmpty else { throw MoviePreservationBundleError.destinationCollisions(destinations) }
        let jobID = "mmm-\(UUID().uuidString.lowercased())"
        try fileManager.createDirectory(at: bundle.appendingPathComponent("generated"), withIntermediateDirectories: true)
        let facade = TVSeries(tvdbID: 0, title: "Existing movie library")
        let multipartNote = sidecarMoves.isEmpty ? [] : ["Emby stacked movie parts use -part1, -part2, etc.; shared NFO/artwork moves once into the movie folder."]
        let manifest = PortableJobManifest(jobID: jobID, series: facade, moves: moves, sidecarMoves: sidecarMoves, generatedFiles: [], notes: ["Existing valid NFO XML and recognised sidecars are preserved exactly; this package only reorganises them."] + multipartNote, mediaKind: "movie", metadataProvider: "existing-nfo", sourceFingerprints: fingerprints(for: sources, mode: fingerprintMode))
        try finalize(manifest, in: bundle, preservation: true)
        return manifest
    }

    /// Plans shared sidecars for Emby file-stacked movies. Each group has one
    /// original sidecar stem (e.g. `Film.nfo`) and several video part entries.
    /// The NFO keeps the canonical folder stem; artwork becomes Emby's standard
    /// folder artwork names, avoiding a misleading attachment to Part 1.
    private static func sharedMultiPartSidecarMoves(plan: MoviePlanDocument, root: URL, fileManager: FileManager) -> [PortableJobManifest.Move] {
        let grouped = Dictionary(grouping: plan.entries.compactMap { entry -> (MoviePlanDocument.Entry, URL, URL)? in
            guard let shared = entry.sharedSidecarBasePath,
                  let destination = entry.destinationPath else { return nil }
            return (entry, URL(fileURLWithPath: shared), URL(fileURLWithPath: destination))
        }, by: { $0.1.standardizedFileURL.path })
        var result = [PortableJobManifest.Move]()
        let extensions = ["jpg", "jpeg", "png", "gif", "tbn"]
        for (_, entries) in grouped {
            guard let first = entries.first else { continue }
            let sourceBase = first.1
            let destinationFolder = first.2.deletingLastPathComponent()
            let destinationStem = destinationFolder.lastPathComponent
            let candidates: [(String, String)] = [(".nfo", "\(destinationStem).nfo")] + extensions.flatMap { ext in
                [("-poster.\(ext)", "poster.\(ext)"), (".\(ext)", "poster.\(ext)"), ("-fanart.\(ext)", "fanart.\(ext)"), ("-clearlogo.\(ext)", "clearlogo.\(ext)"), ("-clearart.\(ext)", "clearart.\(ext)"), ("-banner.\(ext)", "banner.\(ext)"), ("-landscape.\(ext)", "landscape.\(ext)"), ("-thumb.\(ext)", "thumb.\(ext)")]
            }
            for (suffix, name) in candidates {
                let source = URL(fileURLWithPath: sourceBase.path + suffix)
                guard fileManager.fileExists(atPath: source.path),
                      let sourceRelative = try? relative(source, to: root),
                      let destinationRelative = try? relative(destinationFolder.appendingPathComponent(name), to: root) else { continue }
                result.append(.init(source: sourceRelative, destination: destinationRelative))
            }
        }
        return Array(Dictionary(grouping: result, by: { $0.source }).compactMap { _, values in values.first }).sorted { $0.source < $1.source }
    }
    @discardableResult
    public static func create(
        at requestedBundle: URL,
        showRoot: URL,
        series: TVSeries,
        mappings: [ApprovedEpisodeMapping],
        destinations: [URL: URL] = [:],
        downloadArtwork: Bool = true,
        fingerprintMode: SourceFingerprintMode = .metadata,
        notes: [String] = [],
        fileManager: FileManager = .default
    ) async throws -> PortableJobManifest {
        let bundle = availableOutputURL(for: requestedBundle, fileManager: fileManager)
        let root = showRoot.standardizedFileURL
        let jobID = "mmm-\(UUID().uuidString.lowercased())"
        let moves = try mappings.compactMap { mapping -> PortableJobManifest.Move? in
            let source = try relative(mapping.local.url, to: root)
            let destinationURL = destinations[mapping.local.url] ?? mapping.local.url
            let destination = try relative(destinationURL, to: root)
            return source == destination ? nil : .init(source: source, destination: destination)
        }

        try fileManager.createDirectory(at: bundle.appendingPathComponent("generated"), withIntermediateDirectories: true)
        var generated = ["tvshow.nfo"]
        var unavailableArtwork = [String]()
        var artworkJobs = [ArtworkJob]()
        try write(NFOWriter.seriesData(series), relativePath: "tvshow.nfo", in: bundle)

        let outputLocations = try mappings.map { mapping -> (ApprovedEpisodeMapping, String) in
            let destination = destinations[mapping.local.url] ?? mapping.local.url
            return (mapping, try relative(destination, to: root))
        }
        for (mapping, videoPath) in outputLocations {
            let nfoPath = replacingExtension(videoPath, with: "nfo")
            if !generated.contains(nfoPath) {
                let existing = mapping.local.url.deletingPathExtension().appendingPathExtension("nfo")
                try write(NFORepairInspector.mergedEpisodeData(existingNFO: existing, canonical: mapping.canonical, replacing: mapping.nfoFieldsToReplace), relativePath: nfoPath, in: bundle)
                generated.append(nfoPath)
            }
            if downloadArtwork, mapping.downloadArtwork, let artwork = mapping.canonical.artworkURL {
                let jpgPath = replacingExtension(videoPath, with: "jpg")
                let target = generatedURL(for: jpgPath, in: bundle)
                if !generated.contains(jpgPath) && !artworkJobs.contains(where: { $0.path == jpgPath }) {
                    try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    artworkJobs.append(ArtworkJob(path: jpgPath, url: artwork, target: target))
                }
            }
        }
        await withTaskGroup(of: ArtworkResult.self) { group in
            for job in artworkJobs {
                group.addTask {
                    do {
                        _ = try await ArtworkDownloader.download(job.url, to: job.target)
                        return ArtworkResult(path: job.path)
                    } catch {
                        return ArtworkResult(path: job.path, failure: error.localizedDescription)
                    }
                }
            }
            for await result in group {
                if let failure = result.failure {
                    // An absent/expired image must not prevent the reviewed,
                    // otherwise complete NFO/rename transaction from being portable.
                    unavailableArtwork.append("\(result.path): \(failure)")
                } else {
                    generated.append(result.path)
                }
            }
        }
        let byFolder = Dictionary(grouping: outputLocations, by: { ($0.1 as NSString).deletingLastPathComponent })
        for (folder, items) in byFolder {
            // A regular season folder can include an aired special (season 0).
            // Its season.nfo should still describe the dominant regular season.
            let counts = Dictionary(grouping: items, by: { $0.0.canonical.season }).mapValues(\.count)
            guard let season = counts.filter({ $0.key > 0 }).max(by: { lhs, rhs in lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value })?.key else { continue }
            let path = folder.isEmpty || folder == "." ? "season.nfo" : folder + "/season.nfo"
            let metadata = series.seasons.first { $0.number == season }
            try write(NFOWriter.seasonData(number: season, title: metadata?.title, overview: metadata?.overview, premiered: metadata?.aired), relativePath: path, in: bundle)
            generated.append(path)
            if downloadArtwork, let artwork = metadata?.artworkURL {
                let artworkPath = folder.isEmpty || folder == "." ? "season.jpg" : folder + "/season.jpg"
                let target = generatedURL(for: artworkPath, in: bundle)
                do {
                    try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    _ = try await ArtworkDownloader.download(artwork, to: target)
                    generated.append(artworkPath)
                } catch {
                    unavailableArtwork.append("\(artworkPath): \(error.localizedDescription)")
                }
            }
        }

        generated.sort()
        var sourceLocations = [String: URL]()
        for mapping in mappings { if let path = try? relative(mapping.local.url, to: root) { sourceLocations[path] = mapping.local.url } }
        let manifest = PortableJobManifest(jobID: jobID, series: series, moves: moves, generatedFiles: generated, unavailableArtwork: unavailableArtwork.sorted(), notes: notes, sourceFingerprints: fingerprints(for: sourceLocations, mode: fingerprintMode))
        try finalize(manifest, in: bundle)
        return manifest
    }

    private static func relative(_ url: URL, to root: URL) throws -> String {
        let path = url.standardizedFileURL.path
        let rootPath = root.path
        guard path.hasPrefix(rootPath + "/") else { throw PortableJobBundleError.pathOutsideShowRoot(url) }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private static func fingerprints(for locations: [String: URL], mode: SourceFingerprintMode = .metadata, fileManager: FileManager = .default) -> [String: String] {
        Dictionary(uniqueKeysWithValues: locations.compactMap { relative, url in
            if mode == .sha256, let hash = sha256(url) { return (relative, "sha256:\(hash)") }
            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path), let size = attributes[.size] as? NSNumber, let date = attributes[.modificationDate] as? Date else { return nil }
            return (relative, "\(size.int64Value):\(Int64(date.timeIntervalSince1970))")
        })
    }

    private static func sha256(_ url: URL) -> String? {
        let process = Process(); let pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum"); process.arguments = ["-a", "256", url.path]; process.standardOutput = pipe
        guard (try? process.run()) != nil else { return nil }; process.waitUntilExit(); guard process.terminationStatus == 0 else { return nil }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: " ").first.map(String.init)
    }

    private static func replacingExtension(_ path: String, with extensionName: String) -> String {
        ((path as NSString).deletingPathExtension as NSString).appendingPathExtension(extensionName) ?? path
    }

    private static func generatedURL(for path: String, in bundle: URL) -> URL {
        bundle.appendingPathComponent("generated").appendingPathComponent(path)
    }

    private static func write(_ data: Data, relativePath: String, in bundle: URL) throws {
        let output = generatedURL(for: relativePath, in: bundle)
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: output, options: .atomic)
    }

    private static func script(_ text: String, named name: String, in bundle: URL) throws {
        let url = bundle.appendingPathComponent(name)
        try text.data(using: .utf8)!.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// Add a checksum manifest after every immutable package component has
    /// been written. `verify.sh` is deliberately portable to Catalina and
    /// Monterey: both ship `/usr/bin/shasum`.
    private static func finalize(_ manifest: PortableJobManifest, in bundle: URL, preservation: Bool = false) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: bundle.appendingPathComponent("manifest.json"), options: .atomic)
        try script(preservation ? preservationApplyScript(manifest) : applyScript(manifest), named: "apply.sh", in: bundle)
        try script(preservation ? preservationRollbackScript(manifest) : rollbackScript(manifest), named: "rollback.sh", in: bundle)
        let text = preservation ? preservationReadme(manifest) : readme(manifest)
        try text.data(using: .utf8)!.write(to: bundle.appendingPathComponent("README.txt"), options: .atomic)
        try script(integrityScript(), named: "verify.sh", in: bundle)
        try integrityManifest(in: bundle)
    }

    private static func integrityScript() -> String {
        """
        #!/usr/bin/env bash
        # Verifies the frozen MMM package before inspection or application.
        set -euo pipefail
        BUNDLE_DIR="$(cd "$(dirname "$0")" && pwd)"
        cd "$BUNDLE_DIR"
        /usr/bin/shasum -a 256 -c SHA256SUMS
        echo "Package integrity verified."
        """
    }

    private static func integrityManifest(in bundle: URL) throws {
        let names = ["README.txt", "apply.sh", "manifest.json", "rollback.sh", "verify.sh"] + generatedRelativeFiles(in: bundle)
        var lines = [String]()
        for name in names.sorted() {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
            process.currentDirectoryURL = bundle
            process.arguments = ["-a", "256", name]
            let output = Pipe(); process.standardOutput = output
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw PortableJobBundleError.integrityManifestFailed }
            let line = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append(line)
        }
        try (lines.joined(separator: "\n") + "\n").write(to: bundle.appendingPathComponent("SHA256SUMS"), atomically: true, encoding: .utf8)
    }

    private static func generatedRelativeFiles(in bundle: URL) -> [String] {
        let generated = bundle.appendingPathComponent("generated", isDirectory: true)
        guard let files = FileManager.default.enumerator(at: generated, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return files.compactMap { $0 as? URL }.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
            let path = url.standardizedFileURL.path
            let root = generated.standardizedFileURL.path + "/"
            guard path.hasPrefix(root) else { return nil }
            return "generated/" + String(path.dropFirst(root.count))
        }
    }

    private static func applyScript(_ manifest: PortableJobManifest) -> String {
        let preflights = manifest.moves.map { "preflight_video \(quote($0.source)) \(quote($0.destination))" }.joined(separator: "\n")
        let moves = manifest.moves.map { "move_video \(quote($0.source)) \(quote($0.destination))" }.joined(separator: "\n")
        let generatedPreflights = manifest.generatedFiles.map { "preflight_generated \(quote($0))" }.joined(separator: "\n")
        let fingerprintPreflights = manifest.sourceFingerprints.sorted { $0.key < $1.key }.map { "preflight_fingerprint \(quote($0.key)) \(quote($0.value))" }.joined(separator: "\n")
        let installs = manifest.generatedFiles.map { "install_generated \(quote($0))" }.joined(separator: "\n")
        return """
        #!/usr/bin/env bash
        # Frozen NoSide Media Manager job \(manifest.jobID). Generated; do not edit paths.
        set -euo pipefail
        shopt -s nullglob
        usage() { echo "Usage: $0 [--dry-run] /path/to/show-root" >&2; exit 64; }
        DRY_RUN=false; ROOT=""
        for arg in "$@"; do
          if [[ "$arg" == "--dry-run" ]]; then DRY_RUN=true
          elif [[ -z "$ROOT" ]]; then ROOT="$arg"
          else usage; fi
        done
        [[ -n "$ROOT" && -d "$ROOT" ]] || usage
        ROOT="$(cd "$ROOT" && pwd)"
        BUNDLE_DIR="$(cd "$(dirname "$0")" && pwd)"
        "$BUNDLE_DIR/verify.sh"
        BACKUP_ROOT="$ROOT/.noside-mmm-backups/\(manifest.jobID)"
        CREATED="$BACKUP_ROOT/created-files.txt"
        run() { if $DRY_RUN; then printf 'DRY-RUN:'; printf ' %q' "$@"; printf '\\n'; else "$@"; fi; }
        backup() { local rel target saved; rel="$1"; target="$ROOT/$rel"; saved="$BACKUP_ROOT/$rel"; [[ -e "$target" ]] || return 0; [[ -e "$saved" ]] && return 0; run mkdir -p "$(dirname "$saved")"; run cp -p "$target" "$saved"; }
        mark_created() { local rel="$1"; if [[ ! -e "$ROOT/$rel" ]]; then run mkdir -p "$BACKUP_ROOT"; if $DRY_RUN; then echo "DRY-RUN: record created $rel"; else printf '%s\\n' "$rel" >> "$CREATED"; fi; fi; }
        preflight_video() { [[ -f "$ROOT/$1" ]] || { echo "Missing video: $1" >&2; exit 1; }; [[ ! -e "$ROOT/$2" ]] || { echo "Destination video already exists: $2" >&2; exit 1; }; }
        preflight_fingerprint() { local actual; if [[ "$2" == sha256:* ]]; then actual="sha256:$(shasum -a 256 "$ROOT/$1" | awk '{print $1}')"; else actual="$(stat -f '%z:%m' "$ROOT/$1")"; fi; [[ "$actual" == "$2" ]] || { echo "Video changed since review: $1 (expected $2, found $actual)" >&2; exit 1; }; }
        preflight_generated() { [[ -f "$BUNDLE_DIR/generated/$1" ]] || { echo "Bundle is missing generated/$1" >&2; exit 1; }; }
        move_optional() { local src="$1" dst="$2"; [[ -e "$ROOT/$src" ]] || return 0; backup "$dst"; run mkdir -p "$(dirname "$ROOT/$dst")"; run mv "$ROOT/$src" "$ROOT/$dst"; }
        move_video() {
          local src="$1" dst="$2" srcbase="${1%.*}" dstbase="${2%.*}" suffix sidecar target
          [[ -f "$ROOT/$src" ]] || { echo "Missing video: $src" >&2; exit 1; }
          [[ ! -e "$ROOT/$dst" ]] || { echo "Destination video already exists: $dst" >&2; exit 1; }
          run mkdir -p "$(dirname "$ROOT/$dst")"; run mv "$ROOT/$src" "$ROOT/$dst"
          # NFO is regenerated. Preserve it for rollback instead of trusting it as metadata.
          if [[ -e "$ROOT/$srcbase.nfo" ]]; then backup "$srcbase.nfo"; run rm -f "$ROOT/$srcbase.nfo"; fi
          # Preserve old image sidecars when new TVDB artwork is bundled; otherwise move them.
          for sidecar in "$ROOT/$srcbase".{jpg,jpeg,png}; do
            [[ -e "$sidecar" ]] || continue; suffix="${sidecar#"$ROOT/$srcbase"}"; target="$dstbase$suffix"
            if [[ -f "$BUNDLE_DIR/generated/$dstbase.jpg" ]]; then backup "$srcbase$suffix"; run rm -f "$sidecar"; else move_optional "$srcbase$suffix" "$target"; fi
          done
          # Language-bearing subtitle suffixes are retained, e.g. .en.srt.
          for sidecar in "$ROOT/$srcbase"*.{srt,ass,ssa,sub,idx,vtt}; do
            [[ -e "$sidecar" ]] || continue; suffix="${sidecar#"$ROOT/$srcbase"}"; move_optional "$srcbase$suffix" "$dstbase$suffix"
          done
        }
        install_generated() { local rel="$1"; [[ -f "$BUNDLE_DIR/generated/$rel" ]] || { echo "Bundle is missing generated/$rel" >&2; exit 1; }; backup "$rel"; mark_created "$rel"; run mkdir -p "$(dirname "$ROOT/$rel")"; run cp -p "$BUNDLE_DIR/generated/$rel" "$ROOT/$rel"; }
        # Validate the complete frozen plan before altering a media file.
        \(preflights)
        \(fingerprintPreflights)
        \(generatedPreflights)
        \(moves)
        \(installs)
        if $DRY_RUN; then echo "Dry run complete: no media-library files changed."; else rm -f "$BACKUP_ROOT/rolled-back"; echo "Applied \(manifest.jobID). Backup: $BACKUP_ROOT"; fi
        """
    }

    private static func preservationApplyScript(_ manifest: PortableJobManifest) -> String {
        let preflights = manifest.moves.map { "preflight_move \(quote($0.source)) \(quote($0.destination))" }.joined(separator: "\n")
        let sidecarPreflights = manifest.sidecarMoves.map { "preflight_sidecar \(quote($0.source)) \(quote($0.destination))" }.joined(separator: "\n")
        let fingerprints = manifest.sourceFingerprints.sorted { $0.key < $1.key }.map { "preflight_fingerprint \(quote($0.key)) \(quote($0.value))" }.joined(separator: "\n")
        let moves = manifest.moves.map { "move_with_sidecars \(quote($0.source)) \(quote($0.destination))" }.joined(separator: "\n")
        let sidecarMoves = manifest.sidecarMoves.map { "move_sidecar \(quote($0.source)) \(quote($0.destination))" }.joined(separator: "\n")
        return """
        #!/usr/bin/env bash
        # Frozen NoSide Media Manager preservation job \(manifest.jobID). Generated; do not edit paths.
        set -euo pipefail
        shopt -s nullglob
        usage() { echo "Usage: $0 [--dry-run] /path/to/movie-library-root" >&2; exit 64; }
        DRY_RUN=false; ROOT=""
        for arg in "$@"; do if [[ "$arg" == "--dry-run" ]]; then DRY_RUN=true; elif [[ -z "$ROOT" ]]; then ROOT="$arg"; else usage; fi; done
        [[ -n "$ROOT" && -d "$ROOT" ]] || usage
        ROOT="$(cd "$ROOT" && pwd)"; BUNDLE_DIR="$(cd "$(dirname "$0")" && pwd)"; "$BUNDLE_DIR/verify.sh"; BACKUP_ROOT="$ROOT/.noside-mmm-backups/\(manifest.jobID)"
        run() { if $DRY_RUN; then printf 'DRY-RUN:'; printf ' %q' "$@"; printf '\\n'; else "$@"; fi; }
        sidecars() {
          local base="$1"; local file
          # Exact stem, recognised artwork names, and language subtitle suffixes.
          # Do not use "$base"*: "Pride" must not claim "Pride lowres".
          for file in "$ROOT/$base".{nfo,srt,ass,ssa,sub,idx,vtt,jpg,jpeg,png,tbn} "$ROOT/$base"-*.{jpg,jpeg,png,tbn} "$ROOT/$base".*.{srt,ass,ssa,sub,idx,vtt}; do
            [[ -e "$file" ]] && printf '%s\\n' "$file"
          done
        }
        preflight_fingerprint() { local actual; if [[ "$2" == sha256:* ]]; then actual="sha256:$(shasum -a 256 "$ROOT/$1" | awk '{print $1}')"; else actual="$(stat -f '%z:%m' "$ROOT/$1")"; fi; [[ "$actual" == "$2" ]] || { echo "Video changed since review: $1 (expected $2, found $actual)" >&2; exit 1; }; }
        preflight_move() {
          local src="$1" dst="$2" srcbase="${1%.*}" dstbase="${2%.*}" sidecar suffix target
          [[ -f "$ROOT/$src" ]] || { echo "Missing video: $src" >&2; exit 1; }
          [[ ! -e "$ROOT/$dst" ]] || { echo "Destination video already exists: $dst" >&2; exit 1; }
          while IFS= read -r sidecar; do suffix="${sidecar#"$ROOT/$srcbase"}"; target="$ROOT/$dstbase$suffix"; [[ ! -e "$target" ]] || { echo "Destination sidecar already exists: ${target#"$ROOT/"}" >&2; exit 1; }; done < <(sidecars "$srcbase")
        }
        preflight_sidecar() { [[ -f "$ROOT/$1" ]] || { echo "Missing shared sidecar: $1" >&2; exit 1; }; [[ ! -e "$ROOT/$2" ]] || { echo "Destination sidecar already exists: $2" >&2; exit 1; }; }
        move_with_sidecars() {
          local src="$1" dst="$2" srcbase="${1%.*}" dstbase="${2%.*}" sidecar suffix
          run mkdir -p "$BACKUP_ROOT" "$(dirname "$ROOT/$dst")"; run mv "$ROOT/$src" "$ROOT/$dst"
          while IFS= read -r sidecar; do suffix="${sidecar#"$ROOT/$srcbase"}"; run mkdir -p "$(dirname "$ROOT/$dstbase$suffix")"; run mv "$sidecar" "$ROOT/$dstbase$suffix"; done < <(sidecars "$srcbase")
        }
        move_sidecar() { run mkdir -p "$BACKUP_ROOT" "$(dirname "$ROOT/$2")"; run mv "$ROOT/$1" "$ROOT/$2"; }
        # Validate every destination and every reviewed source before moving anything.
        \(preflights)
        \(sidecarPreflights)
        \(fingerprints)
        \(moves)
        \(sidecarMoves)
        if $DRY_RUN; then echo "Dry run complete: no media-library files changed."; else rm -f "$BACKUP_ROOT/rolled-back"; echo "Applied \(manifest.jobID). Backup marker: $BACKUP_ROOT"; fi
        """
    }

    private static func preservationRollbackScript(_ manifest: PortableJobManifest) -> String {
        let moves = manifest.moves.reversed().map { "rollback_with_sidecars \(quote($0.destination)) \(quote($0.source))" }.joined(separator: "\n")
        let sidecarMoves = manifest.sidecarMoves.reversed().map { "rollback_sidecar \(quote($0.destination)) \(quote($0.source))" }.joined(separator: "\n")
        return """
        #!/usr/bin/env bash
        # Reverses NoSide Media Manager preservation job \(manifest.jobID).
        set -euo pipefail
        shopt -s nullglob
        usage() { echo "Usage: $0 [--dry-run] /path/to/movie-library-root" >&2; exit 64; }
        DRY_RUN=false; ROOT=""
        for arg in "$@"; do if [[ "$arg" == "--dry-run" ]]; then DRY_RUN=true; elif [[ -z "$ROOT" ]]; then ROOT="$arg"; else usage; fi; done
        [[ -n "$ROOT" && -d "$ROOT" ]] || usage
        ROOT="$(cd "$ROOT" && pwd)"; BACKUP_ROOT="$ROOT/.noside-mmm-backups/\(manifest.jobID)"
        [[ -d "$BACKUP_ROOT" ]] || { echo "Applied-job marker not found: $BACKUP_ROOT" >&2; exit 1; }
        run() { if $DRY_RUN; then printf 'DRY-RUN:'; printf ' %q' "$@"; printf '\\n'; else "$@"; fi; }
        sidecars() {
          local base="$1"; local file
          for file in "$ROOT/$base".{nfo,srt,ass,ssa,sub,idx,vtt,jpg,jpeg,png,tbn} "$ROOT/$base"-*.{jpg,jpeg,png,tbn} "$ROOT/$base".*.{srt,ass,ssa,sub,idx,vtt}; do
            [[ -e "$file" ]] && printf '%s\\n' "$file"
          done
        }
        rollback_with_sidecars() {
          local src="$1" dst="$2" srcbase="${1%.*}" dstbase="${2%.*}" sidecar suffix target
          [[ -f "$ROOT/$src" ]] || { echo "Missing moved video: $src" >&2; exit 1; }
          [[ ! -e "$ROOT/$dst" ]] || { echo "Rollback collision: $dst" >&2; exit 1; }
          while IFS= read -r sidecar; do suffix="${sidecar#"$ROOT/$srcbase"}"; target="$ROOT/$dstbase$suffix"; [[ ! -e "$target" ]] || { echo "Rollback collision: ${target#"$ROOT/"}" >&2; exit 1; }; done < <(sidecars "$srcbase")
          run mkdir -p "$(dirname "$ROOT/$dst")"; run mv "$ROOT/$src" "$ROOT/$dst"
          while IFS= read -r sidecar; do suffix="${sidecar#"$ROOT/$srcbase"}"; run mkdir -p "$(dirname "$ROOT/$dstbase$suffix")"; run mv "$sidecar" "$ROOT/$dstbase$suffix"; done < <(sidecars "$srcbase")
        }
        rollback_sidecar() { [[ -f "$ROOT/$1" ]] || { echo "Missing moved sidecar: $1" >&2; exit 1; }; [[ ! -e "$ROOT/$2" ]] || { echo "Rollback collision: $2" >&2; exit 1; }; run mkdir -p "$(dirname "$ROOT/$2")"; run mv "$ROOT/$1" "$ROOT/$2"; }
        \(sidecarMoves)
        \(moves)
        if $DRY_RUN; then echo "Dry-run rollback complete: no media-library files changed."; else touch "$BACKUP_ROOT/rolled-back"; echo "Rollback complete for \(manifest.jobID)."; fi
        """
    }

    private static func rollbackScript(_ manifest: PortableJobManifest) -> String {
        let reverseMoves = manifest.moves.reversed().map { "rollback_video \(quote($0.destination)) \(quote($0.source))" }.joined(separator: "\n")
        return """
        #!/usr/bin/env bash
        # Reverses NoSide Media Manager job \(manifest.jobID) where its backup remains available.
        set -euo pipefail
        shopt -s nullglob
        usage() { echo "Usage: $0 [--dry-run] /path/to/show-root" >&2; exit 64; }
        DRY_RUN=false; ROOT=""
        for arg in "$@"; do if [[ "$arg" == "--dry-run" ]]; then DRY_RUN=true; elif [[ -z "$ROOT" ]]; then ROOT="$arg"; else usage; fi; done
        [[ -n "$ROOT" && -d "$ROOT" ]] || usage
        ROOT="$(cd "$ROOT" && pwd)"; BACKUP_ROOT="$ROOT/.noside-mmm-backups/\(manifest.jobID)"; CREATED="$BACKUP_ROOT/created-files.txt"
        [[ -d "$BACKUP_ROOT" ]] || { echo "Backup not found: $BACKUP_ROOT" >&2; exit 1; }
        run() { if $DRY_RUN; then printf 'DRY-RUN:'; printf ' %q' "$@"; printf '\\n'; else "$@"; fi; }
        rollback_optional() { local src="$1" dst="$2"; [[ -e "$ROOT/$src" ]] || return 0; [[ ! -e "$ROOT/$dst" ]] || { echo "Rollback collision: $dst" >&2; exit 1; }; run mkdir -p "$(dirname "$ROOT/$dst")"; run mv "$ROOT/$src" "$ROOT/$dst"; }
        rollback_video() { local src="$1" dst="$2" srcbase="${1%.*}" dstbase="${2%.*}" suffix sidecar; [[ -f "$ROOT/$src" ]] || { echo "Missing moved video: $src" >&2; exit 1; }; rollback_optional "$src" "$dst"; for sidecar in "$ROOT/$srcbase"*.{srt,ass,ssa,sub,idx,vtt,jpg,jpeg,png}; do [[ -e "$sidecar" ]] || continue; suffix="${sidecar#"$ROOT/$srcbase"}"; rollback_optional "$srcbase$suffix" "$dstbase$suffix"; done; }
        # Remove generated files that did not replace an original; then reverse moves.
        if [[ -f "$CREATED" ]]; then while IFS= read -r rel; do [[ -n "$rel" ]] && run rm -f "$ROOT/$rel"; done < "$CREATED"; fi
        \(reverseMoves)
        # Restore every original sidecar or destination collision saved by apply.sh.
        if $DRY_RUN; then echo "DRY-RUN: restore $BACKUP_ROOT into $ROOT"; else (cd "$BACKUP_ROOT" && find . -type f ! -name created-files.txt -exec sh -c 'root="$1"; shift; for f do d="$root/${f#./}"; mkdir -p "$(dirname "$d")"; cp -p "$f" "$d"; done' sh "$ROOT" {} +); fi
        if $DRY_RUN; then echo "Dry-run rollback complete: no media-library files changed."; else touch "$BACKUP_ROOT/rolled-back"; echo "Rollback complete for \(manifest.jobID). Keep or archive $BACKUP_ROOT after verification."; fi
        """
    }

    private static func readme(_ manifest: PortableJobManifest) -> String {
        """
        NoSide Media Manager portable job
        =================================
        \(manifest.mediaKind == "movie" ? "Movie" : "Series"): \(manifest.seriesTitle) (\(manifest.metadataProvider.uppercased()) \(manifest.seriesTVDBID))
        Job: \(manifest.jobID)

        This package is intentionally portable: it contains generated XML/NFO and
        artwork, not any media files. It never embeds a machine-specific media path.

        On the Mac with the real library:
          ./apply.sh --dry-run "/path/to/library-root"
          ./apply.sh "/path/to/library-root"

        To undo after a successful apply:
          ./rollback.sh --dry-run "/path/to/library-root"
          ./rollback.sh "/path/to/library-root"

        Apply creates a local backup under `.noside-mmm-backups/\(manifest.jobID)`.
        Keep it until Emby and the files have been verified. `manifest.json` is the
        frozen review record; `generated/` holds the exact sidecars to be installed.
        \(manifest.unavailableArtwork.isEmpty ? "All requested TVDB episode artwork was bundled." : "TVDB artwork unavailable for \(manifest.unavailableArtwork.count) item(s); see manifest.json. NFOs and all available artwork are included.")
        \(manifest.notes.isEmpty ? "" : "Notes:\n" + manifest.notes.map { "- \($0)" }.joined(separator: "\n"))
        """
    }

    private static func preservationReadme(_ manifest: PortableJobManifest) -> String {
        """
        NoSide Media Manager preservation job
        =====================================
        Existing movie library normalisation
        Job: \(manifest.jobID)

        This frozen package makes no new metadata and downloads no artwork. It
        moves each reviewed video plus matching NFO, poster, fanart, logo, and
        subtitle sidecars unchanged into its planned movie folder.

        On the Mac with the real library:
          ./apply.sh --dry-run "/path/to/movie-library-root"
          ./apply.sh "/path/to/movie-library-root"

        To undo after a successful apply:
          ./rollback.sh --dry-run "/path/to/movie-library-root"
          ./rollback.sh "/path/to/movie-library-root"

        Apply creates `.noside-mmm-backups/\(manifest.jobID)` as an applied-job
        marker. The transaction refuses any destination collision and verifies
        each video fingerprint before it begins.
        """
    }

    private static func quote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}

private struct ArtworkJob: Sendable {
    let path: String
    let url: URL
    let target: URL
}

private struct ArtworkResult: Sendable {
    let path: String
    let failure: String?
    init(path: String, failure: String? = nil) { self.path = path; self.failure = failure }
}
