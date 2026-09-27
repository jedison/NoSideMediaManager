import Foundation

public struct MoviePlanDocument: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable { public var sourcePath: String; public var tmdbID: Int?; public var destinationPath: String?; public var downloadArtwork: Bool; public init(sourcePath: String, tmdbID: Int?, destinationPath: String? = nil, downloadArtwork: Bool = true) { self.sourcePath = sourcePath; self.tmdbID = tmdbID; self.destinationPath = destinationPath; self.downloadArtwork = downloadArtwork } }
    public let formatVersion: Int; public let libraryPath: String; public var entries: [Entry]
    public init(libraryPath: String, entries: [Entry]) { self.formatVersion = 1; self.libraryPath = libraryPath; self.entries = entries }
    public func normalized(movies: [Int: Movie]) throws -> MoviePlanDocument {
        guard entries.allSatisfy({ $0.tmdbID != nil }) else { throw MoviePlanError.unresolvedEntries }
        var result = self
        for index in result.entries.indices { guard let id = result.entries[index].tmdbID, let movie = movies[id] else { throw MoviePlanError.unresolvedEntries }; let source = URL(fileURLWithPath: result.entries[index].sourcePath); result.entries[index].destinationPath = source.deletingLastPathComponent().appendingPathComponent(Self.safe(movie.title) + (movie.year.map { " (\($0))" } ?? "")).appendingPathExtension(source.pathExtension).path }
        return result
    }
    public func write(to url: URL) throws { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(self).write(to: url, options: .atomic) }
    public static func read(from url: URL) throws -> MoviePlanDocument { try JSONDecoder().decode(MoviePlanDocument.self, from: Data(contentsOf: url)) }
    private static func safe(_ value: String) -> String { value.components(separatedBy: CharacterSet(charactersIn: "/:\\?*\"<>|")).joined(separator: " - ") }
}
public enum MoviePlanError: LocalizedError { case unresolvedEntries; public var errorDescription: String? { "Every movie entry needs a reviewed TMDB ID." } }
