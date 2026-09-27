import Foundation

public enum MovieSidecarState: String, Codable, Sendable { case complete, embeddedMetadataNeedsSidecars, bareNeedsTMDB, incompleteSidecars }
public struct MovieAuditItem: Codable, Sendable, Equatable {
    public let videoPath: String; public let nfoExists: Bool; public let artworkExists: Bool; public let embeddedTitle: String?; public let embeddedCreationDate: String?; public let hasEmbeddedArtwork: Bool; public let tmdbID: Int?; public let nfoIsValid: Bool?; public let editionHint: String?; public let state: MovieSidecarState
}
public struct MovieLibraryHealthReport: Codable, Sendable, Equatable {
    public let items: [MovieAuditItem]; public let duplicateTMDBIDs: [String: [String]]; public let invalidNFOs: [String]
    public var summary: [String: Int] { Dictionary(grouping: items, by: { $0.state.rawValue }).mapValues(\.count) }
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
            let base = video.deletingPathExtension(); let nfo = base.appendingPathExtension("nfo"); let nfoExists = FileManager.default.fileExists(atPath: nfo.path); let parsed = nfoExists ? inspectNFO(nfo) : nil
            let image = ["jpg", "jpeg", "png"].contains { FileManager.default.fileExists(atPath: base.appendingPathExtension($0).path) }
            items.append(MovieAuditItem(videoPath: video.path, nfoExists: nfoExists, artworkExists: image, embeddedTitle: info.title, embeddedCreationDate: info.creationDate, hasEmbeddedArtwork: info.hasEmbeddedArtwork, tmdbID: parsed?.id, nfoIsValid: nfoExists ? parsed?.valid ?? false : nil, editionHint: editionHint(video.lastPathComponent), state: classify(nfoExists: nfoExists, artworkExists: image, info: info)))
        }
        return items
    }
    @MainActor public static func health(directory: URL) async -> MovieLibraryHealthReport {
        let items = await inspect(directory: directory)
        let pairs = items.compactMap { item -> (String, String)? in item.tmdbID.map { (String($0), item.videoPath) } }
        let duplicates = Dictionary(grouping: pairs, by: \.0).compactMapValues { values in values.count > 1 ? values.map(\.1).sorted() : nil }
        return MovieLibraryHealthReport(items: items, duplicateTMDBIDs: duplicates, invalidNFOs: items.filter { $0.nfoIsValid == false }.map(\.videoPath).sorted())
    }
    private static func inspectNFO(_ url: URL) -> (id: Int?, valid: Bool) {
        guard let document = try? XMLDocument(contentsOf: url, options: []), document.rootElement()?.name == "movie" else { return (nil, false) }
        let identifier = (try? document.nodes(forXPath: "/movie/uniqueid[@type='tmdb']"))?.first?.stringValue.flatMap(Int.init)
        return (identifier, true)
    }
    private static func editionHint(_ name: String) -> String? {
        let lower = name.lowercased()
        for hint in ["director's cut", "directors cut", "extended", "remux", "3d", "commentary", "trailer", "featurette", "behind the scenes"] where lower.contains(hint) { return hint }
        return nil
    }
}

public struct EmbeddedMovieMetadata: Sendable {
    public let title: String?; public let creationDate: String?; public let artwork: Data?
    public init(title: String?, creationDate: String?, artwork: Data?) { self.title = title; self.creationDate = creationDate; self.artwork = artwork }
}
