import Foundation
import Testing
@testable import NoSideMediaManager

private final class OpenSubtitleProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }; override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { let path = request.url!.path; let response: (Int, Data) = path.contains("unauthorized") ? (401, Data()) : path.contains("limited") ? (429, Data()) : (200, Data(#"{"data":[{"attributes":{"language":"en","format":"srt","release":"WEB","files":[{"file_id":7}],"feature_details":{"episode_name":"Cake Week","season_number":11,"episode_number":1}}},{"attributes":{"language":"fr","format":"srt","files":[{"file_id":8}],"feature_details":{"episode_name":"Cake Week","season_number":11,"episode_number":1}}}]}"#.utf8)); client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: response.0, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed); client?.urlProtocol(self, didLoad: response.1); client?.urlProtocolDidFinishLoading(self) }
    override func stopLoading() {}
}
@Test func openSubtitlesSearchParsesEnglishAndFrenchFixtureCandidates() async throws {
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [OpenSubtitleProtocol.self]
    let episode = TVEpisode(tvdbID: 1, seriesTVDBID: 2, season: 11, number: 1, title: "Cake Week")
    let results = try await OpenSubtitlesClient(apiKey: "fixture", session: URLSession(configuration: config), baseURL: URL(string: "https://fixture.test")!).search(.init(episode: episode, seriesTitle: "Bake Off"))
    #expect(results.map(\.language) == ["en", "fr"])
}
@Test func openSubtitlesMapsAuthenticationAndRateLimitFailures() async throws {
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [OpenSubtitleProtocol.self]
    let episode = TVEpisode(tvdbID: 1, seriesTVDBID: 2, season: 1, number: 1, title: "Cake")
    let unauthorizedClient = OpenSubtitlesClient(apiKey: "fixture", session: URLSession(configuration: config), baseURL: URL(string: "https://fixture.test/unauthorized")!); var unauthorized = false; do { _ = try await unauthorizedClient.search(.init(episode: episode)) } catch OpenSubtitlesError.unauthorized { unauthorized = true }; #expect(unauthorized)
    let limitedClient = OpenSubtitlesClient(apiKey: "fixture", session: URLSession(configuration: config), baseURL: URL(string: "https://fixture.test/limited")!); var limited = false; do { _ = try await limitedClient.search(.init(episode: episode)) } catch OpenSubtitlesError.rateLimited { limited = true }; #expect(limited)
}
