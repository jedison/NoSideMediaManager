import Foundation
import Testing
@testable import NoSideMediaManager

@Test func movieNFOIsKodiCompatibleAndUsesTMDBID() throws {
    let movie = Movie(tmdbID: 603, title: "The Matrix", overview: "Choice & consequence", releaseDate: "1999-03-30", runtimeMinutes: 136, rating: 8.2, genres: ["Science Fiction"])
    let text = String(decoding: try NFOWriter.movieData(movie), as: UTF8.self)
    #expect(text.contains("<movie>")); #expect(text.contains("<year>1999</year>")); #expect(text.contains("Choice &amp; consequence")); #expect(text.contains("<uniqueid type=\"tmdb\" default=\"true\">603</uniqueid>")); #expect(text.contains("<lockdata>true</lockdata>"))
}

@Test func embeddedMovieNFOUsesEmbyMetadataLock() throws {
    let text = String(decoding: try NFOWriter.embeddedMovieData(title: "Inside", creationDate: nil), as: UTF8.self)
    #expect(text.contains("<lockdata>true</lockdata>"))
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
    try runMovieScript(bundle.appendingPathComponent("apply.sh"), [root.path]); #expect(FileManager.default.fileExists(atPath: destination.path)); #expect(FileManager.default.fileExists(atPath: destination.deletingPathExtension().appendingPathExtension("nfo").path)); #expect(try String(contentsOf: destination.deletingPathExtension().appendingPathExtension("nfo")).contains("<lockdata>true</lockdata>"))
    try runMovieScript(bundle.appendingPathComponent("rollback.sh"), [root.path]); #expect(FileManager.default.fileExists(atPath: source.path))
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".noside-mmm-backups").appendingPathComponent(manifest.jobID).appendingPathComponent("rolled-back").path))
    try runMovieScript(bundle.appendingPathComponent("apply.sh"), [root.path])
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".noside-mmm-backups").appendingPathComponent(manifest.jobID).appendingPathComponent("rolled-back").path))
}

@Test func existingBundleOutputReceivesAnAutomaticRevision() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let source = root.appendingPathComponent("Inside.mp4")
    let requested = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("video".utf8).write(to: source)
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: requested); try? FileManager.default.removeItem(at: requested.deletingLastPathComponent().appendingPathComponent("\(requested.lastPathComponent)-v2")) }

    _ = try PortableJobBundle.createEmbeddedMovie(at: requested, libraryRoot: root, source: source, title: "Inside", creationDate: nil, artwork: nil)
    _ = try PortableJobBundle.createEmbeddedMovie(at: requested, libraryRoot: root, source: source, title: "Inside", creationDate: nil, artwork: nil)
    #expect(FileManager.default.fileExists(atPath: requested.appendingPathComponent("manifest.json").path))
    #expect(FileManager.default.fileExists(atPath: requested.deletingLastPathComponent().appendingPathComponent("\(requested.lastPathComponent)-v2/manifest.json").path))
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

