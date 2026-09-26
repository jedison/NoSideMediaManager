import Foundation

public enum ArtworkDownloader {
    private static let artworkSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpMaximumConnectionsPerHost = 32
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 3
        return URLSession(configuration: configuration)
    }()

    @discardableResult
    public static func download(_ url: URL, to destination: URL, session: URLSession? = nil, fileManager: FileManager = .default) async throws -> URL {
        guard !fileManager.fileExists(atPath: destination.path) else { throw NFOImportError.fileAlreadyExists(destination) }
        var request = URLRequest(url: url)
        // Artwork is optional package enrichment. Do not let a slow image CDN
        // hold a complete, reviewed NFO/rename job hostage.
        request.timeoutInterval = 2
        let (data, response) = try await (session ?? artworkSession).data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw TVDBClient.Error.invalidResponse }
        try data.write(to: destination, options: .atomic)
        return destination
    }
}
