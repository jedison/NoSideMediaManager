import Foundation

public struct MoviePlanDocument: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable { public var sourcePath: String; public var tmdbID: Int?; public var destinationPath: String?; public var downloadArtwork: Bool; public init(sourcePath: String, tmdbID: Int?, destinationPath: String? = nil, downloadArtwork: Bool = true) { self.sourcePath = sourcePath; self.tmdbID = tmdbID; self.destinationPath = destinationPath; self.downloadArtwork = downloadArtwork } }
    public let formatVersion: Int; public let libraryPath: String; public var entries: [Entry]
    public init(libraryPath: String, entries: [Entry]) { self.formatVersion = 1; self.libraryPath = libraryPath; self.entries = entries }
    /// Creates a folder-normalisation proposal from existing, valid movie NFO
    /// metadata. The later preservation bundle moves sidecars as-is; it never
    /// replaces the NFO or downloads substitute artwork.
    public static func preservationProposal(library: URL, items: [MovieAuditItem]) -> MoviePlanDocument {
        let entries = items.compactMap { item -> Entry? in
            guard item.state == .complete, item.nfoIsValid == true,
                  let title = item.nfoTitle, !title.isEmpty,
                  let tmdbID = item.tmdbID else { return nil }
            let source = URL(fileURLWithPath: item.videoPath)
            let stem = safe(title) + (item.nfoYear.flatMap { $0.isEmpty ? nil : $0 }.map { " (\($0))" } ?? "")
            let destination = library.appendingPathComponent(stem, isDirectory: true).appendingPathComponent(stem).appendingPathExtension(source.pathExtension)
            return Entry(sourcePath: source.path, tmdbID: tmdbID, destinationPath: destination.path, downloadArtwork: false)
        }
        return MoviePlanDocument(libraryPath: library.path, entries: entries)
    }
    /// Keeps existing folders by default. `oneFolderPerMovie` is an explicit,
    /// opt-in library-layout normalisation: movie, NFO, poster and subtitle
    /// companions then move beneath `Title (Year)/` as one transaction.
    public func normalized(movies: [Int: Movie], oneFolderPerMovie: Bool = false) throws -> MoviePlanDocument {
        guard entries.allSatisfy({ $0.tmdbID != nil }) else { throw MoviePlanError.unresolvedEntries }
        var result = self
        for index in result.entries.indices {
            guard let id = result.entries[index].tmdbID, let movie = movies[id] else { throw MoviePlanError.unresolvedEntries }
            let source = URL(fileURLWithPath: result.entries[index].sourcePath)
            let stem = Self.safe(movie.title) + (movie.year.map { " (\($0))" } ?? "")
            let parent = source.deletingLastPathComponent()
            let destination = oneFolderPerMovie ? parent.appendingPathComponent(stem, isDirectory: true).appendingPathComponent(stem) : parent.appendingPathComponent(stem)
            result.entries[index].destinationPath = destination.appendingPathExtension(source.pathExtension).path
        }
        return result
    }
    public func write(to url: URL) throws { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(self).write(to: url, options: .atomic) }
    public static func read(from url: URL) throws -> MoviePlanDocument { try JSONDecoder().decode(MoviePlanDocument.self, from: Data(contentsOf: url)) }
    static func safe(_ value: String) -> String { value.components(separatedBy: CharacterSet(charactersIn: "/:\\?*\"<>|")).joined(separator: " - ") }
}
public enum MoviePlanError: LocalizedError { case unresolvedEntries; public var errorDescription: String? { "Every movie entry needs a reviewed TMDB ID." } }