@Test func preservationPlanAndBundleMoveExistingSidecarsWithoutReplacingThem() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let source = root.appendingPathComponent("12 Monkeys.mp4")
    let bundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("video".utf8).write(to: source)
    let base = source.deletingPathExtension()
    let originals = [".nfo": "rich nfo", "-poster.jpg": "poster", "-fanart.jpg": "fanart", "-clearlogo.png": "logo", ".en.srt": "subtitle"]
    for (suffix, contents) in originals { try Data(contents.utf8).write(to: URL(fileURLWithPath: base.path + suffix)) }
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: bundle) }
    let item = MovieAuditItem(videoPath: source.path, nfoExists: true, artworkExists: true, embeddedTitle: nil, embeddedCreationDate: nil, hasEmbeddedArtwork: false, tmdbID: 63, nfoTitle: "12 Monkeys", nfoYear: "1995", nfoIsValid: true, editionHint: nil, state: .complete)
    let plan = MoviePlanDocument.preservationProposal(library: root, items: [item])
    #expect(plan.entries[0].destinationPath == root.appendingPathComponent("12 Monkeys (1995)/12 Monkeys (1995).mp4").path)
    let manifest = try PortableJobBundle.createExistingMoviePreservation(at: bundle, plan: plan)
    #expect(manifest.metadataProvider == "existing-nfo")
    #expect(manifest.generatedFiles.isEmpty)
    try runMovieScript(bundle.appendingPathComponent("apply.sh"), ["--dry-run", root.path])
    #expect(FileManager.default.fileExists(atPath: source.path))
    try runMovieScript(bundle.appendingPathComponent("apply.sh"), [root.path])
    let destinationBase = root.appendingPathComponent("12 Monkeys (1995)/12 Monkeys (1995)")
    #expect(FileManager.default.fileExists(atPath: destinationBase.appendingPathExtension("mp4").path))
    for (suffix, contents) in originals { #expect(try String(contentsOf: URL(fileURLWithPath: destinationBase.path + suffix)) == contents) }
    try runMovieScript(bundle.appendingPathComponent("rollback.sh"), [root.path])
    #expect(FileManager.default.fileExists(atPath: source.path))
    for (suffix, contents) in originals { #expect(try String(contentsOf: URL(fileURLWithPath: base.path + suffix)) == contents) }
}

@Test func preservationProposalKeepsMultipleCopiesInOneMovieFolderWithSeparateNFOs() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let first = root.appendingPathComponent("Pride.mp4")
    let second = root.appendingPathComponent("Pride lowres.mp4")
    let bundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("primary video".utf8).write(to: first)
    try Data("low-resolution video".utf8).write(to: second)
    try Data("primary nfo".utf8).write(to: first.deletingPathExtension().appendingPathExtension("nfo"))
    try Data("low-resolution nfo".utf8).write(to: second.deletingPathExtension().appendingPathExtension("nfo"))
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: bundle) }

    let items = [first, second].map { video in
        MovieAuditItem(videoPath: video.path, nfoExists: true, artworkExists: true, embeddedTitle: nil, embeddedCreationDate: nil, hasEmbeddedArtwork: false, tmdbID: 86829, nfoTitle: "Pride", nfoYear: "2014", nfoIsValid: true, editionHint: nil, state: .complete)
    }
    let plan = MoviePlanDocument.preservationProposal(library: root, items: items)
    let destinations = try plan.entries.map { try #require($0.destinationPath) }
    #expect(destinations.count == 2)
    #expect(Set(destinations).count == 2)
    #expect(Set(destinations.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }) == [root.appendingPathComponent("Pride (2014)").path])
    #expect(destinations.contains(root.appendingPathComponent("Pride (2014)/Pride (2014).mp4").path))
    #expect(destinations.contains(root.appendingPathComponent("Pride (2014)/Pride (2014) [Pride lowres].mp4").path))

    _ = try PortableJobBundle.createExistingMoviePreservation(at: bundle, plan: plan)
    try runMovieScript(bundle.appendingPathComponent("apply.sh"), [root.path])
    let nfos = destinations.map { URL(fileURLWithPath: $0).deletingPathExtension().appendingPathExtension("nfo") }
    let nfoContents = try nfos.map { try String(contentsOf: $0) }
    #expect(nfoContents.sorted() == ["low-resolution nfo", "primary nfo"])
}

@Test func moviePreservationBundleDecodesMovieOnlyJSONWithoutTVMappingValidation() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let source = root.appendingPathComponent("20,000 Days on Earth (1080p HD).mp4")
    let destination = root.appendingPathComponent("20,000 Days on Earth (2014)/20,000 Days on Earth (2014).mp4")
    let planURL = root.appendingPathComponent("movie-preservation-plan.json")
    let bundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("video".utf8).write(to: source)
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: bundle) }

    let json: [String: Any] = [
        "formatVersion": 1,
        "libraryPath": root.path,
        "entries": [[
            "sourcePath": source.path,
            "destinationPath": destination.path,
            "tmdbID": 246400,
            "downloadArtwork": false
        ]]
    ]
    let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: planURL)
    #expect(!String(decoding: data, as: UTF8.self).contains("canonicalEpisodeID"))

    let plan = try MoviePlanDocument.read(from: planURL)
    let manifest = try PortableJobBundle.createExistingMoviePreservation(at: bundle, plan: plan)
    #expect(manifest.mediaKind == "movie")
    #expect(manifest.metadataProvider == "existing-nfo")
    #expect(manifest.moves == [.init(source: source.lastPathComponent, destination: "20,000 Days on Earth (2014)/20,000 Days on Earth (2014).mp4")])
    #expect(!manifest.notes.joined(separator: " ").contains("TVDB"))
}

