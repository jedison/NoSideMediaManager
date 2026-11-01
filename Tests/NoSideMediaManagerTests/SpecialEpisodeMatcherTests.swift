import Foundation
import Testing
@testable import NoSideMediaManager

private func local(_ name: String, _ episode: Int, title: String? = nil) -> LocalEpisodeFile {
    .init(url: URL(fileURLWithPath: "/GBBO/Season 11/\(name).m4v"), season: 11, episode: episode, folderSeason: 11, metadataTitle: title)
}
private func special(_ id: Int, _ number: Int, _ title: String) -> TVEpisode {
    .init(tvdbID: id, seriesTVDBID: 184871, season: 0, number: number, title: title)
}

@Test func specialMatcherFindsChristmasNewYearAndCharityTitles() {
    let specials = [special(1, 1, "Christmas Special"), special(2, 2, "New Year's Bake Off"), special(3, 3, "Stand Up To Cancer")]
    let proposals = SpecialEpisodeMatcher.propose(unmatched: [local("GBBO S11E11 Christmas Special", 11), local("GBBO S11E12 New Years Bake Off", 12), local("GBBO S11E13 Charity", 13, title: "Stand Up to Cancer")], canonicalEpisodes: specials)
    #expect(proposals.map { $0.canonical?.tvdbID } == [1, 2, 3])
    #expect(proposals.allSatisfy { !$0.isAmbiguous })
}

@Test func specialMatcherLeavesAmbiguousAndDuplicateTargetsManual() {
    let specials = [special(1, 1, "Christmas Special"), special(2, 2, "Christmas Special")]
    let ambiguous = SpecialEpisodeMatcher.propose(unmatched: [local("GBBO S11E11 Christmas Special", 11)], canonicalEpisodes: specials)
    #expect(ambiguous.first?.isAmbiguous == true)
    let duplicate = SpecialEpisodeMatcher.propose(unmatched: [local("Christmas Special S11E11", 11), local("Christmas Special S11E12", 12)], canonicalEpisodes: [special(1, 1, "Christmas Special")])
    #expect(duplicate.allSatisfy { $0.isAmbiguous })
    #expect(SpecialEpisodeMatcher.bulkApprovals(proposals: duplicate, existing: [:]).isEmpty)
}

@Test func bulkSpecialApprovalPreservesExistingRegularMappings() {
    let regular = local("GBBO S11E01", 1)
    let candidate = local("GBBO S11E11 Christmas Special", 11)
    let existing = [regular.url: 101]
    let proposals = SpecialEpisodeMatcher.propose(unmatched: [candidate], canonicalEpisodes: [special(1, 1, "Christmas Special")])
    let approved = SpecialEpisodeMatcher.bulkApprovals(proposals: proposals, existing: existing)
    #expect(existing[regular.url] == 101)
    #expect(approved == [candidate.url: 1])
}
