import Foundation

public enum MovieSidecarState: String, Codable, Sendable { case complete, embeddedMetadataNeedsSidecars, bareNeedsTMDB, incompleteSidecars }
/// A conservative, filename-derived label for content that should be reviewed
/// as an edition or extra rather than silently treated as the main feature.
public enum MovieContentKind: String, Codable, Sendable {
    case feature, edition, alternateEncode, trailer, featurette, behindTheScenes, commentary

    public var requiresExplicitReview: Bool {
        switch self { case .feature, .edition: false; default: true }
    }
}
/// Layout is intentionally reported separately from metadata readiness: a film
/// may be complete but still need its files moved into a canonical movie folder.
public enum MovieFolderState: String, Codable, Sendable { case normalized, needsNormalization, metadataIncomplete, sharedMultiPart }
public struct MovieAuditItem: Codable, Sendable, Equatable {
    public let videoPath: String; public let nfoExists: Bool; public let artworkExists: Bool; public let embeddedTitle: String?; public let embeddedCreationDate: String?; public let hasEmbeddedArtwork: Bool; public let tmdbID: Int?; public let nfoTitle: String?; public let nfoYear: String?; public let nfoIsValid: Bool?; public let editionHint: String?; public let contentKind: MovieContentKind?; public let subtitleLanguages: [String]?; public let fileSize: Int64?; public let width: Int?; public let height: Int?; public let state: MovieSidecarState; public let folderState: MovieFolderState
    public init(videoPath: String, nfoExists: Bool, artworkExists: Bool, embeddedTitle: String?, embeddedCreationDate: String?, hasEmbeddedArtwork: Bool, tmdbID: Int?, nfoTitle: String?, nfoYear: String?, nfoIsValid: Bool?, editionHint: String?, contentKind: MovieContentKind? = nil, subtitleLanguages: [String]? = nil, fileSize: Int64? = nil, width: Int? = nil, height: Int? = nil, state: MovieSidecarState, folderState: MovieFolderState = .metadataIncomplete) {
        self.videoPath = videoPath; self.nfoExists = nfoExists; self.artworkExists = artworkExists; self.embeddedTitle = embeddedTitle; self.embeddedCreationDate = embeddedCreationDate; self.hasEmbeddedArtwork = hasEmbeddedArtwork; self.tmdbID = tmdbID; self.nfoTitle = nfoTitle; self.nfoYear = nfoYear; self.nfoIsValid = nfoIsValid; self.editionHint = editionHint; self.contentKind = contentKind; self.subtitleLanguages = subtitleLanguages; self.fileSize = fileSize; self.width = width; self.height = height; self.state = state; self.folderState = folderState
    }
    public var isMultiPart: Bool { folderState == .sharedMultiPart }
    public var isPreservationReady: Bool { state == .complete && nfoIsValid == true && tmdbID != nil && folderState == .needsNormalization }
    public var isMultiPartPreservationReady: Bool { state == .complete && nfoIsValid == true && tmdbID != nil && folderState == .sharedMultiPart }
    public var isArtworkRepairReady: Bool { state == .incompleteSidecars && nfoIsValid == true && tmdbID != nil && hasEmbeddedArtwork }
    public var isEmbeddedSidecarReady: Bool { state == .embeddedMetadataNeedsSidecars && !(embeddedTitle?.isEmpty ?? true) }
}
public struct MovieLibraryHealthReport: Codable, Sendable, Equatable {
    public let items: [MovieAuditItem]; public let duplicateTMDBIDs: [String: [String]]; public let invalidNFOs: [String]; public let ignoredVideoFiles: [String]
    public var summary: [String: Int] { Dictionary(grouping: items, by: { $0.state.rawValue }).mapValues(\.count) }
    public var folderSummary: [String: Int] { Dictionary(grouping: items, by: { $0.folderState.rawValue }).mapValues(\.count) }
}
public enum MovieLibraryAudit {
    /// An optional plain-text, library-root `.noside-mmm-ignore` file can list
    /// relative files or directory names, one per line. Blank lines and `#`
    /// comments are ignored. It is deliberately local XML-adjacent state: no
    /// database and no machine-specific paths are required.
    public enum IgnoreRuleError: LocalizedError { case invalidRule; public var errorDescription: String? { "Ignore rules must be relative paths inside the movie library." } }
    public static func ignoreRules(in directory: URL, fileManager: FileManager = .default) -> [String] { customIgnoreRules(in: directory, fileManager: fileManager).sorted() }
    /// Updates only MMM's small, human-editable library configuration file.
    /// It never moves, renames, or changes a media item.
    public static func addIgnoreRule(_ rule: String, in directory: URL, fileManager: FileManager = .default) throws {
        let cleaned = rule.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !cleaned.isEmpty, !cleaned.hasPrefix("."), !cleaned.split(separator: "/").contains("..") else { throw IgnoreRuleError.invalidRule }
        var rules = customIgnoreRules(in: directory, fileManager: fileManager)
        rules.insert(cleaned)
        let output = "# NoSide Media Manager audit exclusions (relative to this library root)\n" + rules.sorted().joined(separator: "\n") + "\n"
        try output.write(to: directory.appendingPathComponent(".noside-mmm-ignore"), atomically: true, encoding: .utf8)
    }
    static func ignoredVideoFiles(in directory: URL, fileManager: FileManager = .default) -> [URL] {
        let rules = customIgnoreRules(in: directory, fileManager: fileManager)
        return MediaFileInspector.videoFiles(in: directory, fileManager: fileManager)
            .filter { isIgnored($0, libraryRoot: directory, customRules: rules) }
    }

