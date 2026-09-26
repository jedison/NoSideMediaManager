import Testing
@testable import NoSideMediaManager

@Test func tvdbArtworkPathsBecomeDownloadableURLs() {
    #expect(TVDBClient.artworkURL(from: "/banners/episodes/184871/1.jpg")?.absoluteString == "https://artworks.thetvdb.com/banners/episodes/184871/1.jpg")
    #expect(TVDBClient.artworkURL(from: "//images.example.test/episode.jpg")?.absoluteString == "https://images.example.test/episode.jpg")
    #expect(TVDBClient.artworkURL(from: "https://images.example.test/episode.jpg")?.absoluteString == "https://images.example.test/episode.jpg")
    #expect(TVDBClient.artworkURL(from: nil) == nil)
}
