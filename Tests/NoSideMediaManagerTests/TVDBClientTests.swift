import Testing
import Foundation
@testable import NoSideMediaManager

@Test func tvdbArtworkPathsBecomeDownloadableURLs() {
    #expect(TVDBClient.artworkURL(from: "/banners/episodes/184871/1.jpg")?.absoluteString == "https://artworks.thetvdb.com/banners/episodes/184871/1.jpg")
    #expect(TVDBClient.artworkURL(from: "//images.example.test/episode.jpg")?.absoluteString == "https://images.example.test/episode.jpg")
    #expect(TVDBClient.artworkURL(from: "https://images.example.test/episode.jpg")?.absoluteString == "https://images.example.test/episode.jpg")
    #expect(TVDBClient.artworkURL(from: nil) == nil)
}

@Test func recordedTVDBFixturesExerciseOfficialEpisodeOrder() async throws {
    FixtureURLProtocol.responses = [
        "/v4/login": fixture("tvdb-login"),
        "/v4/series/184871/extended": fixture("tvdb-series-184871"),
        "/v4/series/184871/episodes/official/eng": fixture("tvdb-official-episodes-184871")
    ]
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FixtureURLProtocol.self]
    let client = TVDBClient(credentials: .init(apiKey: "fixture"), session: URLSession(configuration: configuration), baseURL: URL(string: "https://fixture.test/v4")!)
    let series = try await client.series(id: 184871)
    let episodes = try await client.episodes(forSeriesID: 184871)
    #expect(series.title == "The Great British Bake Off")
    #expect(series.network == "BBC One")
    #expect(series.seasons == [.init(number: 8, title: "Season Eight", overview: "Fixture season overview", aired: "2017-08-29", artworkURL: URL(string: "https://artworks.thetvdb.com/banners/seasons/184871-8.jpg"))])
    #expect(episodes.map(\.tvdbID) == [9001, 9002])
    #expect(episodes[0].artworkURL?.absoluteString == "https://artworks.thetvdb.com/banners/episodes/184871/9001.jpg")
}

private func fixture(_ name: String) -> Data {
    #if SWIFT_PACKAGE
    let bundle = Bundle.module
    #else
    let bundle = Bundle(for: FixtureBundleMarker.self)
    #endif
    let url = bundle.url(forResource: name, withExtension: "json")!
    return try! Data(contentsOf: url)
}

private final class FixtureBundleMarker {}

private final class FixtureURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses = [String: Data]()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        guard let data = Self.responses[path] else { client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable)); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
