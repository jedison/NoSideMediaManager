import Foundation
import Testing
@testable import NoSideMediaManager

@Test func portableBundleContainsOnlyRelativeLibraryInstructions() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let source = root.appendingPathComponent("Season 01/Old Name S01E01.mkv")
    let destination = root.appendingPathComponent("Season 08/New Name S08E01.mkv")
    let bundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: source.path, contents: Data())
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: bundle) }

    let series = TVSeries(tvdbID: 407318, title: "The Great British Bake Off")
    let episode = TVEpisode(tvdbID: 101, seriesTVDBID: 407318, season: 8, number: 1, title: "Cake")
    let manifest = try await PortableJobBundle.create(at: bundle, showRoot: root, series: series, mappings: [ApprovedEpisodeMapping(local: LocalEpisodeFile(url: source, season: 1, episode: 1), canonical: episode)], destinations: [source: destination], downloadArtwork: false)

    #expect(manifest.moves == [.init(source: "Season 01/Old Name S01E01.mkv", destination: "Season 08/New Name S08E01.mkv")])
    #expect(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("generated/Season 08/New Name S08E01.nfo").path))
    #expect(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("generated/Season 08/season.nfo").path))
    let apply = try String(contentsOf: bundle.appendingPathComponent("apply.sh"))
    #expect(apply.contains("--dry-run"))
    #expect(apply.contains(".noside-mmm-backups"))
    #expect(apply.contains("move_video 'Season 01/Old Name S01E01.mkv' 'Season 08/New Name S08E01.mkv'"))
    #expect(!apply.contains(root.path))
    #expect(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("rollback.sh").path))
    #expect(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("manifest.json").path))
    #expect(manifest.notes.isEmpty)
    for script in ["apply.sh", "rollback.sh"] {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-n", bundle.appendingPathComponent(script).path]
        try process.run(); process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}

@Test func portableBundleAppliesAndRollsBackOnATargetRoot() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let source = root.appendingPathComponent("Incoming/GBBO S01E01.mkv")
    let destination = root.appendingPathComponent("Season 08/GBBO S08E01.mkv")
    let bundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("video".utf8).write(to: source)
    try Data("old nfo".utf8).write(to: source.deletingPathExtension().appendingPathExtension("nfo"))
    try Data("subtitle".utf8).write(to: source.deletingPathExtension().appendingPathExtension("en.srt"))
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: bundle) }

    let series = TVSeries(tvdbID: 407318, title: "The Great British Bake Off")
    let episode = TVEpisode(tvdbID: 101, seriesTVDBID: 407318, season: 8, number: 1, title: "Cake")
    _ = try await PortableJobBundle.create(at: bundle, showRoot: root, series: series, mappings: [ApprovedEpisodeMapping(local: LocalEpisodeFile(url: source, season: 1, episode: 1), canonical: episode)], destinations: [source: destination], downloadArtwork: false)

    try runScript(bundle.appendingPathComponent("apply.sh"), ["--dry-run", root.path])
    #expect(FileManager.default.fileExists(atPath: source.path))
    try runScript(bundle.appendingPathComponent("apply.sh"), [root.path])
    #expect(FileManager.default.fileExists(atPath: destination.path))
    #expect(FileManager.default.fileExists(atPath: destination.deletingPathExtension().appendingPathExtension("nfo").path))
    #expect(FileManager.default.fileExists(atPath: destination.deletingPathExtension().appendingPathExtension("en.srt").path))
    try runScript(bundle.appendingPathComponent("rollback.sh"), [root.path])
    #expect(FileManager.default.fileExists(atPath: source.path))
    #expect(try String(contentsOf: source.deletingPathExtension().appendingPathExtension("nfo")) == "old nfo")
    #expect(FileManager.default.fileExists(atPath: source.deletingPathExtension().appendingPathExtension("en.srt").path))
    #expect(!FileManager.default.fileExists(atPath: destination.path))
}

