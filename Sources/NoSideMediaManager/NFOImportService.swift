import Foundation

public enum NFOImportError: LocalizedError, Equatable {
    case destinationDoesNotExist(URL)
    case fileAlreadyExists(URL)

    public var errorDescription: String? {
        switch self {
        case .destinationDoesNotExist(let url): "Destination folder does not exist: \(url.path)"
        case .fileAlreadyExists(let url): "NFO already exists: \(url.path)"
        }
    }
}

public struct NFOImportService {
    private let source: any TVMetadataSource
    private let fileManager: FileManager

    public init(source: any TVMetadataSource, fileManager: FileManager = .default) {
        self.source = source
        self.fileManager = fileManager
    }

    @discardableResult
    public func importSeries(id: Int, into directory: URL, replaceExisting: Bool = false) async throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw NFOImportError.destinationDoesNotExist(directory)
        }
        let metadataSource = source
        async let fetchedSeries = metadataSource.series(id: id)
        async let fetchedEpisodes = metadataSource.episodes(forSeriesID: id)
        let (series, episodes) = try await (fetchedSeries, fetchedEpisodes)
        let seriesURL = directory.appendingPathComponent("tvshow.nfo")
        let episodeFiles: [(episode: TVEpisode, url: URL)] = episodes.compactMap { episode in
            guard episode.season >= 0, episode.number >= 0 else { return nil }
            return (episode, directory.appendingPathComponent(String(format: "S%02dE%02d.nfo", episode.season, episode.number)))
        }
        let plannedURLs = [seriesURL] + episodeFiles.map(\.url)
        if !replaceExisting, let existing = plannedURLs.first(where: { fileManager.fileExists(atPath: $0.path) }) {
            throw NFOImportError.fileAlreadyExists(existing)
        }
        var written = [URL]()
        try write(NFOWriter.seriesData(series), to: seriesURL, replaceExisting: replaceExisting)
        written.append(seriesURL)
        for file in episodeFiles {
            let url = file.url
            try write(NFOWriter.episodeData(file.episode), to: url, replaceExisting: replaceExisting)
            written.append(url)
        }
        return written
    }

    private func write(_ data: Data, to url: URL, replaceExisting: Bool) throws {
        guard replaceExisting || !fileManager.fileExists(atPath: url.path) else { throw NFOImportError.fileAlreadyExists(url) }
        try data.write(to: url, options: .atomic)
    }
}
