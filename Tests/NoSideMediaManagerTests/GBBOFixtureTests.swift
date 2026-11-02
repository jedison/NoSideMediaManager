import Foundation
import Testing
@testable import NoSideMediaManager

private struct GBBOFixture: Decodable { let source: String; let seasons: [String: Season]; struct Season: Decodable { let regular: [String]?; let extrasForReview: [String]?; let sidecars: [String]?; let representative: [String]? } }
private func gbboFixture() throws -> GBBOFixture { try JSONDecoder().decode(GBBOFixture.self, from: Data(contentsOf: Bundle.module.url(forResource: "gbbo-cp3-synthetic", withExtension: "json")!)) }

@Test func syntheticGBBOSeason11FixtureRetainsRegularsAndMakesExtrasReviewable() throws {
    let fixture = try gbboFixture(); let season = try #require(fixture.seasons["11"])
    #expect(fixture.source.hasPrefix("synthetic:")); #expect(season.regular?.count == 10); #expect(season.extrasForReview?.count == 7)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("Season 11"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for name in (season.regular ?? []) + (season.extrasForReview ?? []) + (season.sidecars ?? []) { FileManager.default.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data()) }
    let videos = MediaFileInspector.videoFiles(in: root); #expect(videos.count == 17)
    #expect(videos.filter { $0.lastPathComponent.contains("S11E") }.count == 17)
}