@Test func portableBundleSharesSidecarsForSameEpisodeDifferentExtensions() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let first = root.appendingPathComponent("Season 01/first.m4v")
    let second = root.appendingPathComponent("Season 01/second.mp4")
    let bundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: first.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: first.path, contents: Data())
    FileManager.default.createFile(atPath: second.path, contents: Data())
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: bundle) }

    let series = TVSeries(tvdbID: 184871, title: "The Great British Bake Off")
    let episode = TVEpisode(tvdbID: 101, seriesTVDBID: 184871, season: 1, number: 1, title: "Cakes")
    let destinationStem = root.appendingPathComponent("Season 01/The Great British Bake Off - S01E01 - Cakes")
    let manifest = try await PortableJobBundle.create(
        at: bundle,
        showRoot: root,
        series: series,
        mappings: [
            ApprovedEpisodeMapping(local: LocalEpisodeFile(url: first, season: 1, episode: 1), canonical: episode),
            ApprovedEpisodeMapping(local: LocalEpisodeFile(url: second, season: 1, episode: 1), canonical: episode)
        ],
        destinations: [first: destinationStem.appendingPathExtension("m4v"), second: destinationStem.appendingPathExtension("mp4")],
        downloadArtwork: false
    )

    #expect(manifest.generatedFiles.filter { $0.hasSuffix("S01E01 - Cakes.nfo") }.count == 1)
    #expect(manifest.unavailableArtwork.isEmpty)
}

@Test func portableBundleQuotesApostrophesForShellScripts() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let source = root.appendingPathComponent("Season 01/Baker's Choice.mkv")
    let destination = root.appendingPathComponent("Season 01/Baker's Choice S01E01.mkv")
    let bundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: source.path, contents: Data())
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: bundle) }

    let series = TVSeries(tvdbID: 184871, title: "The Great British Bake Off")
    let episode = TVEpisode(tvdbID: 101, seriesTVDBID: 184871, season: 1, number: 1, title: "Baker's Choice")
    _ = try await PortableJobBundle.create(at: bundle, showRoot: root, series: series, mappings: [ApprovedEpisodeMapping(local: LocalEpisodeFile(url: source, season: 1, episode: 1), canonical: episode)], destinations: [source: destination], downloadArtwork: false)

    for script in ["apply.sh", "rollback.sh"] {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-n", bundle.appendingPathComponent(script).path]
        try process.run(); process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}

@Test func portableBundleWritesDominantSeasonNFOWhenFolderIncludesASpecial() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let regular = root.appendingPathComponent("Season 07/regular.mkv")
    let special = root.appendingPathComponent("Season 07/special.mkv")
    let bundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: regular.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: regular.path, contents: Data())
    FileManager.default.createFile(atPath: special.path, contents: Data())
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: bundle) }

    let series = TVSeries(tvdbID: 184871, title: "The Great British Bake Off")
    let regularEpisode = TVEpisode(tvdbID: 101, seriesTVDBID: 184871, season: 7, number: 1, title: "Cake")
    let specialEpisode = TVEpisode(tvdbID: 102, seriesTVDBID: 184871, season: 0, number: 55, title: "Class of 2015")
    let manifest = try await PortableJobBundle.create(at: bundle, showRoot: root, series: series, mappings: [
        ApprovedEpisodeMapping(local: LocalEpisodeFile(url: regular, season: 7, episode: 1), canonical: regularEpisode),
        ApprovedEpisodeMapping(local: LocalEpisodeFile(url: special, season: 7, episode: 2), canonical: specialEpisode)
    ], downloadArtwork: false)

    #expect(manifest.generatedFiles.contains("Season 07/season.nfo"))
    #expect(try String(contentsOf: bundle.appendingPathComponent("generated/Season 07/season.nfo")).contains("<seasonnumber>7</seasonnumber>"))
}

private func runScript(_ script: URL, _ arguments: [String]) throws {
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [script.path] + arguments
    try process.run(); process.waitUntilExit()
    #expect(process.terminationStatus == 0)
}

@Test func mediaInspectorFindsVideoWithoutSxxEyyFilename() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let m4v = root.appendingPathComponent("17 Series 3, Episode 1.m4v")
    FileManager.default.createFile(atPath: m4v.path, contents: Data())
    FileManager.default.createFile(atPath: root.appendingPathComponent("ignored.nfo").path, contents: Data())
    let files = MediaFileInspector.videoFiles(in: root)
    #expect(files.map(\.lastPathComponent) == [m4v.lastPathComponent])
}
