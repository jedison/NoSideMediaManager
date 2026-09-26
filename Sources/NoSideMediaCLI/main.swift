import Foundation
import Darwin
import NoSideMediaManager

@main
struct NoSideMediaCLI {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let command = arguments.first else { throw CLIError.usage }
            switch command {
            case "inspect" where arguments.count == 2:
                let url = URL(fileURLWithPath: arguments[1]); var isDirectory: ObjCBool = false
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    var infos = [EmbeddedMediaInfo]()
                    for file in MediaFileInspector.videoFiles(in: url) { infos.append(try await MediaFileInspector.inspect(file)) }
                    print(String(decoding: try encoder.encode(infos), as: UTF8.self))
                } else {
                    print(String(decoding: try encoder.encode(try await MediaFileInspector.inspect(url)), as: UTF8.self))
                }
            case "search" where arguments.count == 2:
                let source = try source()
                for result in try await source.searchSeries(named: arguments[1]) { print("\(result.tvdbID)\t\(result.title)\(result.year.map { " (\($0))" } ?? "")") }
            case "review" where arguments.count >= 3:
                let source = try source()
                let id = try Int(arguments[1]).unwrap(or: CLIError.usage)
                let directory = URL(fileURLWithPath: arguments[2])
                let localFiles = try await EpisodeFolderScanner.scanIncludingEmbeddedMetadata(directory: directory)
                let episodes = try await source.episodes(forSeriesID: id)
                let mappings = EpisodeMappingPlanner.propose(localFiles: localFiles, canonicalEpisodes: episodes, adoptFolderSeason: arguments.contains("--adopt-folder-season"))
                for mapping in mappings {
                    if let episode = mapping.canonical {
                        print("MATCH\t\(mapping.local.url.path)\tS\(episode.season)E\(String(format: "%02d", episode.number))\t\(episode.title)")
                    } else {
                        print("REVIEW\t\(mapping.local.url.path)\t(no number-for-number TVDB match)")
                    }
                }
                print("\(mappings.count) video files reviewed; \(mappings.filter { $0.canonical == nil }.count) require explicit mapping.")
            case "plan" where arguments.count >= 4:
                let source = try source()
                let id = try Int(arguments[1]).unwrap(or: CLIError.usage)
                let directory = URL(fileURLWithPath: arguments[2])
                let localFiles = try await EpisodeFolderScanner.scanIncludingEmbeddedMetadata(directory: directory)
                let mappings = EpisodeMappingPlanner.propose(localFiles: localFiles, canonicalEpisodes: try await source.episodes(forSeriesID: id), adoptFolderSeason: arguments.contains("--adopt-folder-season"))
                try MappingPlanDocument.proposed(seriesID: id, library: directory, mappings: mappings).write(to: URL(fileURLWithPath: arguments[3]))
                print("Wrote review plan: \(arguments[3]). Fill canonicalEpisodeID for every unresolved entry before creating a job bundle.")
            case "merge-plans" where arguments.count >= 4:
                let root = URL(fileURLWithPath: arguments[1])
                let output = URL(fileURLWithPath: arguments[2])
                let documents = try arguments.dropFirst(3).map { try MappingPlanDocument.read(from: URL(fileURLWithPath: $0)) }
                try MappingPlanDocument.combined(showRoot: root, documents: documents).write(to: output)
                print("Wrote combined review plan: \(output.path)")
            case "normalize-plan" where arguments.count == 3:
                let source = try source()
                let plan = try MappingPlanDocument.read(from: URL(fileURLWithPath: arguments[1]))
                let episodes = try await source.episodes(forSeriesID: plan.seriesTVDBID)
                let index = Dictionary(uniqueKeysWithValues: episodes.map { ($0.tvdbID, $0) })
                let normalized = try plan.normalized(series: try await source.series(id: plan.seriesTVDBID), episodesByID: index)
                try normalized.write(to: URL(fileURLWithPath: arguments[2]))
                print("Wrote normalized review plan: \(arguments[2])")
            case "bundle" where arguments.count >= 3:
                let planURL = URL(fileURLWithPath: arguments[1]); let plan = try MappingPlanDocument.read(from: planURL)
                guard plan.entries.allSatisfy({ $0.canonicalEpisodeID != nil }) else { throw CLIError.unresolvedMappings }
                let offline = arguments.contains("--offline")
                let metadata: (series: TVSeries, episodes: [Int: TVEpisode])
                if offline { metadata = try plan.offlineMetadata() }
                else {
                    let source = try source()
                    let episodes = try await source.episodes(forSeriesID: plan.seriesTVDBID)
                    metadata = (try await source.series(id: plan.seriesTVDBID), Dictionary(uniqueKeysWithValues: episodes.map { ($0.tvdbID, $0) }))
                }
                let library = URL(fileURLWithPath: plan.libraryPath); let index = metadata.episodes
                let approved = try plan.entries.map { entry -> ApprovedEpisodeMapping in guard let id = entry.canonicalEpisodeID, let episode = index[id] else { throw CLIError.unresolvedMappings }; let url = URL(fileURLWithPath: entry.sourcePath); return ApprovedEpisodeMapping(local: LocalEpisodeFile(url: url, season: episode.season, episode: episode.number), canonical: episode, downloadArtwork: entry.downloadArtwork) }
                let destinations = Dictionary(uniqueKeysWithValues: plan.entries.compactMap { entry -> (URL, URL)? in guard let destination = entry.destinationPath else { return nil }; return (URL(fileURLWithPath: entry.sourcePath), URL(fileURLWithPath: destination)) })
                let manifest = try await PortableJobBundle.create(at: URL(fileURLWithPath: arguments[2]), showRoot: library, series: metadata.series, mappings: approved, destinations: destinations, downloadArtwork: !offline && !arguments.contains("--no-artwork"))
                print("Created portable job \(manifest.jobID): \(arguments[2])")
                if offline { print("Offline package: canonical NFOs were reconstructed from the reviewed plan; no fresh TVDB artwork was downloaded.") }
                print("Copy or ZIP it, then run ./apply.sh --dry-run \"/path/to/show-root\" on the media Mac.")
            default: throw CLIError.usage
            }
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    static func credential(_ name: String) throws -> String {
        if let value = ProcessInfo.processInfo.environment[name], !value.isEmpty { return value }
        // Keychain access from debug/rebuilt command-line executables can cause
        // repeated macOS consent prompts. It is deliberately opt-in.
        if ProcessInfo.processInfo.environment["TVDB_USE_KEYCHAIN"] == "1",
           let value = TVDBCredentialStore.value(named: name) { return value }
        throw CLIError.missingCredentials
    }
    static func source() throws -> TVDBClient { TVDBClient(credentials: .init(apiKey: try credential("TVDB_API_KEY"), subscriberPIN: ProcessInfo.processInfo.environment["TVDB_PIN"])) }
}
private enum CLIError: LocalizedError { case usage, missingCredentials, unresolvedMappings; var errorDescription: String? { switch self { case .usage: "Usage: noside-media inspect <video-or-folder> | search <title> | review <tvdb-id> <folder> [--adopt-folder-season] | plan <tvdb-id> <folder> [--adopt-folder-season] | merge-plans <show-root> <output.json> <plan...> | normalize-plan <plan.json> <output.json> | bundle <plan.json> <new-job-folder> [--no-artwork|--offline]"; case .missingCredentials: "Set TVDB_API_KEY before running TVDB commands."; case .unresolvedMappings: "The plan has unresolved or invalid canonicalEpisodeID values." } } }
private extension Optional { func unwrap(or error: Error) throws -> Wrapped { guard let self else { throw error }; return self } }
