import Foundation
import Testing
@testable import NoSideMediaManager

@Test func subtitleDiscoveryRetainsOnlyExactEpisodeLanguageAndSupportedFormat() {
    let episode = TVEpisode(tvdbID: 1, seriesTVDBID: 2, season: 11, number: 3, title: "Bread Week")
    let request = SubtitleSearchRequest(episode: episode)
    let candidates = [SubtitleCandidate(id: "en", provider: "mock", language: "en", episodeTitle: "Bread Week", season: 11, episode: 3, format: "srt"), SubtitleCandidate(id: "wrong", provider: "mock", language: "en", episodeTitle: "Bread Week", season: 11, episode: 4, format: "srt"), SubtitleCandidate(id: "bad", provider: "mock", language: "fr", episodeTitle: "Bread Week", season: 11, episode: 3, format: "zip")]
    #expect(SubtitleDiscovery.reviewedCandidates(candidates, for: request).map(\.id) == ["en"])
}