    /// Checks the current library's standard and user-managed exclusions.
    /// It is read-only and can safely be used by a UI to hide already-loaded
    /// audit rows immediately after an exclusion is added.
    public static func isIgnored(_ video: URL, libraryRoot: URL, customRules: Set<String>? = nil, fileManager: FileManager = .default) -> Bool {
        isIgnoredInternal(video, libraryRoot: libraryRoot, customRules: customRules ?? customIgnoreRules(in: libraryRoot, fileManager: fileManager))
    }

    private static func isIgnoredInternal(_ video: URL, libraryRoot: URL, customRules: Set<String>) -> Bool {
        let root = libraryRoot.standardizedFileURL.path + "/"
        let path = video.standardizedFileURL.path
        guard path.hasPrefix(root) else { return false }
        let relative = String(path.dropFirst(root.count))
        let components = relative.split(separator: "/").map(String.init)
        // iTunes Extras packages often include motion loops, trailers, menus,
        // and other ancillary clips under a .ite subfolder. Keep a possible
        // top-level feature file in the package, but omit descendants.
        if let ite = components.firstIndex(where: { $0.lowercased().hasSuffix(".ite") }), ite + 2 < components.count { return true }
        return customRules.contains { relative == $0 || relative.hasPrefix($0 + "/") }
    }

