import Foundation
import Testing
@testable import NoSideMediaManager

@Test func seriesNFOEscapesXMLAndIncludesTVDBID() throws {
    let series = TVSeries(tvdbID: 123, title: "Salt & Pepper", overview: "A < B", firstAired: "2026-09-25", genres: ["Drama"])
    let text = String(decoding: try NFOWriter.seriesData(series), as: UTF8.self)
    #expect(text.contains("<tvshow>"))
    #expect(text.contains("Salt &amp; Pepper"))
    #expect(text.contains("A &lt; B"))
    #expect(text.contains("<uniqueid type=\"tvdb\" default=\"true\">123</uniqueid>"))
}

@Test func seasonNFOUsesCanonicalSeasonNumber() throws {
    let text = String(decoding: try NFOWriter.seasonData(number: 8), as: UTF8.self)
    #expect(text.contains("<seasonnumber>8</seasonnumber>"))
    #expect(text.contains("<title>Season 8</title>"))
}

@Test func importWritesSeriesAndEpisodeFiles() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = FixtureSource()
    let written = try await NFOImportService(source: source).importSeries(id: 123, into: directory)
    #expect(written.map(\.lastPathComponent).sorted() == ["S01E02.nfo", "tvshow.nfo"])
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("tvshow.nfo").path))
    #expect(String(decoding: try Data(contentsOf: directory.appendingPathComponent("S01E02.nfo")), as: UTF8.self).contains("Second episode"))
}

@Test func importDoesNotPartiallyWriteWhenANFOAlreadyExists() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    FileManager.default.createFile(atPath: directory.appendingPathComponent("S01E02.nfo").path, contents: Data())
    await #expect(throws: NFOImportError.fileAlreadyExists(directory.appendingPathComponent("S01E02.nfo"))) { try await NFOImportService(source: FixtureSource()).importSeries(id: 123, into: directory) }
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("tvshow.nfo").path))
}

private struct FixtureSource: TVMetadataSource {
    func searchSeries(named query: String) async throws -> [TVSeriesSearchResult] { [] }
    func series(id: Int) async throws -> TVSeries { TVSeries(tvdbID: id, title: "Fixture Show") }
    func episodes(forSeriesID id: Int) async throws -> [TVEpisode] { [TVEpisode(tvdbID: 456, seriesTVDBID: id, season: 1, number: 2, title: "Second episode")] }
}
