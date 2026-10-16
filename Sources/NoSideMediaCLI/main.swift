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
            case "--version" where arguments.count == 1,
                 "version" where arguments.count == 1:
                print(MMMBuildInfo.display(for: URL(fileURLWithPath: CommandLine.arguments[0])))
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
            case "movie-search" where arguments.count == 2:
                for result in try await movieSource().searchMovies(named: arguments[1]) { print("\(result.tmdbID)\t\(result.title)\(result.year.map { " (\($0))" } ?? "")") }
            case "movie-tvdb-search" where arguments.count == 2:
                for result in try await source().searchMovies(named: arguments[1]) { print("\(result.tvdbID)\t\(result.title)\(result.year.map { " (\($0))" } ?? "")") }
            case "movie-audit" where arguments.count == 2:
                let items = await MovieLibraryAudit.inspect(directory: URL(fileURLWithPath: arguments[1])); let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; print(String(decoding: try encoder.encode(items), as: UTF8.self))
            case "movie-health" where arguments.count == 2:
                let report = await MovieLibraryAudit.health(directory: URL(fileURLWithPath: arguments[1])); let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; print(String(decoding: try encoder.encode(report), as: UTF8.self))
            case "movie-health-html" where arguments.count == 3:
                let report = await MovieLibraryAudit.health(directory: URL(fileURLWithPath: arguments[1]))
                try MovieLibraryAudit.htmlReport(report).write(to: URL(fileURLWithPath: arguments[2]), atomically: true, encoding: .utf8)
                print("Wrote movie health report: \(arguments[2])")
            case "movie-ignore-list" where arguments.count == 2:
                for rule in MovieLibraryAudit.ignoreRules(in: URL(fileURLWithPath: arguments[1])) { print(rule) }
            case "movie-ignore-add" where arguments.count == 3:
                try MovieLibraryAudit.addIgnoreRule(arguments[2], in: URL(fileURLWithPath: arguments[1]))
                print("Added MMM audit exclusion: \(arguments[2])")
            case "movie-ignore-remove" where arguments.count == 3:
                try MovieLibraryAudit.removeIgnoreRule(arguments[2], in: URL(fileURLWithPath: arguments[1]))
                print("Removed MMM audit exclusion: \(arguments[2])")
            case "movie-embedded-bundle" where arguments.count == 4:
                let source = URL(fileURLWithPath: arguments[2]); let embedded = try await MediaFileInspector.extractMovieMetadata(source)
                guard let title = embedded.title, !title.isEmpty else { throw CLIError.unresolvedMappings }
                let manifest = try PortableJobBundle.createEmbeddedMovie(at: URL(fileURLWithPath: arguments[3]), libraryRoot: URL(fileURLWithPath: arguments[1]), source: source, title: title, creationDate: embedded.creationDate, artwork: embedded.artwork)
                print("Created embedded-metadata movie job \(manifest.jobID): \(arguments[3])")
            case "movie-plan" where arguments.count == 5:
                let id = try Int(arguments[1]).unwrap(or: CLIError.usage)
                let plan = MoviePlanDocument(libraryPath: arguments[2], entries: [.init(sourcePath: arguments[3], tmdbID: id)])
                try plan.write(to: URL(fileURLWithPath: arguments[4]))
                print("Wrote movie review plan: \(arguments[4]). Review the TMDB ID before normalization.")
            case "movie-preservation-plan" where arguments.count == 3:
                let library = URL(fileURLWithPath: arguments[1])
                let plan = MoviePlanDocument.preservationProposal(library: library, items: await MovieLibraryAudit.inspect(directory: library))
                guard !plan.entries.isEmpty else { throw CLIError.unresolvedMappings }
                try plan.write(to: URL(fileURLWithPath: arguments[2]))
                print("Wrote preservation plan with \(plan.entries.count) complete movie(s): \(arguments[2]). Review destinationPath values before freezing it.")
            case "movie-multipart-plan" where arguments.count >= 5:
                let library = URL(fileURLWithPath: arguments[1])
                let output = URL(fileURLWithPath: arguments[2])
                let requested = Set(arguments.dropFirst(3))
                let all = await MovieLibraryAudit.inspect(directory: library)
                let selected = all.filter { requested.contains($0.videoPath) }
                guard selected.count == requested.count, selected.allSatisfy(\.isMultiPartPreservationReady), MoviePlanDocument.isCompleteMultiPartSelection(selected, from: all) else { throw CLIError.unresolvedMappings }
                let plan = MoviePlanDocument.preservationProposal(library: library, items: selected)
                try plan.write(to: output)
                print("Wrote Emby stacked-movie plan with \(plan.entries.count) parts: \(output.path). Review it, then freeze it with movie-preservation-bundle.")
            case "movie-normalize-plan" where arguments.count >= 3:
                let plan = try MoviePlanDocument.read(from: URL(fileURLWithPath: arguments[1])); let source = try movieSource()
                let ids = Set(plan.entries.compactMap(\.tmdbID)); var movies = [Int: Movie](); for id in ids { movies[id] = try await source.movie(id: id) }
                try plan.normalized(movies: movies, oneFolderPerMovie: arguments.contains("--movie-folders")).write(to: URL(fileURLWithPath: arguments[2]))
                print("Wrote normalized movie plan: \(arguments[2])")
            case "movie-bundle" where arguments.count >= 3:
                let plan = try MoviePlanDocument.read(from: URL(fileURLWithPath: arguments[1]))
                guard plan.entries.allSatisfy({ $0.tmdbID != nil && $0.destinationPath != nil }) else { throw CLIError.unresolvedMappings }
                let source = try movieSource(); var movies = [Int: Movie](); for id in Set(plan.entries.compactMap(\.tmdbID)) { movies[id] = try await source.movie(id: id) }
                let items = try plan.entries.map { entry -> MovieBundleItem in guard let id = entry.tmdbID, let movie = movies[id], let destination = entry.destinationPath else { throw CLIError.unresolvedMappings }; return MovieBundleItem(movie: movie, source: URL(fileURLWithPath: entry.sourcePath), destination: URL(fileURLWithPath: destination), downloadArtwork: entry.downloadArtwork) }
                let manifest = try await PortableJobBundle.createMovies(at: URL(fileURLWithPath: arguments[2]), libraryRoot: URL(fileURLWithPath: plan.libraryPath), items: items, downloadArtwork: !arguments.contains("--no-artwork"), fingerprintMode: arguments.contains("--sha256") ? .sha256 : .metadata, notes: ["TMDB movie metadata was frozen into this portable job after review."])
                print("Created portable movie job \(manifest.jobID): \(arguments[2])")
            case "movie-preservation-bundle" where arguments.count >= 3:
                let plan = try MoviePlanDocument.read(from: URL(fileURLWithPath: arguments[1]))
                let manifest = try PortableJobBundle.createExistingMoviePreservation(at: URL(fileURLWithPath: arguments[2]), plan: plan, fingerprintMode: arguments.contains("--sha256") ? .sha256 : .metadata)
                print("Created preservation movie job \(manifest.jobID): \(arguments[2])")
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
                let manifest = try await PortableJobBundle.create(at: URL(fileURLWithPath: arguments[2]), showRoot: library, series: metadata.series, mappings: approved, destinations: destinations, downloadArtwork: !offline && !arguments.contains("--no-artwork"), fingerprintMode: arguments.contains("--sha256") ? .sha256 : .metadata, notes: offline ? ["Offline metadata mode: canonical NFO basics were reconstructed from the reviewed plan. No fresh TVDB descriptions, air dates, ratings, or artwork are included."] : [])
                print("Created portable job \(manifest.jobID): \(arguments[2])")
                if offline { print("Offline package: canonical NFOs were reconstructed from the reviewed plan; no fresh TVDB artwork was downloaded.") }
                print("Copy or ZIP it, then run ./apply.sh --dry-run \"/path/to/show-root\" on the media server.")
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
    static func movieSource() throws -> TMDBClient { TMDBClient(apiKey: try credential("TMDB_API_KEY")) }
}
private enum CLIError: LocalizedError { case usage, missingCredentials, unresolvedMappings; var errorDescription: String? { switch self { case .usage: "Usage: noside-media inspect <video-or-folder> | search <title> | review <tvdb-id> <folder> [--adopt-folder-season] | plan <tvdb-id> <folder> [--adopt-folder-season] | merge-plans <show-root> <output.json> <plan.json...> | normalize-plan <plan.json> <output.json> | bundle <plan.json> <new-job-folder> [--no-artwork|--offline|--sha256] | movie-audit <folder> | movie-health <folder> | movie-health-html <folder> <output.html> | movie-ignore-list <library-root> | movie-ignore-add <library-root> <relative-path> | movie-ignore-remove <library-root> <relative-path> | movie-embedded-bundle <library-root> <video> <new-job-folder> | movie-search <title> | movie-tvdb-search <title> | movie-plan <tmdb-id> <library-root> <video> <plan.json> | movie-normalize-plan <plan.json> <output.json> [--movie-folders] | movie-bundle <plan.json> <new-job-folder> [--no-artwork|--sha256] | movie-preservation-plan <library-root> <plan.json> | movie-multipart-plan <library-root> <plan.json> <part-video>... | movie-preservation-bundle <plan.json> <new-job-folder> [--sha256]"; case .missingCredentials: "Set TVDB_API_KEY or TMDB_API_KEY before running provider commands."; case .unresolvedMappings: "The plan has unresolved or invalid provider IDs/destinations, or not every part of a shared movie was selected." } } }
private extension Optional { func unwrap(or error: Error) throws -> Wrapped { guard let self else { throw error }; return self } }
