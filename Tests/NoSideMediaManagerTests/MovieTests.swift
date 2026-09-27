import Foundation
import Testing
@testable import NoSideMediaManager

@Test func movieNFOIsKodiCompatibleAndUsesTMDBID() throws {
    let movie = Movie(tmdbID: 603, title: "The Matrix", overview: "Choice & consequence", releaseDate: "1999-03-30", runtimeMinutes: 136, rating: 8.2, genres: ["Science Fiction"])
    let text = String(decoding: try NFOWriter.movieData(movie), as: UTF8.self)
    #expect(text.contains("<movie>")); #expect(text.contains("<year>1999</year>")); #expect(text.contains("Choice &amp; consequence")); #expect(text.contains("<uniqueid type=\"tmdb\" default=\"true\">603</uniqueid>"))
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

private func runMovieScript(_ script: URL, _ arguments: [String]) throws { let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/bash"); process.arguments = [script.path] + arguments; try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 0) }
