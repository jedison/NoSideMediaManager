import Foundation
import NoSideMediaManager

@main
struct NoSideMediaCLI {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let command = arguments.first else { throw CLIError.usage }
            switch command {
            case "inspect" where arguments.count == 2:
                let info = try await MediaFileInspector.inspect(URL(fileURLWithPath: arguments[1]))
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                print(String(decoding: try encoder.encode(info), as: UTF8.self))
            case "search" where arguments.count == 2:
                let source = try source()
                for result in try await source.searchSeries(named: arguments[1]) { print("\(result.tvdbID)\t\(result.title)\(result.year.map { " (\($0))" } ?? "")") }
            case "review" where arguments.count == 3:
                let source = try source()
                let id = try Int(arguments[1]).unwrap(or: CLIError.usage)
                let directory = URL(fileURLWithPath: arguments[2])
                let localFiles = try EpisodeFolderScanner.scan(directory: directory)
                let episodes = try await source.episodes(forSeriesID: id)
                let mappings = EpisodeMappingPlanner.propose(localFiles: localFiles, canonicalEpisodes: episodes)
                for mapping in mappings {
                    if let episode = mapping.canonical {
                        print("MATCH\t\(mapping.local.url.path)\tS\(episode.season)E\(String(format: "%02d", episode.number))\t\(episode.title)")
                    } else {
                        print("REVIEW\t\(mapping.local.url.path)\t(no number-for-number TVDB match)")
                    }
                }
                print("\(mappings.count) video files reviewed; \(mappings.filter { $0.canonical == nil }.count) require explicit mapping.")
            case "plan" where arguments.count == 4:
                let source = try source()
                let id = try Int(arguments[1]).unwrap(or: CLIError.usage)
                let directory = URL(fileURLWithPath: arguments[2])
                let localFiles = try EpisodeFolderScanner.scan(directory: directory)
                let mappings = EpisodeMappingPlanner.propose(localFiles: localFiles, canonicalEpisodes: try await source.episodes(forSeriesID: id))
                try MappingPlanDocument.proposed(seriesID: id, library: directory, mappings: mappings).write(to: URL(fileURLWithPath: arguments[3]))
                print("Wrote review plan: \(arguments[3]). Fill canonicalEpisodeID for every unresolved entry before creating a job bundle.")
            case "bundle" where arguments.count >= 3:
                let source = try source()
                let planURL = URL(fileURLWithPath: arguments[1]); let plan = try MappingPlanDocument.read(from: planURL)
                guard plan.entries.allSatisfy({ $0.canonicalEpisodeID != nil }) else { throw CLIError.unresolvedMappings }
                let library = URL(fileURLWithPath: plan.libraryPath); let episodes = try await source.episodes(forSeriesID: plan.seriesTVDBID); let index = Dictionary(uniqueKeysWithValues: episodes.map { ($0.tvdbID, $0) })
                let approved = try plan.entries.map { entry -> ApprovedEpisodeMapping in guard let id = entry.canonicalEpisodeID, let episode = index[id] else { throw CLIError.unresolvedMappings }; let url = URL(fileURLWithPath: entry.sourcePath); return ApprovedEpisodeMapping(local: LocalEpisodeFile(url: url, season: episode.season, episode: episode.number), canonical: episode, downloadArtwork: entry.downloadArtwork) }
                let destinations = Dictionary(uniqueKeysWithValues: plan.entries.compactMap { entry -> (URL, URL)? in guard let destination = entry.destinationPath else { return nil }; return (URL(fileURLWithPath: entry.sourcePath), URL(fileURLWithPath: destination)) })
                let manifest = try await PortableJobBundle.create(at: URL(fileURLWithPath: arguments[2]), showRoot: library, series: try await source.series(id: plan.seriesTVDBID), mappings: approved, destinations: destinations, downloadArtwork: !arguments.contains("--no-artwork"))
                print("Created portable job \(manifest.jobID): \(arguments[2])")
                print("Copy or ZIP it, then run ./apply.sh --dry-run \"/path/to/show-root\" on the media Mac.")
            default: throw CLIError.usage
            }
        } catch { fputs("Error: \(error.localizedDescription)\n", stderr) }
    }
    static func credential(_ name: String) throws -> String { try ProcessInfo.processInfo.environment[name].unwrap(or: CLIError.missingCredentials) }
    static func source() throws -> TVDBClient { TVDBClient(credentials: .init(apiKey: try credential("TVDB_API_KEY"), subscriberPIN: ProcessInfo.processInfo.environment["TVDB_PIN"])) }
}
private enum CLIError: LocalizedError { case usage, missingCredentials, unresolvedMappings; var errorDescription: String? { switch self { case .usage: "Usage: noside-media inspect <video> | search <title> | review <tvdb-id> <folder> | plan <tvdb-id> <folder> <plan.json> | bundle <plan.json> <new-job-folder> [--no-artwork]"; case .missingCredentials: "Set TVDB_API_KEY before running TVDB commands."; case .unresolvedMappings: "The plan has unresolved or invalid canonicalEpisodeID values." } } }
private extension Optional { func unwrap(or error: Error) throws -> Wrapped { guard let self else { throw error }; return self } }
