import Foundation

public struct MoviePlanDocument: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public var sourcePath: String; public var tmdbID: Int?; public var destinationPath: String?; public var downloadArtwork: Bool
        /// Shared NFO/artwork stem for a CD/Disc/Part set.  Kept optional so
        /// existing editable preservation JSON remains compatible.
        public var sharedSidecarBasePath: String?
        public init(sourcePath: String, tmdbID: Int?, destinationPath: String? = nil, downloadArtwork: Bool = true, sharedSidecarBasePath: String? = nil) { self.sourcePath = sourcePath; self.tmdbID = tmdbID; self.destinationPath = destinationPath; self.downloadArtwork = downloadArtwork; self.sharedSidecarBasePath = sharedSidecarBasePath }
    }
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
            guard item.folderState != .sharedMultiPart else { return nil }
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
        // A CD/Disc/Part set shares one NFO and artwork set.  Its parts are
        // deliberately named independently, while those shared sidecars are
        // moved exactly once by the preservation bundle.
        let multipart = items.compactMap { item -> (MovieAuditItem, URL, URL, Int, String)? in
            guard item.isMultiPartPreservationReady,
                  let title = item.nfoTitle, !title.isEmpty,
                  let info = MovieLibraryAudit.multiPartInfo(for: URL(fileURLWithPath: item.videoPath).deletingPathExtension()) else { return nil }
            let stem = safe(title) + (item.nfoYear.flatMap { $0.isEmpty ? nil : $0 }.map { " (\($0))" } ?? "")
            return (item, URL(fileURLWithPath: item.videoPath), info.base, info.part, stem)
        }
        for (_, group) in Dictionary(grouping: multipart, by: { "\($0.0.tmdbID!)|\($0.2.standardizedFileURL.path.lowercased())" }).sorted(by: { $0.key < $1.key }) {
            guard let first = group.first else { continue }
            for candidate in group.sorted(by: { $0.3 < $1.3 }) {
                let folder = library.appendingPathComponent(candidate.4, isDirectory: true)
                // Emby's documented split-movie stacking marker is `-part#`.
                let destination = folder.appendingPathComponent("\(candidate.4)-part\(candidate.3)").appendingPathExtension(candidate.1.pathExtension)
                entries.append(Entry(sourcePath: candidate.1.path, tmdbID: candidate.0.tmdbID, destinationPath: destination.path, downloadArtwork: false, sharedSidecarBasePath: first.2.path))
            }
        }
        return MoviePlanDocument(libraryPath: library.path, entries: entries.sorted { $0.sourcePath.localizedStandardCompare($1.sourcePath) == .orderedAscending })
    }
    /// Multipart packages are only safe when every detected part of each
    /// selected movie is included. Otherwise applying a package could split a
    /// film into different folders, so callers must reject partial groups.
    public static func isCompleteMultiPartSelection(_ selected: [MovieAuditItem], from allItems: [MovieAuditItem]) -> Bool {
        let requested = Set(selected.map(\.videoPath))
        let groupKeys = Set(selected.compactMap { item -> String? in
            guard item.isMultiPartPreservationReady else { return nil }
            return MovieLibraryAudit.multiPartInfo(for: URL(fileURLWithPath: item.videoPath).deletingPathExtension())?.base.standardizedFileURL.path
        })
        guard !groupKeys.isEmpty else { return false }
        for key in groupKeys {
            let members = allItems.filter { item in
                guard item.isMultiPartPreservationReady,
                      let base = MovieLibraryAudit.multiPartInfo(for: URL(fileURLWithPath: item.videoPath).deletingPathExtension())?.base.standardizedFileURL.path else { return false }
                return base == key
            }
            guard !members.isEmpty, members.allSatisfy({ requested.contains($0.videoPath) }) else { return false }
        }
        return selected.allSatisfy { !$0.isMultiPartPreservationReady || requested.contains($0.videoPath) }
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
