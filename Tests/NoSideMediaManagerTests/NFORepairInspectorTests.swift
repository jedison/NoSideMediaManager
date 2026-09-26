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
