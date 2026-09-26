import Foundation

public struct LibraryChangeManifest: Codable, Sendable, Equatable {
    public let createdAt: Date
    public let renames: [MediaRename]
    public let writtenFiles: [URL]
    public var undoRenames: [MediaRename] { renames.reversed().map { MediaRename(source: $0.destination, destination: $0.source) } }
}

public enum LibraryApplyService {
    @discardableResult
    public static func apply(series: TVSeries, mappings: [ApprovedEpisodeMapping], directory: URL, renamePlan: MediaRenamePlan? = nil, downloadArtwork: Bool, manifestURL: URL, replaceExisting: Bool = false) async throws -> LibraryChangeManifest {
        let companionPlan = try renamePlan.map { try CompanionRenamePlanner.expand(videoPlan: $0) }
        let renames = companionPlan?.filePlan.renames ?? []
        if let companionPlan { try CompanionRenamePlanner.execute(companionPlan) }
        let relocated = mappings.map { mapping -> ApprovedEpisodeMapping in
            let moved = renames.first(where: { $0.source == mapping.local.url })
            return ApprovedEpisodeMapping(local: LocalEpisodeFile(url: moved?.destination ?? mapping.local.url, season: mapping.local.season, episode: mapping.local.episode), canonical: mapping.canonical)
        }
        let written = try await MappedLibraryWriter.write(series: series, mappings: relocated, in: directory, downloadArtwork: downloadArtwork, replaceExisting: replaceExisting)
        let manifest = LibraryChangeManifest(createdAt: Date(), renames: renames, writtenFiles: written)
        try JSONEncoder.pretty.encode(manifest).write(to: manifestURL, options: .atomic)
        return manifest
    }
}
private extension JSONEncoder { static var pretty: JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder } }
