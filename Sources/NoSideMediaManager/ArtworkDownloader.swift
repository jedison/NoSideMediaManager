import Foundation

public enum ArtworkDownloader {
    @discardableResult
    public static func download(_ url: URL, to destination: URL, session: URLSession = .shared, fileManager: FileManager = .default) async throws -> URL {
        guard !fileManager.fileExists(atPath: destination.path) else { throw NFOImportError.fileAlreadyExists(destination) }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw TVDBClient.Error.invalidResponse }
        try data.write(to: destination, options: .atomic)
        return destination
    }
}
