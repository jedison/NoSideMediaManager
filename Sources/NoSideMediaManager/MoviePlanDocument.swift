import Foundation

public struct MoviePlanDocument: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable { public var sourcePath: String; public var tmdbID: Int?; public var destinationPath: String?; public var downloadArtwork: Bool; public init(sourcePath: String, tmdbID: Int?, destinationPath: String? = nil, downloadArtwork: Bool = true) { self.sourcePath = sourcePath; self.tmdbID = tmdbID; self.destinationPath = destinationPath; self.downloadArtwork = downloadArtwork } }
    public let formatVersion: Int; public let libraryPath: String; public var entries: [Entry]
    public init(libraryPath: String, entries: [Entry]) { self.formatVersion = 1; self.libraryPath = libraryPath; self.entries = entries }
    /// Creates a folder-normalisation proposal from existing, valid movie NFO
    /// metadata. The later preservation bundle moves sidecars as-is; it never
    /// replaces the NFO or downloads substitute artwork.
    public static func preservationProposal(library: URL, items: [MovieAuditItem]) -> MoviePlanDocument {
        let eligible = items.compactMap { item -> (item: MovieAuditItem, source: URL, folderStem: String)? in
            guard item.state == .complete, item.nfoIsValid == true,
                  let title = item.nfoTitle, !title.isEmpty,
                  let tmdbID = item.tmdbID else { return nil }
            let source = URL(fileURLWithPath: item.videoPath)
            let stem = safe(title) + (item.nfoYear.flatMap { $0.isEmpty ? nil : $0 }.map { " (\($0))" } ?? "")
            _ = tmdbID
            return (item, source, stem)
        }

        // Multiple files can legitimately represent the same movie: a low-res
        // copy, different subtitle treatment, or another retained edition.
        // They share a movie folder, but must have distinct stems so that each
        // video retains its own NFO and artwork/subtitle sidecars.
        var usedStemsByFolder = [String: Set<String>]()
        var entries = [Entry]()
        for (_, group) in Dictionary(grouping: eligible, by: { $0.item.tmdbID! }).sorted(by: { $0.key < $1.key }) {
            let ordered = group.sorted { lhs, rhs in
                let lhsCanonical = isCanonicalMovieCopy(lhs.source, folderStem: lhs.folderStem)
                let rhsCanonical = isCanonicalMovieCopy(rhs.source, folderStem: rhs.folderStem)
                if lhsCanonical != rhsCanonical { return lhsCanonical }
                return lhs.source.path.localizedStandardCompare(rhs.source.path) == .orderedAscending
            }
            for (index, candidate) in ordered.enumerated() {
                let folder = library.appendingPathComponent(candidate.folderStem, isDirectory: true)
                let folderKey = folder.standardizedFileURL.path.lowercased()
                var usedStems = usedStemsByFolder[folderKey] ?? []
                let sourceStem = safe(candidate.source.deletingPathExtension().lastPathComponent)
                let preferredStem = index == 0 ? candidate.folderStem : "\(candidate.folderStem) [\(sourceStem)]"
                let destinationStem = uniquePreservationStem(preferredStem, fallback: candidate.folderStem, used: &usedStems)
                usedStemsByFolder[folderKey] = usedStems
                let destination = folder.appendingPathComponent(destinationStem).appendingPathExtension(candidate.source.pathExtension)
                entries.append(Entry(sourcePath: candidate.source.path, tmdbID: candidate.item.tmdbID, destinationPath: destination.path, downloadArtwork: false))
            }
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
    private static func uniquePreservationStem(_ preferred: String, fallback: String, used: inout Set<String>) -> String {
        var candidate = preferred
        var number = 2
        while used.contains(candidate.lowercased()) {
            candidate = "\(fallback) [Edition \(number)]"
            number += 1
        }
        used.insert(candidate.lowercased())
        return candidate
    }
    private static func isCanonicalMovieCopy(_ source: URL, folderStem: String) -> Bool {
        let titleOnly = folderStem.replacingOccurrences(of: #" \(\d{4}\)$"#, with: "", options: .regularExpression)
        return source.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(titleOnly) == .orderedSame
    }
}
public enum MoviePlanError: LocalizedError { case unresolvedEntries; public var errorDescription: String? { "Every movie entry needs a reviewed TMDB ID." } }
