import Foundation

public enum MovieSidecarState: String, Codable, Sendable { case complete, embeddedMetadataNeedsSidecars, bareNeedsTMDB, incompleteSidecars }
/// Layout is intentionally reported separately from metadata readiness: a film
/// may be complete but still need its files moved into a canonical movie folder.
public enum MovieFolderState: String, Codable, Sendable { case normalized, needsNormalization, metadataIncomplete, sharedMultiPart }
public struct MovieAuditItem: Codable, Sendable, Equatable {
    public let videoPath: String; public let nfoExists: Bool; public let artworkExists: Bool; public let embeddedTitle: String?; public let embeddedCreationDate: String?; public let hasEmbeddedArtwork: Bool; public let tmdbID: Int?; public let nfoTitle: String?; public let nfoYear: String?; public let nfoIsValid: Bool?; public let editionHint: String?; public let state: MovieSidecarState; public let folderState: MovieFolderState
    public init(videoPath: String, nfoExists: Bool, artworkExists: Bool, embeddedTitle: String?, embeddedCreationDate: String?, hasEmbeddedArtwork: Bool, tmdbID: Int?, nfoTitle: String?, nfoYear: String?, nfoIsValid: Bool?, editionHint: String?, state: MovieSidecarState, folderState: MovieFolderState = .metadataIncomplete) {
        self.videoPath = videoPath; self.nfoExists = nfoExists; self.artworkExists = artworkExists; self.embeddedTitle = embeddedTitle; self.embeddedCreationDate = embeddedCreationDate; self.hasEmbeddedArtwork = hasEmbeddedArtwork; self.tmdbID = tmdbID; self.nfoTitle = nfoTitle; self.nfoYear = nfoYear; self.nfoIsValid = nfoIsValid; self.editionHint = editionHint; self.state = state; self.folderState = folderState
    }
    public var isPreservationReady: Bool { state == .complete && nfoIsValid == true && tmdbID != nil && folderState == .needsNormalization }
}
public struct MovieLibraryHealthReport: Codable, Sendable, Equatable {
    public let items: [MovieAuditItem]; public let duplicateTMDBIDs: [String: [String]]; public let invalidNFOs: [String]
    public var summary: [String: Int] { Dictionary(grouping: items, by: { $0.state.rawValue }).mapValues(\.count) }
    public var folderSummary: [String: Int] { Dictionary(grouping: items, by: { $0.folderState.rawValue }).mapValues(\.count) }
}
public enum MovieLibraryAudit {
    public static func classify(nfoExists: Bool, artworkExists: Bool, info: EmbeddedMediaInfo) -> MovieSidecarState {
        if nfoExists && artworkExists { return .complete }
        if !nfoExists && !artworkExists && (info.title != nil || info.creationDate != nil || info.hasEmbeddedArtwork) { return .embeddedMetadataNeedsSidecars }
        if !nfoExists && !artworkExists { return .bareNeedsTMDB }
        return .incompleteSidecars
    }
    @MainActor public static func inspect(directory: URL) async -> [MovieAuditItem] {
        var items = [MovieAuditItem]()
        for video in MediaFileInspector.videoFiles(in: directory) {
            guard let info = try? await MediaFileInspector.inspect(video) else { continue }
            let base = video.deletingPathExtension()
            // CD/Disc/Part files may deliberately share a single movie NFO and
            // artwork. Treat that shared set as complete, never as three
            // separate embedded-metadata candidates.
            let sharedBase = multiPartBase(for: base)
            let sidecarBase = sharedBase ?? base
            let nfo = sidecarBase.appendingPathExtension("nfo"); let nfoExists = FileManager.default.fileExists(atPath: nfo.path); let parsed = nfoExists ? inspectNFO(nfo) : nil
            let image = primaryArtworkExists(for: sidecarBase)
            let state = classify(nfoExists: nfoExists, artworkExists: image, info: info)
            let folderState: MovieFolderState = sharedBase == nil ? folderState(for: video, nfo: parsed, sidecarState: state) : (state == .complete ? .sharedMultiPart : .metadataIncomplete)
            items.append(MovieAuditItem(videoPath: video.path, nfoExists: nfoExists, artworkExists: image, embeddedTitle: info.title, embeddedCreationDate: info.creationDate, hasEmbeddedArtwork: info.hasEmbeddedArtwork, tmdbID: parsed?.id, nfoTitle: parsed?.title, nfoYear: parsed?.year, nfoIsValid: nfoExists ? parsed?.valid ?? false : nil, editionHint: editionHint(video.lastPathComponent), state: state, folderState: folderState))
        }
        return items
    }
    /// Supports both MMM's stem artwork and tinyMediaManager's conventional
    /// `Title-poster.jpg` sidecar without treating fanart or logos as posters.
    static func primaryArtworkExists(for base: URL, fileManager: FileManager = .default) -> Bool {
        ["", "-poster"].contains { suffix in
            ["jpg", "jpeg", "png"].contains { fileManager.fileExists(atPath: URL(fileURLWithPath: base.path + suffix).appendingPathExtension($0).path) }
        }
    }
    @MainActor public static func health(directory: URL) async -> MovieLibraryHealthReport {
        let items = await inspect(directory: directory)
        let pairs = items.compactMap { item -> (String, String)? in item.tmdbID.map { (String($0), item.videoPath) } }
        let duplicates = Dictionary(grouping: pairs, by: \.0).compactMapValues { values in values.count > 1 ? values.map(\.1).sorted() : nil }
        return MovieLibraryHealthReport(items: items, duplicateTMDBIDs: duplicates, invalidNFOs: items.filter { $0.nfoIsValid == false }.map(\.videoPath).sorted())
    }
    private static func inspectNFO(_ url: URL) -> (id: Int?, title: String?, year: String?, valid: Bool) {
        guard let document = try? XMLDocument(contentsOf: url, options: []), document.rootElement()?.name == "movie" else { return (nil, nil, nil, false) }
        let identifier = (try? document.nodes(forXPath: "/movie/uniqueid[@type='tmdb']"))?.first?.stringValue.flatMap(Int.init)
        let title = (try? document.nodes(forXPath: "/movie/title"))?.first?.stringValue
        let year = (try? document.nodes(forXPath: "/movie/year"))?.first?.stringValue
        return (identifier, title?.trimmingCharacters(in: .whitespacesAndNewlines), year?.trimmingCharacters(in: .whitespacesAndNewlines), true)
    }
    private static func editionHint(_ name: String) -> String? {
        let lower = name.lowercased()
        for hint in ["director's cut", "directors cut", "extended", "remux", "3d", "commentary", "trailer", "featurette", "behind the scenes"] where lower.contains(hint) { return hint }
        return nil
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
    /// a real suffix is present: `Film CD1`, `Film Disc 2`, `Film Part 3`.
    static func multiPartBase(for base: URL) -> URL? {
        let pattern = #"(?i)\s+(?:cd|disc|disk|part)\s*\d+$"#
        let range = NSRange(base.lastPathComponent.startIndex..., in: base.lastPathComponent)
        guard let match = try? NSRegularExpression(pattern: pattern).firstMatch(in: base.lastPathComponent, range: range),
              let swiftRange = Range(match.range, in: base.lastPathComponent) else { return nil }
        let shared = String(base.lastPathComponent[..<swiftRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return shared.isEmpty ? nil : base.deletingLastPathComponent().appendingPathComponent(shared)
    }
}

public struct EmbeddedMovieMetadata: Sendable {
    public let title: String?; public let creationDate: String?; public let artwork: Data?
    public init(title: String?, creationDate: String?, artwork: Data?) { self.title = title; self.creationDate = creationDate; self.artwork = artwork }
}
