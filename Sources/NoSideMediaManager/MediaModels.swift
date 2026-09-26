import Foundation

public struct TVSeries: Sendable, Equatable {
    public let tvdbID: Int
    public let title: String
    public let overview: String?
    public let firstAired: String?
    public let status: String?
    public let genres: [String]
    public let network: String?
    public let rating: Double?

    public init(tvdbID: Int, title: String, overview: String? = nil, firstAired: String? = nil, status: String? = nil, genres: [String] = [], network: String? = nil, rating: Double? = nil) {
        self.tvdbID = tvdbID
        self.title = title
        self.overview = overview
        self.firstAired = firstAired
        self.status = status
        self.genres = genres
        self.network = network
        self.rating = rating
    }
}

public struct TVEpisode: Sendable, Equatable {
    public let tvdbID: Int
    public let seriesTVDBID: Int
    public let season: Int
    public let number: Int
    public let title: String
    public let overview: String?
    public let aired: String?
    public let rating: Double?
    public let artworkURL: URL?

    public init(tvdbID: Int, seriesTVDBID: Int, season: Int, number: Int, title: String, overview: String? = nil, aired: String? = nil, rating: Double? = nil, artworkURL: URL? = nil) {
        self.tvdbID = tvdbID
        self.seriesTVDBID = seriesTVDBID
        self.season = season
        self.number = number
        self.title = title
        self.overview = overview
        self.aired = aired
        self.rating = rating
        self.artworkURL = artworkURL
    }
}

public struct TVSeriesSearchResult: Sendable, Equatable {
    public let tvdbID: Int
    public let title: String
    public let overview: String?
    public let year: String?

    public init(tvdbID: Int, title: String, overview: String? = nil, year: String? = nil) {
        self.tvdbID = tvdbID
        self.title = title
        self.overview = overview
        self.year = year
    }
}

public protocol TVMetadataSource: Sendable {
    func searchSeries(named query: String) async throws -> [TVSeriesSearchResult]
    func series(id: Int) async throws -> TVSeries
    func episodes(forSeriesID id: Int) async throws -> [TVEpisode]
}