    private static func customIgnoreRules(in directory: URL, fileManager: FileManager) -> Set<String> {
        let file = directory.appendingPathComponent(".noside-mmm-ignore")
        guard let text = try? String(contentsOf: file) else { return [] }
        return Set(text.split(whereSeparator: { $0.isNewline }).map(String.init).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) })
    }
    public static func classify(nfoExists: Bool, artworkExists: Bool, info: EmbeddedMediaInfo) -> MovieSidecarState {
        if nfoExists && artworkExists { return .complete }
        if !nfoExists && !artworkExists && (info.title != nil || info.creationDate != nil || info.hasEmbeddedArtwork) { return .embeddedMetadataNeedsSidecars }
        if !nfoExists && !artworkExists { return .bareNeedsTMDB }
        return .incompleteSidecars
    }
    @MainActor public static func inspect(directory: URL, progress: (@MainActor @Sendable (Int, Int) -> Void)? = nil) async -> [MovieAuditItem] {
        var items = [MovieAuditItem]()
        let videos = MediaFileInspector.videoFiles(in: directory).filter { !isIgnored($0, libraryRoot: directory, customRules: customIgnoreRules(in: directory, fileManager: .default)) }
        progress?(0, videos.count)
        for (index, video) in videos.enumerated() {
            // MKV and older AVI containers are not always readable by
            // AVFoundation. They remain real library videos and must be
            // reviewed as bare items, never silently omitted from an audit.
            let info = (try? await MediaFileInspector.inspect(video)) ?? EmbeddedMediaInfo(fileName: video.lastPathComponent, title: nil, creationDate: nil, durationSeconds: nil, width: nil, height: nil, audioLanguages: [], subtitleLanguages: [], hasEmbeddedArtwork: false)
            let base = video.deletingPathExtension()
            // CD/Disc/Part files may deliberately share a single movie NFO and
            // artwork. Treat that shared set as complete, never as three
            // separate embedded-metadata candidates.
            let sharedBase = multiPartBase(for: base)
            let sidecarBase = sharedBase ?? base
            let nfo = sidecarBase.appendingPathExtension("nfo"); let nfoExists = FileManager.default.fileExists(atPath: nfo.path); let parsed = nfoExists ? inspectNFO(nfo) : nil
            let image = primaryArtworkExists(for: sidecarBase)
            let state = classify(nfoExists: nfoExists, artworkExists: image, info: info)
            let folderState: MovieFolderState = sharedBase == nil ? folderState(for: video, nfo: parsed, sidecarState: state) : .sharedMultiPart
            let content = contentClassification(video.lastPathComponent)
            let fileSize = try? video.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init)
            items.append(MovieAuditItem(videoPath: video.path, nfoExists: nfoExists, artworkExists: image, embeddedTitle: info.title, embeddedCreationDate: info.creationDate, hasEmbeddedArtwork: info.hasEmbeddedArtwork, tmdbID: parsed?.id, nfoTitle: parsed?.title, nfoYear: parsed?.year, nfoIsValid: nfoExists ? parsed?.valid ?? false : nil, editionHint: content.hint, contentKind: content.kind, subtitleLanguages: info.subtitleLanguages, fileSize: fileSize, width: info.width, height: info.height, state: state, folderState: folderState))
            progress?(index + 1, videos.count)
        }
        return items
    }
    /// Supports both MMM's stem artwork and tinyMediaManager's conventional
    /// `Title-poster.jpg` sidecar. In a canonical movie folder, Emby also
    /// recognises `poster.jpg`/`folder.jpg`; accept those only when the folder
    /// name matches the movie stem, so a library-root poster cannot bless every
    /// loose video as complete.
    static func primaryArtworkExists(for base: URL, fileManager: FileManager = .default) -> Bool {
        if ["", "-poster"].contains(where: { suffix in
            ["jpg", "jpeg", "png"].contains { fileManager.fileExists(atPath: URL(fileURLWithPath: base.path + suffix).appendingPathExtension($0).path) }
        }) { return true }
        let folder = base.deletingLastPathComponent()
        guard folder.lastPathComponent.caseInsensitiveCompare(base.lastPathComponent) == .orderedSame else { return false }
        return ["poster", "folder", "cover", "default", "movie"].contains { stem in
            ["jpg", "jpeg", "png"].contains { fileManager.fileExists(atPath: folder.appendingPathComponent(stem).appendingPathExtension($0).path) }
        }
    }
    @MainActor public static func health(directory: URL, progress: (@MainActor @Sendable (Int, Int) -> Void)? = nil) async -> MovieLibraryHealthReport {
        let items = await inspect(directory: directory, progress: progress)
        let pairs = items.compactMap { item -> (String, String)? in item.tmdbID.map { (String($0), item.videoPath) } }
        let duplicates = Dictionary(grouping: pairs, by: \.0).compactMapValues { values in values.count > 1 ? values.map(\.1).sorted() : nil }
        let ignored = ignoredVideoFiles(in: directory).map(\.path).sorted()
        return MovieLibraryHealthReport(items: items, duplicateTMDBIDs: duplicates, invalidNFOs: items.filter { $0.nfoIsValid == false }.map(\.videoPath).sorted(), ignoredVideoFiles: ignored)
    }
    public static func orphanSidecars(in directory: URL, fileManager: FileManager = .default) -> [String] {
        let videos = MediaFileInspector.videoFiles(in: directory, fileManager: fileManager).map { $0.deletingPathExtension().standardizedFileURL.path }
        let extensions: Set<String> = ["nfo", "jpg", "jpeg", "png", "srt", "ass", "ssa", "sub", "idx", "vtt"]
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { sidecar in
            guard extensions.contains(sidecar.pathExtension.lowercased()) else { return false }
            let stem = sidecar.deletingPathExtension().standardizedFileURL.path
            return !videos.contains { video in
                stem == video || stem.hasPrefix(video + ".") || stem.hasPrefix(video + "-")
            }
        }.map(\.path).sorted()
    }
    /// A portable, read-only companion to `movie-health` JSON for a person
    /// reviewing a library outside MMM. It contains no provider calls and no
    /// media paths beyond those already in the audit report.
    public static func htmlReport(_ report: MovieLibraryHealthReport) -> String {
        func escaped(_ text: String) -> String { text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;") }
        let summary = report.summary.sorted { $0.key < $1.key }.map { "<li><strong>\(escaped($0.key))</strong>: \($0.value)</li>" }.joined()
        let rows = report.items.sorted { $0.videoPath.localizedStandardCompare($1.videoPath) == .orderedAscending }.map { item in "<tr><td>\(escaped(item.nfoTitle ?? URL(fileURLWithPath: item.videoPath).lastPathComponent))</td><td>\(escaped(item.state.rawValue))</td><td>\(escaped(item.folderState.rawValue))</td><td><code>\(escaped(item.videoPath))</code></td></tr>" }.joined()
        let invalid = report.invalidNFOs.map { "<li><code>\(escaped($0))</code></li>" }.joined()
        let duplicates = report.duplicateTMDBIDs.sorted { $0.key < $1.key }.map { id, paths in "<li>TMDB \(escaped(id)): \(paths.map { "<code>\(escaped($0))</code>" }.joined(separator: ", "))</li>" }.joined()
        let ignored = report.ignoredVideoFiles.map { "<li><code>\(escaped($0))</code></li>" }.joined()
        return "<!doctype html><html><head><meta charset=\"utf-8\"><title>NoSide MMM movie health</title><style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;margin:2rem;color:#202124}table{border-collapse:collapse;width:100%}th,td{padding:.5rem;border-bottom:1px solid #ddd;text-align:left;vertical-align:top}code{font-size:.85em}h2{margin-top:2rem}</style></head><body><h1>NoSide MMM movie health</h1><p>\(report.items.count) audited video(s); \(report.ignoredVideoFiles.count) ignored extra(s).</p><h2>Summary</h2><ul>\(summary)</ul><h2>Audited movies</h2><table><thead><tr><th>Title</th><th>Metadata</th><th>Layout</th><th>Path</th></tr></thead><tbody>\(rows)</tbody></table><h2>Invalid NFOs</h2><ul>\(invalid.isEmpty ? "<li>None</li>" : invalid)</ul><h2>Duplicate TMDB IDs</h2><ul>\(duplicates.isEmpty ? "<li>None</li>" : duplicates)</ul><h2>Ignored extras</h2><ul>\(ignored.isEmpty ? "<li>None</li>" : ignored)</ul></body></html>"
    }
    private static func inspectNFO(_ url: URL) -> (id: Int?, title: String?, year: String?, valid: Bool) {
        guard let document = try? XMLDocument(contentsOf: url, options: []), document.rootElement()?.name == "movie" else { return (nil, nil, nil, false) }
        let identifier = (try? document.nodes(forXPath: "/movie/uniqueid[@type='tmdb']"))?.first?.stringValue.flatMap(Int.init)
        let title = (try? document.nodes(forXPath: "/movie/title"))?.first?.stringValue
        let year = (try? document.nodes(forXPath: "/movie/year"))?.first?.stringValue
        return (identifier, title?.trimmingCharacters(in: .whitespacesAndNewlines), year?.trimmingCharacters(in: .whitespacesAndNewlines), true)
    }
    static func contentClassification(_ name: String) -> (kind: MovieContentKind, hint: String?) {
        let lower = name.lowercased()
        let values: [(String, MovieContentKind)] = [("trailer", .trailer), ("featurette", .featurette), ("behind the scenes", .behindTheScenes), ("commentary", .commentary), ("director's cut", .edition), ("directors cut", .edition), ("extended", .edition), ("remux", .alternateEncode), ("3d", .alternateEncode)]
        for (hint, kind) in values where lower.contains(hint) { return (kind, hint) }
        return (.feature, nil)
    }
    static func folderState(for video: URL, nfo: (id: Int?, title: String?, year: String?, valid: Bool)?, sidecarState: MovieSidecarState) -> MovieFolderState {
        guard sidecarState == .complete, nfo?.valid == true, nfo?.id != nil,
              let title = nfo?.title, !title.isEmpty else { return .metadataIncomplete }
        let stem = MoviePlanDocument.safe(title) + (nfo?.year.flatMap { $0.isEmpty ? nil : $0 }.map { " (\($0))" } ?? "")
        let expectedVideo = stem + "." + video.pathExtension
        let editionVideo = video.lastPathComponent.hasPrefix(stem + " [") && video.lastPathComponent.hasSuffix("]." + video.pathExtension)
        return video.deletingLastPathComponent().lastPathComponent == stem && (video.lastPathComponent == expectedVideo || editionVideo) ? .normalized : .needsNormalization
    }
    /// Returns the base shared by conventional multipart file names, only when
    /// a real suffix is present: `Film CD1`, `Film Disc 2`, `Film Part 3`, or
    /// Emby's canonical stacked-file form `Film-part1`.
    static func multiPartInfo(for base: URL) -> (base: URL, part: Int)? {
        let pattern = #"(?i)(?:\s+|[-_.]+)(?:cd|disc|disk|part)\s*\d+$"#
        let range = NSRange(base.lastPathComponent.startIndex..., in: base.lastPathComponent)
        guard let match = try? NSRegularExpression(pattern: pattern).firstMatch(in: base.lastPathComponent, range: range),
              let swiftRange = Range(match.range, in: base.lastPathComponent),
              let numberRange = Range(match.range(at: 0), in: base.lastPathComponent) else { return nil }
        let shared = String(base.lastPathComponent[..<swiftRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = String(base.lastPathComponent[numberRange])
        let number = suffix.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        guard !shared.isEmpty, let part = Int(number), part > 0 else { return nil }
        return (base.deletingLastPathComponent().appendingPathComponent(shared), part)
    }
    static func multiPartBase(for base: URL) -> URL? { multiPartInfo(for: base)?.base }
}

public struct EmbeddedMovieMetadata: Sendable {
    public let title: String?; public let creationDate: String?; public let artwork: Data?
    public init(title: String?, creationDate: String?, artwork: Data?) { self.title = title; self.creationDate = creationDate; self.artwork = artwork }
}
