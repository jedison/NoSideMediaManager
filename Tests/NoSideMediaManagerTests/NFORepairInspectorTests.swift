import Foundation
import Testing
@testable import NoSideMediaManager

@Test func inspectorReportsOnlyChangedNFOFields() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("nfo")
    defer { try? FileManager.default.removeItem(at: file) }
    try "<episodedetails><title>Wrong</title><season>8</season><episode>1</episode></episodedetails>".data(using: .utf8)!.write(to: file)
    let differences = try NFORepairInspector.differences(at: file, comparedTo: TVEpisode(tvdbID: 1, seriesTVDBID: 2, season: 8, number: 1, title: "Cake Week"))
    #expect(differences.contains(where: { $0.field == "title" }))
    #expect(!differences.contains(where: { $0.field == "season" }))
}

@Test func fieldLevelMergeKeepsUncheckedExistingValues() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("nfo")
    defer { try? FileManager.default.removeItem(at: file) }
    try "<episodedetails><title>Local title</title><plot>Local plot</plot><season>8</season><episode>1</episode></episodedetails>".data(using: .utf8)!.write(to: file)
    let episode = TVEpisode(tvdbID: 1, seriesTVDBID: 2, season: 8, number: 1, title: "TVDB title", overview: "TVDB plot")
    let merged = try NFORepairInspector.mergedEpisodeData(existingNFO: file, canonical: episode, replacing: ["title"])
    let xml = try XMLDocument(data: merged, options: [])
    #expect(try xml.nodes(forXPath: "//title").first?.stringValue == "TVDB title")
    #expect(try xml.nodes(forXPath: "//plot").first?.stringValue == "Local plot")
}
