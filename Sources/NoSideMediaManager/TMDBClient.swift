import Foundation

/// Small TMDB v3 adapter. Supply a TMDB v3 API key through `TMDB_API_KEY`.
public struct TMDBClient: MovieMetadataSource, Sendable {
    public enum Error: LocalizedError { case invalidURL, invalidResponse; public var errorDescription: String? { "TMDB returned an invalid response." } }
    private let apiKey: String; private let session: URLSession
    public init(apiKey: String, session: URLSession = .shared) { self.apiKey = apiKey; self.session = session }
    public func searchMovies(named query: String) async throws -> [MovieSearchResult] {
        let response: SearchResponse = try await request("search/movie", query: [URLQueryItem(name: "query", value: query)])
        return response.results.map { MovieSearchResult(tmdbID: $0.id, title: $0.title, year: $0.releaseDate.map { String($0.prefix(4)) }, overview: $0.overview) }
    }
    public func movie(id: Int) async throws -> Movie {
        let response: MovieResponse = try await request("movie/\(id)")
        return Movie(tmdbID: response.id, title: response.title, originalTitle: response.originalTitle, overview: response.overview, releaseDate: response.releaseDate, runtimeMinutes: response.runtime, rating: response.voteAverage, genres: response.genres.map(\.name), posterURL: response.posterPath.flatMap(posterURL))
    }
    private func request<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        guard var components = URLComponents(string: "https://api.themoviedb.org/3/\(path)") else { throw Error.invalidURL }
        components.queryItems = [URLQueryItem(name: "api_key", value: apiKey), URLQueryItem(name: "language", value: "en-US")] + query
        guard let url = components.url else { throw Error.invalidURL }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw Error.invalidResponse }
        return try JSONDecoder().decode(T.self, from: data)
    }
    private func posterURL(_ path: String) -> URL? { URL(string: "https://image.tmdb.org/t/p/original\(path)") }
}
private struct SearchResponse: Decodable { let results: [SearchMovie] }
private struct SearchMovie: Decodable { let id: Int; let title: String; let releaseDate: String?; let overview: String?; enum CodingKeys: String, CodingKey { case id, title, overview; case releaseDate = "release_date" } }
private struct MovieResponse: Decodable { let id: Int; let title: String; let originalTitle: String?; let overview: String?; let releaseDate: String?; let runtime: Int?; let voteAverage: Double?; let genres: [Genre]; let posterPath: String?; enum CodingKeys: String, CodingKey { case id, title, overview, runtime, genres; case originalTitle = "original_title"; case releaseDate = "release_date"; case voteAverage = "vote_average"; case posterPath = "poster_path" } }
private struct Genre: Decodable { let name: String }
