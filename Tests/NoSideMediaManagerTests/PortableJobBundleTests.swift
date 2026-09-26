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

private func runScript(_ script: URL, _ arguments: [String]) throws {
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [script.path] + arguments
    try process.run(); process.waitUntilExit()
    #expect(process.terminationStatus == 0)
}
