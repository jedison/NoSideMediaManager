import Foundation

/// TVDB v4 adapter. Authentication and transport remain contained here so the
/// rest of the application can support additional sources later.
public struct TVDBClient: TVMetadataSource, Sendable {
    public struct Credentials: Sendable, Equatable {
        public let apiKey: String
        public let subscriberPIN: String?

        public init(apiKey: String, subscriberPIN: String? = nil) {
            self.apiKey = apiKey
            self.subscriberPIN = subscriberPIN?.nilIfBlank
        }
    }

    public enum Error: LocalizedError, Equatable {
        case invalidCredentials
        case invalidResponse
        case server(statusCode: Int, message: String?)

        public var errorDescription: String? {
            switch self {
            case .invalidCredentials: "TVDB credentials are missing or invalid."
            case .invalidResponse: "TVDB returned a response that could not be read."
            case let .server(statusCode, message): message ?? "TVDB request failed (HTTP \(statusCode))."
            }
        }
    }

    private let credentials: Credentials
    private let session: URLSession
    private let baseURL: URL

    public init(credentials: Credentials, session: URLSession = .shared, baseURL: URL = URL(string: "https://api4.thetvdb.com/v4")!) {
        self.credentials = credentials
        self.session = session
        self.baseURL = baseURL
    }

    public func searchSeries(named query: String) async throws -> [TVSeriesSearchResult] {
        let token = try await login()
        var components = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "query", value: query), URLQueryItem(name: "type", value: "series")]
        let response: TVDBEnvelope<[SearchRecord]> = try await get(components.url!, token: token)
        return response.data.map { TVSeriesSearchResult(tvdbID: $0.tvdbID, title: $0.name, overview: $0.overview, year: $0.year) }
    }

    public func series(id: Int) async throws -> TVSeries {
        let response: TVDBEnvelope<SeriesRecord> = try await authorizedGet(path: "series/\(id)/extended")
        let record = response.data
        return TVSeries(tvdbID: record.id, title: record.name, overview: record.overview, firstAired: record.firstAired, status: record.status?.name, genres: record.genres?.map(\.name) ?? [], network: record.companies?.first(where: { $0.companyType?.companyTypeName == "Network" })?.name, rating: record.score)
    }

    public func episodes(forSeriesID id: Int) async throws -> [TVEpisode] {
        let token = try await login()
        // Use TVDB's explicit official (UK aired) order. This keeps long-running
        // shows such as GBBO as one continuous series rather than adopting a
        // provider-specific regional/streaming split.
        var nextURL: URL? = baseURL.appendingPathComponent("series/\(id)/episodes/official/eng")
        var episodes = [TVEpisode]()
        while let url = nextURL {
            let response: TVDBEpisodePage = try await get(url, token: token)
            episodes += response.data.episodes.map {
                TVEpisode(tvdbID: $0.id, seriesTVDBID: $0.seriesID ?? id, season: $0.seasonNumber ?? 0, number: $0.number ?? 0, title: $0.name ?? "Episode \($0.id)", overview: $0.overview, aired: $0.aired, rating: $0.score, artworkURL: Self.artworkURL(from: $0.image))
            }
            nextURL = response.links?.next.map { URL(string: $0, relativeTo: baseURL)?.absoluteURL } ?? nil
        }
        return episodes.sorted { ($0.season, $0.number, $0.tvdbID) < ($1.season, $1.number, $1.tvdbID) }
    }

    /// TVDB can return artwork as an absolute URL, a protocol-relative URL, or
    /// a legacy `/banners/...` path. Package builders need a fetchable URL.
    static func artworkURL(from value: String?) -> URL? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if value.hasPrefix("//") { return URL(string: "https:" + value) }
        if let url = URL(string: value), let scheme = url.scheme?.lowercased(), (scheme == "https" || scheme == "http"), url.host != nil { return url }
        let path = value.hasPrefix("/") ? String(value.dropFirst()) : value
        return URL(string: "https://artworks.thetvdb.com/")?.appendingPathComponent(path)
    }

    private func authorizedGet<T: Decodable>(path: String) async throws -> T {
        let token = try await login()
        return try await get(baseURL.appendingPathComponent(path), token: token)
    }

    private func login() async throws -> String {
        guard !credentials.apiKey.isEmpty else { throw Error.invalidCredentials }
        var request = URLRequest(url: baseURL.appendingPathComponent("login"))
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct LoginBody: Encodable { let apikey: String; let pin: String? }
        request.httpBody = try JSONEncoder().encode(LoginBody(apikey: credentials.apiKey, pin: credentials.subscriberPIN))
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        guard let token = try JSONDecoder().decode(TVDBEnvelope<Token>.self, from: data).data.token.nilIfBlank else { throw Error.invalidResponse }
        return token
    }

    private func get<T: Decodable>(_ url: URL, token: String) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw Error.invalidResponse }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw Error.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let message = try? JSONDecoder().decode(TVDBFailure.self, from: data).message
            throw Error.server(statusCode: http.statusCode, message: message)
        }
    }
}

private struct TVDBEnvelope<T: Decodable>: Decodable { let data: T }
private struct Token: Decodable { let token: String }
private struct TVDBFailure: Decodable { let message: String? }
private struct SearchRecord: Decodable {
    let tvdbID: Int
    let name: String
    let overview: String?
    let year: String?
    enum CodingKeys: String, CodingKey { case tvdbID = "tvdb_id", name, overview, year }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let integer = try? values.decode(Int.self, forKey: .tvdbID) { tvdbID = integer }
        else { tvdbID = Int(try values.decode(String.self, forKey: .tvdbID)) ?? 0 }
        name = try values.decode(String.self, forKey: .name)
        overview = try values.decodeIfPresent(String.self, forKey: .overview)
        year = try values.decodeIfPresent(String.self, forKey: .year)
    }
}
private struct SeriesRecord: Decodable {
    let id: Int
    let name: String
    let overview: String?
    let firstAired: String?
    let status: NamedRecord?
    let genres: [NamedRecord]?
    let companies: [CompanyRecord]?
    let score: Double?
}
private struct NamedRecord: Decodable { let name: String }
private struct CompanyRecord: Decodable { let name: String; let companyType: CompanyType? }
private struct CompanyType: Decodable { let companyTypeName: String? }
private struct TVDBEpisodePage: Decodable { let data: EpisodePageData; let links: Links? }
private struct EpisodePageData: Decodable { let episodes: [EpisodeRecord] }
private struct EpisodeRecord: Decodable {
    let id: Int
    let seriesID: Int?
    let seasonNumber: Int?
    let number: Int?
    let name: String?
    let overview: String?
    let aired: String?
    let score: Double?
    let image: String?
    enum CodingKeys: String, CodingKey { case id, seriesID = "seriesId", seasonNumber, number, name, overview, aired, score, image }
}
private struct Links: Decodable { let next: String? }
private extension String { var nilIfBlank: String? { isEmpty ? nil : self } }
