import Foundation
import Testing
@testable import NoSideMediaManager

@Test func normalizationKeepsExtensionsAsEditionDistinction() throws {
    let root = URL(fileURLWithPath: "/Library/GBBO", isDirectory: true)
    let folder = root.appendingPathComponent("Season 01", isDirectory: true)
    let episode = TVEpisode(tvdbID: 10, seriesTVDBID: 184871, season: 1, number: 1, title: "Cakes")
    let plan = MappingPlanDocument(seriesTVDBID: 184871, libraryPath: root.path, entries: [
        .init(sourcePath: folder.appendingPathComponent("edition-a.m4v").path, canonicalEpisodeID: 10),
        .init(sourcePath: folder.appendingPathComponent("edition-b.mp4").path, canonicalEpisodeID: 10)
    ])

    let normalized = try plan.normalized(series: TVSeries(tvdbID: 184871, title: "The Great British Bake Off"), episodesByID: [10: episode])

    #expect(normalized.entries.compactMap(\.destinationPath).sorted() == [
        folder.appendingPathComponent("The Great British Bake Off - S01E01 - Cakes.m4v").path,
        folder.appendingPathComponent("The Great British Bake Off - S01E01 - Cakes.mp4").path
    ])
}

@Test func normalizationDisambiguatesOnlyExactDestinationCollisions() throws {
    let root = URL(fileURLWithPath: "/Library/GBBO", isDirectory: true)
    let folder = root.appendingPathComponent("Season 01", isDirectory: true)
    let episode = TVEpisode(tvdbID: 10, seriesTVDBID: 184871, season: 1, number: 1, title: "Cakes")
    let plan = MappingPlanDocument(seriesTVDBID: 184871, libraryPath: root.path, entries: [
        .init(sourcePath: folder.appendingPathComponent("a.mkv").path, canonicalEpisodeID: 10),
        .init(sourcePath: folder.appendingPathComponent("b.mkv").path, canonicalEpisodeID: 10)
    ])

    let normalized = try plan.normalized(series: TVSeries(tvdbID: 184871, title: "The Great British Bake Off"), episodesByID: [10: episode])

    #expect(normalized.entries.compactMap(\.destinationPath).sorted() == [
        folder.appendingPathComponent("The Great British Bake Off - S01E01 - Cakes [Edition 1].mkv").path,
        folder.appendingPathComponent("The Great British Bake Off - S01E01 - Cakes [Edition 2].mkv").path
    ])
}

@Test func offlineMetadataReconstructsCanonicalNFOBasics() throws {
    let plan = MappingPlanDocument(seriesTVDBID: 184871, libraryPath: "/Library/GBBO", entries: [
        .init(sourcePath: "/Library/GBBO/Season 01/old.m4v", canonicalEpisodeID: 10, destinationPath: "/Library/GBBO/Season 01/The Great British Bake Off - S01E01 - Cakes.m4v")
    ])
    let metadata = try plan.offlineMetadata()
    #expect(metadata.series.title == "The Great British Bake Off")
    #expect(metadata.episodes[10] == TVEpisode(tvdbID: 10, seriesTVDBID: 184871, season: 1, number: 1, title: "Cakes"))
}

@Test func reusableMappingPlanRetainsExplicitExclusionsAndReadsOlderPlans() throws {
    let plan = MappingPlanDocument(seriesTVDBID: 184871, libraryPath: "/Library/GBBO", entries: [
        .init(sourcePath: "/Library/GBBO/Season 01/duplicate.m4v", canonicalEpisodeID: nil, excluded: true)
    ])
    let restored = try JSONDecoder().decode(MappingPlanDocument.self, from: JSONEncoder().encode(plan))
    #expect(restored.entries.first?.excluded == true)
    let older = "{\"formatVersion\":1,\"seriesTVDBID\":184871,\"libraryPath\":\"/Library/GBBO\",\"entries\":[{\"sourcePath\":\"/Library/GBBO/Season 01/old.m4v\",\"canonicalEpisodeID\":10,\"downloadArtwork\":true}]}".data(using: .utf8)!
    #expect(try JSONDecoder().decode(MappingPlanDocument.self, from: older).entries.first?.excluded == nil)
}
