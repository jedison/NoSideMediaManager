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

@Test func tvAuditReportsLocalDuplicateEpisodeCandidates() {
    let first = LocalEpisodeFile(url: URL(fileURLWithPath: "/TV/Season 01/Show S01E01.mkv"), season: 1, episode: 1, folderSeason: 1)
    let second = LocalEpisodeFile(url: URL(fileURLWithPath: "/TV/Season 01/Show S01E01.mp4"), season: 1, episode: 1, folderSeason: 1)
    let conflict = LocalEpisodeFile(url: URL(fileURLWithPath: "/TV/Season 08/Show S07E02.mkv"), season: 7, episode: 2, folderSeason: 8)
    let audit = TVLibraryAudit.report(for: [first, second, conflict])
    #expect(audit.duplicates == [.init(season: 1, episode: 1, videoPaths: [first.url.path, second.url.path])])
    #expect(audit.folderSeasonConflicts == 1)
}

@Test func tvAuditExposesDuplicateCandidateFileSizes() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let first = folder.appendingPathComponent("Show S01E01.mkv")
    let second = folder.appendingPathComponent("Show S01E01.mp4")
    try Data(repeating: 0, count: 17).write(to: first)
    try Data(repeating: 0, count: 29).write(to: second)
    let audit = TVLibraryAudit.report(for: [
        .init(url: first, season: 1, episode: 1),
        .init(url: second, season: 1, episode: 1)
    ])
    #expect(audit.duplicates.count == 1)
    #expect(audit.items.map(\.fileSize).sorted { ($0 ?? -1) < ($1 ?? -1) } == [17, 29])
}

@Test func embeddedTitleCanProposeSameSeasonEpisodeButNotOverrideConflict() {
    let episode = TVEpisode(tvdbID: 44, seriesTVDBID: 1, season: 4, number: 1, title: "Cake")
    let titleMatched = LocalEpisodeFile(url: URL(fileURLWithPath: "/tmp/30 Series 4, Cake.m4v"), season: 4, episode: 0, folderSeason: 4, metadataTitle: "Series 4, Cake")
    let conflicting = LocalEpisodeFile(url: URL(fileURLWithPath: "/tmp/s05e01 - Cake Week.mp4"), season: 5, episode: 1, folderSeason: 8, metadataTitle: "Cake Week")
    let mappings = EpisodeMappingPlanner.propose(localFiles: [titleMatched, conflicting], canonicalEpisodes: [episode])
    #expect(mappings[0].canonical == episode)
    #expect(mappings[1].canonical == nil)
}

@Test func explicitFolderSeasonAdoptionMapsRegionalFilenameOrder() {
    let episode = TVEpisode(tvdbID: 88, seriesTVDBID: 1, season: 8, number: 1, title: "Cake Week")
    let local = LocalEpisodeFile(url: URL(fileURLWithPath: "/tmp/s05e01 - Cake Week.mp4"), season: 5, episode: 1, folderSeason: 8)
    let mapping = EpisodeMappingPlanner.propose(localFiles: [local], canonicalEpisodes: [episode], adoptFolderSeason: true)
    #expect(mapping.first?.canonical == episode)
}
