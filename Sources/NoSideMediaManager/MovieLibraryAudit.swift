import Foundation

public enum MovieSidecarState: String, Codable, Sendable { case complete, embeddedMetadataNeedsSidecars, bareNeedsTMDB, incompleteSidecars }
public struct MovieAuditItem: Codable, Sendable, Equatable {
    public let videoPath: String; public let nfoExists: Bool; public let artworkExists: Bool; public let embeddedTitle: String?; public let embeddedCreationDate: String?; public let hasEmbeddedArtwork: Bool; public let state: MovieSidecarState
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
            let base = video.deletingPathExtension(); let nfo = base.appendingPathExtension("nfo")
            let image = ["jpg", "jpeg", "png"].contains { FileManager.default.fileExists(atPath: base.appendingPathExtension($0).path) }
            items.append(MovieAuditItem(videoPath: video.path, nfoExists: FileManager.default.fileExists(atPath: nfo.path), artworkExists: image, embeddedTitle: info.title, embeddedCreationDate: info.creationDate, hasEmbeddedArtwork: info.hasEmbeddedArtwork, state: classify(nfoExists: FileManager.default.fileExists(atPath: nfo.path), artworkExists: image, info: info)))
        }
        return items
    }
}

public struct EmbeddedMovieMetadata: Sendable {
    public let title: String?; public let creationDate: String?; public let artwork: Data?
    public init(title: String?, creationDate: String?, artwork: Data?) { self.title = title; self.creationDate = creationDate; self.artwork = artwork }
}
