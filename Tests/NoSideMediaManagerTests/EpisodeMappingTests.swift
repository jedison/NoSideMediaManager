import Foundation
import Testing
@testable import NoSideMediaManager

@Test func scannerAndPlannerUseExplicitEpisodeNumbers() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    FileManager.default.createFile(atPath: folder.appendingPathComponent("GBBO.S08E01.m4v").path, contents: Data())
    FileManager.default.createFile(atPath: folder.appendingPathComponent("notes.txt").path, contents: Data())
    let locals = try EpisodeFolderScanner.scan(directory: folder)
    let mapping = EpisodeMappingPlanner.propose(localFiles: locals, canonicalEpisodes: [TVEpisode(tvdbID: 1, seriesTVDBID: 184871, season: 8, number: 1, title: "Cake Week")])
    #expect(locals.count == 1)
    #expect(mapping.first?.canonical?.title == "Cake Week")
}

@Test func folderSeasonConflictRequiresManualMapping() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("Season 10 (BBC)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
    FileManager.default.createFile(atPath: folder.appendingPathComponent("GBBO.S07E01.m4v").path, contents: Data())
    let mapping = EpisodeMappingPlanner.propose(localFiles: try EpisodeFolderScanner.scan(directory: folder.deletingLastPathComponent()), canonicalEpisodes: [TVEpisode(tvdbID: 1, seriesTVDBID: 184871, season: 7, number: 1, title: "Wrong auto-match")])
    #expect(mapping.first?.local.folderSeason == 10)
    #expect(mapping.first?.canonical == nil)
}
