import Foundation
import Testing
@testable import NoSideMediaManager

@Test func movieNFOIsKodiCompatibleAndUsesTMDBID() throws {
    let movie = Movie(tmdbID: 603, title: "The Matrix", overview: "Choice & consequence", releaseDate: "1999-03-30", runtimeMinutes: 136, rating: 8.2, genres: ["Science Fiction"])
    let text = String(decoding: try NFOWriter.movieData(movie), as: UTF8.self)
    #expect(text.contains("<movie>")); #expect(text.contains("<year>1999</year>")); #expect(text.contains("Choice &amp; consequence")); #expect(text.contains("<uniqueid type=\"tmdb\" default=\"true\">603</uniqueid>"))
}

@Test func movieAuditSeparatesEmbeddedAndBareVideos() {
    let embedded = EmbeddedMediaInfo(fileName: "Embedded.mp4", title: "Inside", creationDate: nil, durationSeconds: nil, width: nil, height: nil, audioLanguages: [], subtitleLanguages: [], hasEmbeddedArtwork: true)
    let bare = EmbeddedMediaInfo(fileName: "Bare.mkv", title: nil, creationDate: nil, durationSeconds: nil, width: nil, height: nil, audioLanguages: [], subtitleLanguages: [], hasEmbeddedArtwork: false)
    #expect(MovieLibraryAudit.classify(nfoExists: false, artworkExists: false, info: embedded) == .embeddedMetadataNeedsSidecars)
    #expect(MovieLibraryAudit.classify(nfoExists: false, artworkExists: false, info: bare) == .bareNeedsTMDB)
}

@Test func movieBundleHasRelativePathsAndCanApply() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let source = root.appendingPathComponent("Incoming/Matrix.mkv"); let destination = root.appendingPathComponent("The Matrix (1999).mkv")
    let bundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true); try Data("video".utf8).write(to: source)
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: bundle) }
    let manifest = try await PortableJobBundle.createMovie(at: bundle, libraryRoot: root, movie: Movie(tmdbID: 603, title: "The Matrix", releaseDate: "1999-03-30"), source: source, destination: destination, downloadArtwork: false)
    #expect(manifest.mediaKind == "movie"); #expect(manifest.metadataProvider == "tmdb"); #expect(manifest.moves == [.init(source: "Incoming/Matrix.mkv", destination: "The Matrix (1999).mkv")])
    try runMovieScript(bundle.appendingPathComponent("apply.sh"), ["--dry-run", root.path]); #expect(FileManager.default.fileExists(atPath: source.path))
    try runMovieScript(bundle.appendingPathComponent("apply.sh"), [root.path]); #expect(FileManager.default.fileExists(atPath: destination.path)); #expect(FileManager.default.fileExists(atPath: destination.deletingPathExtension().appendingPathExtension("nfo").path))
    try runMovieScript(bundle.appendingPathComponent("rollback.sh"), [root.path]); #expect(FileManager.default.fileExists(atPath: source.path))
}

@Test func batchMovieBundleFreezesEveryReviewedMovieAndFingerprint() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let first = root.appendingPathComponent("Incoming/one.mp4"); let second = root.appendingPathComponent("Incoming/two.mkv"); let bundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: first.deletingLastPathComponent(), withIntermediateDirectories: true); try Data("one".utf8).write(to: first); try Data("two".utf8).write(to: second)
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: bundle) }
    let firstMovie = Movie(tmdbID: 1, title: "One", releaseDate: "2001-01-01"); let secondMovie = Movie(tmdbID: 2, title: "Two", releaseDate: "2002-01-01")
    let manifest = try await PortableJobBundle.createMovies(at: bundle, libraryRoot: root, items: [MovieBundleItem(movie: firstMovie, source: first, destination: root.appendingPathComponent("One (2001).mp4"), downloadArtwork: false), MovieBundleItem(movie: secondMovie, source: second, destination: root.appendingPathComponent("Two (2002).mkv"), downloadArtwork: false)], downloadArtwork: false)
    #expect(manifest.moves.count == 2); #expect(manifest.generatedFiles.count == 2); #expect(manifest.sourceFingerprints.count == 2)
    try runMovieScript(bundle.appendingPathComponent("apply.sh"), [root.path]); #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("One (2001).mp4").path)); #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Two (2002).mkv").path))
}

@Test func movieFolderNormalizationIsExplicitAndKeepsCanonicalStem() throws {
    let plan = MoviePlanDocument(libraryPath: "/Library/Movies", entries: [.init(sourcePath: "/Library/Movies/Incoming/Matrix.mkv", tmdbID: 603)])
    let movie = Movie(tmdbID: 603, title: "The Matrix", releaseDate: "1999-03-30")
    let flat = try plan.normalized(movies: [603: movie]); let folders = try plan.normalized(movies: [603: movie], oneFolderPerMovie: true)
    #expect(flat.entries[0].destinationPath == "/Library/Movies/Incoming/The Matrix (1999).mkv")
    #expect(folders.entries[0].destinationPath == "/Library/Movies/Incoming/The Matrix (1999)/The Matrix (1999).mkv")
}

@Test func movieAuditAcceptsTinyMediaManagerPosterSidecar() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let base = root.appendingPathComponent("12 Monkeys")
    try Data("poster".utf8).write(to: URL(fileURLWithPath: base.path + "-poster").appendingPathExtension("jpg"))
    #expect(MovieLibraryAudit.primaryArtworkExists(for: base))
    let info = EmbeddedMediaInfo(fileName: "12 Monkeys.mp4", title: nil, creationDate: nil, durationSeconds: nil, width: nil, height: nil, audioLanguages: [], subtitleLanguages: [], hasEmbeddedArtwork: false)
    #expect(MovieLibraryAudit.classify(nfoExists: true, artworkExists: MovieLibraryAudit.primaryArtworkExists(for: base), info: info) == .complete)
}

@Test func sha256FingerprintModeIsOptIn() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true); let source = root.appendingPathComponent("movie.mp4"); let bundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); try Data("movie".utf8).write(to: source)
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: bundle) }
    let manifest = try await PortableJobBundle.createMovies(at: bundle, libraryRoot: root, items: [MovieBundleItem(movie: Movie(tmdbID: 1, title: "Movie"), source: source, destination: source, downloadArtwork: false)], downloadArtwork: false, fingerprintMode: .sha256)
    #expect(manifest.sourceFingerprints["movie.mp4"]?.hasPrefix("sha256:") == true)
}

private func runMovieScript(_ script: URL, _ arguments: [String]) throws { let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/bash"); process.arguments = [script.path] + arguments; try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 0) }
