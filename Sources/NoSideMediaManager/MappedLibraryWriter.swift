import Foundation

public struct ApprovedEpisodeMapping: Sendable, Equatable {
    public let local: LocalEpisodeFile
    public let canonical: TVEpisode
    public let downloadArtwork: Bool
    /// TVDB fields explicitly approved to replace an existing episode NFO.
    public let nfoFieldsToReplace: Set<String>
    public init(local: LocalEpisodeFile, canonical: TVEpisode, downloadArtwork: Bool = true, nfoFieldsToReplace: Set<String> = ["title", "plot", "aired", "season", "episode"]) { self.local = local; self.canonical = canonical; self.downloadArtwork = downloadArtwork; self.nfoFieldsToReplace = nfoFieldsToReplace }
}

/// Writes sidecars next to the media files selected in a reviewed mapping.
public enum MappedLibraryWriter {
    @discardableResult
    public static func write(series: TVSeries, mappings: [ApprovedEpisodeMapping], in directory: URL, downloadArtwork: Bool, replaceExisting: Bool = false) async throws -> [URL] {
        var outputs = [URL]()
        let showNFO = directory.appendingPathComponent("tvshow.nfo")
        try write(NFOWriter.seriesData(series), to: showNFO, replace: replaceExisting); outputs.append(showNFO)
        let byFolder = Dictionary(grouping: mappings, by: { $0.local.url.deletingLastPathComponent() })
        for (folder, folderMappings) in byFolder {
            let seasons = Set(folderMappings.map { $0.canonical.season })
            guard seasons.count == 1, let season = seasons.first else { continue }
            let seasonNFO = folder.appendingPathComponent("season.nfo")
            let metadata = series.seasons.first { $0.number == season }
            try write(NFOWriter.seasonData(number: season, title: metadata?.title, overview: metadata?.overview, premiered: metadata?.aired), to: seasonNFO, replace: replaceExisting)
            outputs.append(seasonNFO)
            if downloadArtwork, let artwork = metadata?.artworkURL {
                let poster = folder.appendingPathComponent("season.jpg")
                _ = try await ArtworkDownloader.download(artwork, to: poster)
                outputs.append(poster)
            }
        }
        for mapping in mappings {
            let nfo = mapping.local.url.deletingPathExtension().appendingPathExtension("nfo")
            try write(NFOWriter.episodeData(mapping.canonical), to: nfo, replace: replaceExisting); outputs.append(nfo)
            if downloadArtwork, mapping.downloadArtwork, let artwork = mapping.canonical.artworkURL {
                let jpg = mapping.local.url.deletingPathExtension().appendingPathExtension("jpg")
                _ = try await ArtworkDownloader.download(artwork, to: jpg)
                outputs.append(jpg)
            }
        }
        return outputs
    }
    private static func write(_ data: Data, to url: URL, replace: Bool) throws {
        guard replace || !FileManager.default.fileExists(atPath: url.path) else { throw NFOImportError.fileAlreadyExists(url) }
        try data.write(to: url, options: .atomic)
    }
}