@Test func moviePreservationDestinationCollisionIsNeverReportedAsTVMappingError() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let first = root.appendingPathComponent("Pride.mp4")
    let second = root.appendingPathComponent("Pride lowres.mp4")
    let destination = root.appendingPathComponent("Pride (2014)/Pride (2014).mp4")
    let bundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("one".utf8).write(to: first)
    try Data("two".utf8).write(to: second)
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: bundle) }

    let plan = MoviePlanDocument(libraryPath: root.path, entries: [
        .init(sourcePath: first.path, tmdbID: 86829, destinationPath: destination.path, downloadArtwork: false),
        .init(sourcePath: second.path, tmdbID: 86829, destinationPath: destination.path, downloadArtwork: false)
    ])
    var failure: Error?
    do {
        _ = try PortableJobBundle.createExistingMoviePreservation(at: bundle, plan: plan)
    } catch {
        failure = error
    }
    #expect(failure is MoviePreservationBundleError)
    #expect(failure?.localizedDescription.contains("duplicate destinationPath") == true)
    #expect(failure?.localizedDescription.contains("canonical TVDB episode") == false)
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

@Test func selectedMovieReadinessSeparatesFolderWorkFromMetadataWork() {
    let ready = MovieAuditItem(videoPath: "/Movies/Matrix.mkv", nfoExists: true, artworkExists: true, embeddedTitle: nil, embeddedCreationDate: nil, hasEmbeddedArtwork: false, tmdbID: 603, nfoTitle: "The Matrix", nfoYear: "1999", nfoIsValid: true, editionHint: nil, state: .complete, folderState: .needsNormalization)
    let alreadyNormal = MovieAuditItem(videoPath: "/Movies/The Matrix (1999)/The Matrix (1999).mkv", nfoExists: true, artworkExists: true, embeddedTitle: nil, embeddedCreationDate: nil, hasEmbeddedArtwork: false, tmdbID: 603, nfoTitle: "The Matrix", nfoYear: "1999", nfoIsValid: true, editionHint: nil, state: .complete, folderState: .normalized)
    #expect(ready.isPreservationReady)
    #expect(!alreadyNormal.isPreservationReady)
}

@Test func existingBracketedMovieEditionIsAlreadyFolderNormalized() {
    let video = URL(fileURLWithPath: "/Movies/Pride (2014)/Pride (2014) [Pride lowres].mp4")
    let state = MovieLibraryAudit.folderState(for: video, nfo: (id: 86829, title: "Pride", year: "2014", valid: true), sidecarState: .complete)
    #expect(state == .normalized)
}

@Test func multipartCDUsesOneSharedSidecarBase() {
    let base = URL(fileURLWithPath: "/Movies/Until the End of the World CD2")
    #expect(MovieLibraryAudit.multiPartBase(for: base)?.path == "/Movies/Until the End of the World")
    #expect(MovieLibraryAudit.multiPartBase(for: URL(fileURLWithPath: "/Movies/CD Collection")) == nil)
}

@Test func selectedEmbeddedMoviesFreezeAsOneSidecarPackage() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let first = root.appendingPathComponent("one.mp4"); let second = root.appendingPathComponent("two.mkv"); let bundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); try Data("one".utf8).write(to: first); try Data("two".utf8).write(to: second)
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: bundle) }
    let manifest = try PortableJobBundle.createEmbeddedMovies(at: bundle, libraryRoot: root, items: [.init(source: first, title: "One", creationDate: nil, artwork: nil), .init(source: second, title: "Two", creationDate: nil, artwork: nil)])
    #expect(manifest.generatedFiles == ["one.nfo", "two.nfo"])
    try runMovieScript(bundle.appendingPathComponent("apply.sh"), ["--dry-run", root.path])
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("one.nfo").path))
}

@Test func sha256FingerprintModeIsOptIn() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true); let source = root.appendingPathComponent("movie.mp4"); let bundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); try Data("movie".utf8).write(to: source)
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: bundle) }
    let manifest = try await PortableJobBundle.createMovies(at: bundle, libraryRoot: root, items: [MovieBundleItem(movie: Movie(tmdbID: 1, title: "Movie"), source: source, destination: source, downloadArtwork: false)], downloadArtwork: false, fingerprintMode: .sha256)
    #expect(manifest.sourceFingerprints["movie.mp4"]?.hasPrefix("sha256:") == true)
}

private func runMovieScript(_ script: URL, _ arguments: [String]) throws { let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/bash"); process.arguments = [script.path] + arguments; try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 0) }
