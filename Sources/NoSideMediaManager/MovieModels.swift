import Foundation

/// Provider-neutral movie metadata. Movie jobs never need a database: the
/// reviewed TMDB identifier is kept in the editable JSON plan and movie NFO.
public struct Movie: Sendable, Equatable {
    public let tmdbID: Int
    public let title: String
    public let originalTitle: String?
    public let overview: String?
    public let releaseDate: String?
    public let runtimeMinutes: Int?
    public let rating: Double?
    public let genres: [String]
    public let posterURL: URL?

    public init(tmdbID: Int, title: String, originalTitle: String? = nil, overview: String? = nil, releaseDate: String? = nil, runtimeMinutes: Int? = nil, rating: Double? = nil, genres: [String] = [], posterURL: URL? = nil) {
        self.tmdbID = tmdbID; self.title = title; self.originalTitle = originalTitle; self.overview = overview; self.releaseDate = releaseDate; self.runtimeMinutes = runtimeMinutes; self.rating = rating; self.genres = genres; self.posterURL = posterURL
    }
    public var year: String? { releaseDate.map { String($0.prefix(4)) }.flatMap { $0.count == 4 ? $0 : nil } }
}

public struct MovieSearchResult: Sendable, Equatable {
    public let tmdbID: Int; public let title: String; public let year: String?; public let overview: String?
    public init(tmdbID: Int, title: String, year: String? = nil, overview: String? = nil) { self.tmdbID = tmdbID; self.title = title; self.year = year; self.overview = overview }
}

public struct TVDBMovieSearchResult: Sendable, Equatable {
    public let tvdbID: Int; public let title: String; public let year: String?; public let overview: String?
    public init(tvdbID: Int, title: String, year: String? = nil, overview: String? = nil) { self.tvdbID = tvdbID; self.title = title; self.year = year; self.overview = overview }
}

public struct MovieBundleItem: Sendable {
    public let movie: Movie; public let source: URL; public let destination: URL; public let downloadArtwork: Bool
    public init(movie: Movie, source: URL, destination: URL, downloadArtwork: Bool = true) { self.movie = movie; self.source = source; self.destination = destination; self.downloadArtwork = downloadArtwork }
}

public protocol MovieMetadataSource: Sendable {
    func searchMovies(named query: String) async throws -> [MovieSearchResult]
    func movie(id: Int) async throws -> Movie
}
