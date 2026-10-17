import SwiftUI
import AppKit
import NoSideMediaManager
import NoSideMediaCompanionCore

private enum MMMAppRelease {
    static let display = MMMBuildInfo.display(in: Bundle.main)
}

private enum MMMDefaults {
    static let jobsRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("NoSideMediaManagerJobs", isDirectory: true).path
}

private struct TVDuplicateDecision: Identifiable {
    let id: String
    let label: String
    let videoPaths: [String]
}

private func configuredJobsFolder() -> URL? {
    guard let path = UserDefaults.standard.string(forKey: "companion.jobsRoot"), !path.isEmpty else { return nil }
    return URL(fileURLWithPath: path)
}

/// Launches a new instance from the installed bundle before ending this one.
/// This makes a staged, non-interrupting deployment available on demand.
@MainActor
private func restartMicroMM() {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
        if let error {
            Task { @MainActor in NSAlert(error: error).runModal() }
            return
        }
        Task { @MainActor in NSApp.terminate(nil) }
    }
}

@main
struct NoSideMediaManagerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 720, idealWidth: 840, minHeight: 620, idealHeight: 700)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Restart microMM", action: restartMicroMM)
            }
        }
    }
}

@MainActor
private final class CompanionRuntime: ObservableObject {
    static let shared = CompanionRuntime()
    @Published private(set) var server: CompanionHTTPServer?
    private(set) var service: CompanionJobService?
    @Published private(set) var status = "Companion will start automatically when configured."
    var isRunning: Bool { server != nil }
    func startFromStoredSettings() {
        guard server == nil else { return }
        let defaults = UserDefaults.standard
        let jobs = defaults.string(forKey: "companion.jobsRoot") ?? MMMDefaults.jobsRoot
        let movies = defaults.string(forKey: "companion.libraryRoot") ?? ""
        let tv = defaults.string(forKey: "companion.tvLibraryRoot") ?? ""
        let token = defaults.string(forKey: "companion.token") ?? ""
        let port = defaults.string(forKey: "companion.port") ?? "8347"
        guard let number = UInt16(port), !jobs.isEmpty, !movies.isEmpty, !tv.isEmpty, !token.isEmpty else { status = "Companion needs saved jobs, movie-library, TV-library, token, and port settings."; return }
        do {
            let key = TVDBCredentialStore.value(named: "TVDB_API_KEY")
            let credentials = key.map { TVDBClient.Credentials(apiKey: $0, subscriberPIN: TVDBCredentialStore.value(named: "TVDB_PIN")) }
            let config = CompanionConfiguration(jobsRoot: URL(fileURLWithPath: jobs), libraryRoot: URL(fileURLWithPath: movies), tvLibraryRoot: URL(fileURLWithPath: tv), token: token, version: MMMAppRelease.display, tvdbCredentials: credentials, tmdbAPIKey: TVDBCredentialStore.value(named: "TMDB_API_KEY"))
            let service = CompanionJobService(configuration: config)
            let server = CompanionHTTPServer(service: service, token: token)
            try server.start(port: number, lanVisible: defaults.object(forKey: "companion.lanVisible") as? Bool ?? true)
            self.service = service; self.server = server; status = "Companion started automatically on port \(number)."
        } catch { status = error.localizedDescription }
    }
    func stop() { server?.stop(); server = nil; service = nil; status = "Companion stopped." }
}

@MainActor
private struct ContentView: View {
    @State private var selectedTab = (ProcessInfo.processInfo.environment["MMM_COMPANION_AUTOSTART"] == "1" || UserDefaults.standard.bool(forKey: "companion.autoStart")) ? 3 : 0
    @State private var query = ""
    @State private var results = [TVSeriesSearchResult]()
    @State private var mappings = [EpisodeMapping]()
    @State private var canonicalEpisodes = [TVEpisode]()
    @State private var chosenEpisodeIDs = [URL: Int]()
    @State private var reviewedSeries: TVSeries?
    @State private var downloadArtwork = true
    @State private var nfoDifferenceCounts = [URL: Int]()
    @State private var nfoReplacementFields = [URL: Set<String>]()
    @State private var artworkSelections = [URL: Bool]()
    @State private var destinationPaths = [URL: String]()
    @State private var destination: URL?
    @State private var status = "Choose one TV show folder to audit, search TVDB, and review its episode mappings."
    @State private var isWorking = false
    @State private var tvAudit: TVLibraryAuditReport?
    @State private var tvAuditFilter = "all"
    @State private var tvReviewedFiles = 0
    @State private var tvTotalFiles = 0
    @State private var excludedTVPaths = Set<URL>()
    @State private var duplicateKeepPaths = [String: URL]()
    @State private var duplicateReviewExpanded = true
    @State private var mappingFilter = "needsDecision"
    @State private var canonicalEpisodeQuery = ""
    @State private var showPackagePreview = false
    @State private var showArtworkReview = false
    @AppStorage("tv.mappingSort") private var mappingSort = "file"

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $selectedTab) {
                Text("TV").tag(0)
                Text("Movies").tag(1)
                Text("Packages").tag(2)
                Text("Settings").tag(3)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 430)
            .padding(.vertical, 12)
            Divider()
            Group {
                switch selectedTab {
                case 0: tvScreen
                case 1: MovieToolsView()
                case 2: PackageOperationsView()
                default: MMMSettingsView()
                }
            }
        }
        .task { CompanionRuntime.shared.startFromStoredSettings() }
    }


    private var tvScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
            Text("Media Manager").font(.largeTitle.weight(.semibold))
            Text("TVDB → Kodi NFO").foregroundStyle(.secondary)
            if let destination {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected show folder").font(.headline)
                    Text(destination.path).lineLimit(1).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Choose another show folder…", action: chooseTVFolder).disabled(isWorking)
                        Button("Audit selected folder", action: auditTVFolder).disabled(isWorking)
                        Button("Clear selection") { clearTVFolder() }.disabled(isWorking)
                    }
                }
                HStack { TextField("Search TVDB (suggested from selected folder)", text: $query); Button("Search TVDB", action: search).disabled(query.isEmpty || isWorking) }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Start with one show folder").font(.headline)
                    Text("MMM will only inspect this selected show. It will not scan the whole TV library unless you explicitly choose its root.").foregroundStyle(.secondary)
                    Button("Choose TV show folder…", action: chooseTVFolder).buttonStyle(.borderedProminent).disabled(isWorking)
                }
            }
            if isWorking, tvTotalFiles > 0 { ProgressView(value: Double(tvReviewedFiles), total: Double(tvTotalFiles)) { Text("Reviewing \(tvReviewedFiles) of \(tvTotalFiles) TV video files") }.progressViewStyle(.linear) }
            if let tvAudit { tvAuditSummary(tvAudit); duplicateReview() }
            if !results.isEmpty {
                List(results, id: \.tvdbID) { result in
                    HStack { VStack(alignment: .leading) { Text(result.title); Text("TVDB \(result.tvdbID)\(result.year.map { " · \($0)" } ?? "")").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Review selected folder") { if let destination { review(result, in: destination) } }.disabled(isWorking || destination == nil) }
                }
                .frame(height: min(max(CGFloat(results.count) * 48, 96), 240))
            }
            if !mappings.isEmpty { mappingReview }
            Text(status).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(24)
        .sheet(isPresented: $showArtworkReview) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Artwork review").font(.title2.weight(.semibold))
                artworkReview
            }
            .padding(24)
            .frame(minWidth: 560, minHeight: 300)
        }
    }

    private func client() throws -> TVDBClient { guard let apiKey = TVDBCredentialStore.value(named: "TVDB_API_KEY"), !apiKey.isEmpty else { throw NSError(domain: "NoSideMMM", code: 1, userInfo: [NSLocalizedDescriptionKey: "Add the TVDB API key in Settings first."]) }; return TVDBClient(credentials: .init(apiKey: apiKey, subscriberPIN: TVDBCredentialStore.value(named: "TVDB_PIN"))) }
    private func search() { isWorking = true; status = "Searching TVDB…"; Task { do { results = try await client().searchSeries(named: query); status = "Found \(results.count) series." } catch { status = error.localizedDescription }; isWorking = false } }
    private func chooseTVFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        destination = url
        tvAudit = nil
        let selectedName = url.lastPathComponent
        let folderIsSeason = selectedName.range(of: #"(?i)^season\s*\d+\s*$"#, options: .regularExpression) != nil
        let suggestedName = folderIsSeason ? url.deletingLastPathComponent().lastPathComponent : selectedName
        query = suggestedName.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        status = "Folder selected. Check the suggested search, then choose the correct TVDB series."
    }
    private func clearTVFolder() { destination = nil; query = ""; results = []; mappings = []; canonicalEpisodes = []; reviewedSeries = nil; tvAudit = nil; excludedTVPaths = []; duplicateKeepPaths = [:]; status = "Choose one TV show folder to audit, search TVDB, and review its episode mappings." }
    private func auditTVFolder() { guard let destination else { return }; isWorking = true; tvReviewedFiles = 0; tvTotalFiles = 0; mappings = []; reviewedSeries = nil; excludedTVPaths = []; duplicateKeepPaths = [:]; duplicateReviewExpanded = true; status = "Finding TV video files…"; Task { do { let report = try await TVLibraryAudit.inspect(directory: destination) { completed, total in tvReviewedFiles = completed; tvTotalFiles = total; status = "Reviewing \(completed) of \(total) TV video files…" }; tvAudit = report; status = report.duplicates.isEmpty ? "Audited \(report.items.count) videos. Choose the correct TVDB series." : "Audited \(report.items.count) videos. Choose one file to keep for each of \(report.duplicates.count) duplicate episode group(s), then select TVDB." } catch { status = error.localizedDescription }; isWorking = false } }
    private func tvAuditSummary(_ audit: TVLibraryAuditReport) -> some View { VStack(alignment: .leading, spacing: 4) { Text("TV audit · \(audit.items.count) videos · \(audit.duplicates.count) duplicate episode candidate(s) · \(audit.unnumberedCount) unnumbered").font(.caption).foregroundStyle(.secondary); Picker("Show", selection: $tvAuditFilter) { Text("All").tag("all"); Text("Multiple copies").tag("duplicates"); Text("Folder season conflicts").tag("conflicts"); Text("Unnumbered").tag("unnumbered") }.pickerStyle(.menu); ScrollView { LazyVStack(alignment: .leading, spacing: 3) { ForEach(filteredTVAuditItems(audit)) { item in Text("\(item.episodeKey ?? "Unnumbered") · \(URL(fileURLWithPath: item.videoPath).lastPathComponent)").font(.caption).foregroundStyle(item.folderSeason.map { $0 != item.season } == true ? .orange : .secondary).lineLimit(1).contextMenu { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.videoPath)]) } } } } }.frame(maxHeight: 120) } }
    private func filteredTVAuditItems(_ audit: TVLibraryAuditReport) -> [TVEpisodeAuditItem] {
        let duplicatePaths = Set(audit.duplicates.flatMap(\.videoPaths))
        switch tvAuditFilter {
        case "duplicates":
            return audit.items.filter { duplicatePaths.contains($0.videoPath) }
        case "conflicts":
            return audit.items.filter { item in
                item.folderSeason.map { folderSeason in folderSeason != item.season } == true
            }
        case "unnumbered":
            return audit.items.filter { $0.episodeKey == nil }
        default:
            return audit.items
        }
    }
    private func duplicateReview() -> some View {
        Group {
            if !duplicateDecisionGroups.isEmpty {
                DisclosureGroup("Duplicate episode decisions (\(duplicateDecisionGroups.count))", isExpanded: $duplicateReviewExpanded) {
                    Text("Each local duplicate must have exactly one file kept in this job. Other candidates are explicitly excluded; nothing is deleted.").font(.caption).foregroundStyle(.secondary)
                    ForEach(duplicateDecisionGroups) { duplicate in
                        Picker("\(duplicate.label): keep", selection: Binding(get: { duplicateKeepPaths[duplicate.id]?.path ?? "" }, set: { chooseDuplicate($0, duplicate: duplicate) })) {
                            Text("Choose one file").tag("")
                            ForEach(duplicate.videoPaths, id: \.self) { path in
                                Text("\(URL(fileURLWithPath: path).lastPathComponent) · \(candidateFacts(path))").tag(path)
                            }
                        }
                        .pickerStyle(.menu)
                        ForEach(duplicate.videoPaths, id: \.self) { path in
                            HStack(spacing: 8) {
                                Text(URL(fileURLWithPath: path).lastPathComponent).font(.caption).lineLimit(1)
                                Text(candidateFacts(path)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                            }
                            .contextMenu { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } }
                        }
                    }
                }
            }
        }
    }
    private func fileSizeLabel(_ path: String) -> String {
        guard let size = tvAudit?.items.first(where: { $0.videoPath == path })?.fileSize else { return "size unavailable" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    private func candidateFacts(_ path: String) -> String {
        guard let item = tvAudit?.items.first(where: { $0.videoPath == path }) else { return fileSizeLabel(path) }
        var facts = [fileSizeLabel(path)]
        if let width = item.width, let height = item.height { facts.append("\(width)×\(height)") }
        if let subtitles = item.subtitleLanguages, !subtitles.isEmpty { facts.append("subtitles: \(subtitles.joined(separator: ", "))") }
        return facts.joined(separator: " · ")
    }
    private func chooseDuplicate(_ path: String, duplicate: TVDuplicateDecision) {
        let candidates = duplicate.videoPaths.map(URL.init(fileURLWithPath:))
        excludedTVPaths.subtract(candidates)
        guard !path.isEmpty else { duplicateKeepPaths.removeValue(forKey: duplicate.id); return }
        let keep = URL(fileURLWithPath: path)
        duplicateKeepPaths[duplicate.id] = keep
        excludedTVPaths.formUnion(candidates.filter { $0 != keep })
    }
    private var mappingReview: some View {
        VStack(alignment: .leading) {
            Text("Mapping review").font(.headline)
            Text("\(approved().count) included · \(effectiveExcludedTVPaths.count) excluded · \(mappingIssues.count) decision(s) remaining · \(nfoDifferenceCounts.values.filter { $0 > 0 }.count) NFOs differ").font(.caption).foregroundStyle(mappingIssues.isEmpty ? Color.secondary : Color.orange)
            HStack {
                Picker("Show", selection: $mappingFilter) {
                    Text("Needs decision (\(unresolvedMappings.count))").tag("needsDecision")
                    Text("Ready (\(readyMappings.count))").tag("ready")
                    Text("NFO changes (\(nfoChangedMappings.count))").tag("nfo")
                    Text("Season conflicts (\(seasonConflictMappings.count))").tag("conflicts")
                    Text("Duplicates (\(duplicateMappings.count))").tag("duplicates")
                    Text("All (\(mappings.count))").tag("all")
                }.pickerStyle(.menu)
                Picker("Sort", selection: $mappingSort) { Text("File name").tag("file"); Text("Local episode").tag("local"); Text("Chosen TVDB episode").tag("canonical") }.pickerStyle(.menu)
                TextField("Filter TVDB episodes", text: $canonicalEpisodeQuery).frame(maxWidth: 220)
            }
            List(filteredMappings) { mapping in
            let excluded = isEffectivelyExcluded(mapping.local.url)
            let isDuplicate = duplicateGroup(for: mapping.local.url) != nil
                VStack(alignment: .leading) {
                    HStack {
                        Text(mapping.local.url.lastPathComponent).lineLimit(1)
                        if let count = nfoDifferenceCounts[mapping.local.url], count > 0 { Text("NFO Δ\(count)").foregroundStyle(.orange).font(.caption) }
                        Spacer()
                        Toggle("Include", isOn: Binding(get: { !isEffectivelyExcluded(mapping.local.url) }, set: { include in if include { excludedTVPaths.remove(mapping.local.url) } else { excludedTVPaths.insert(mapping.local.url) } })).labelsHidden().disabled(isDuplicate)
                        Toggle("Replace artwork", isOn: Binding(get: { artworkSelections[mapping.local.url] ?? true }, set: { artworkSelections[mapping.local.url] = $0 })).labelsHidden().disabled(excluded)
                        Picker("Canonical episode", selection: Binding(get: { chosenEpisodeIDs[mapping.local.url] ?? mapping.canonical?.tvdbID ?? 0 }, set: { chosenEpisodeIDs[mapping.local.url] = $0 })) { Text("Needs review").tag(0); ForEach(episodesForPicker(mapping), id: \.tvdbID) { episode in Text("S\(episode.season)E\(episode.number) · \(episode.title)").tag(episode.tvdbID) } }.labelsHidden().disabled(excluded)
                    }
                    if isDuplicate { Text("Choose the one file to keep in Duplicate episode decisions above.").font(.caption2).foregroundStyle(.orange) }
                    if let changes = nfoChanges(for: mapping), !changes.isEmpty {
                        DisclosureGroup("Existing NFO differs: " + changes.map(\.field).joined(separator: ", ")) {
                            Text("Choose exactly which fields TVDB replaces. Unticked fields retain their existing value in the generated, Emby-locked NFO.").font(.caption2).foregroundStyle(.secondary)
                            ForEach(changes) { change in
                                Toggle(change.field, isOn: Binding(get: { nfoReplacementFields[mapping.local.url, default: Set(NFORepairInspector.comparableFields)].contains(change.field) }, set: { replace in var fields = nfoReplacementFields[mapping.local.url, default: Set(NFORepairInspector.comparableFields)]; if replace { fields.insert(change.field) } else { fields.remove(change.field) }; nfoReplacementFields[mapping.local.url] = fields }))
                            }
                        }.font(.caption2).foregroundStyle(.orange)
                    }
                    TextField("Keep location, or enter a full destination video path", text: Binding(get: { destinationPaths[mapping.local.url] ?? mapping.local.url.path }, set: { destinationPaths[mapping.local.url] = $0 })).font(.caption).disabled(excluded)
                }
                .contextMenu { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([mapping.local.url]) } }
            }.frame(height: min(max(CGFloat(filteredMappings.count) * 82, 180), 420))
            Toggle("Enable selected TVDB episode artwork replacements", isOn: $downloadArtwork)
            Text("Next: confirm the episode mappings above, optionally review the artwork choices, then preview and freeze the portable package.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Review artwork (optional)…") { showArtworkReview = true }
                    .disabled(approved().isEmpty)
                Button("Preview package…") { showPackagePreview = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(reviewedSeries == nil || isWorking || !mappingIssues.isEmpty)
                Menu("Plans & presets") {
                    Button("Load preset or plan…", action: importPlan)
                    Button("Export named preset…", action: exportPlan)
                }
                .disabled(reviewedSeries == nil || isWorking)
            }
            if showPackagePreview { packagePreview }
            Text(mappingIssues.isEmpty ? "All discovered videos have an explicit disposition. This Mac creates a reviewed package only; apply.sh changes the library on the media server." : "Resolve every mapping or explicitly exclude it before freezing. Duplicate groups also require exactly one kept file.").font(.caption).foregroundStyle(mappingIssues.isEmpty ? Color.secondary : Color.orange)
        }
    }
    private var duplicateDecisionGroups: [TVDuplicateDecision] {
        let local = (tvAudit?.duplicates ?? []).map { TVDuplicateDecision(id: "local-\($0.id)", label: $0.id, videoPaths: $0.videoPaths) }
        let canonicalIndex = Dictionary(uniqueKeysWithValues: canonicalEpisodes.map { ($0.tvdbID, $0) })
        let mapped = Dictionary(grouping: mappings.compactMap { mapping in chosenEpisodeIDs[mapping.local.url].map { ($0, mapping.local.url.path) } }, by: \.0)
            .compactMap { id, values -> TVDuplicateDecision? in
                let paths = values.map(\.1).sorted()
                guard paths.count > 1, !local.contains(where: { Set($0.videoPaths) == Set(paths) }) else { return nil }
                let label = canonicalIndex[id].map { "TVDB S\($0.season)E\($0.number)" } ?? "TVDB episode \(id)"
                return TVDuplicateDecision(id: "tvdb-\(id)", label: label, videoPaths: paths)
            }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        return local + mapped
    }
    private func duplicateGroup(for path: URL) -> TVDuplicateDecision? { duplicateDecisionGroups.first { $0.videoPaths.contains(path.path) } }
    private func isEffectivelyExcluded(_ path: URL) -> Bool {
        if excludedTVPaths.contains(path) { return true }
        guard let duplicate = duplicateGroup(for: path) else { return false }
        return duplicateKeepPaths[duplicate.id] != path
    }
    private var effectiveExcludedTVPaths: Set<URL> { Set(mappings.map(\.local.url).filter(isEffectivelyExcluded)) }
    private var unresolvedMappings: [EpisodeMapping] { mappings.filter { !isEffectivelyExcluded($0.local.url) && chosenEpisodeIDs[$0.local.url] == nil } }
    private var readyMappings: [EpisodeMapping] { mappings.filter { !isEffectivelyExcluded($0.local.url) && chosenEpisodeIDs[$0.local.url] != nil && nfoDifferenceCounts[$0.local.url, default: 0] == 0 } }
    private var nfoChangedMappings: [EpisodeMapping] { mappings.filter { nfoDifferenceCounts[$0.local.url, default: 0] > 0 } }
    private var seasonConflictMappings: [EpisodeMapping] { mappings.filter { mapping in mapping.local.folderSeason.map { $0 != mapping.local.season } ?? false } }
    private var duplicateMappings: [EpisodeMapping] {
        let paths = Set(duplicateDecisionGroups.flatMap(\.videoPaths))
        return mappings.filter { paths.contains($0.local.url.path) }
    }
    private var filteredMappings: [EpisodeMapping] {
        let filtered: [EpisodeMapping]
        switch mappingFilter {
        case "needsDecision": filtered = unresolvedMappings
        case "ready": filtered = readyMappings
        case "nfo": filtered = nfoChangedMappings
        case "conflicts": filtered = seasonConflictMappings
        case "duplicates": filtered = duplicateMappings
        default: filtered = mappings
        }
        let canonical = Dictionary(uniqueKeysWithValues: canonicalEpisodes.map { ($0.tvdbID, $0) })
        switch mappingSort {
        case "local": return filtered.sorted { ($0.local.season, $0.local.episode, $0.local.url.lastPathComponent) < ($1.local.season, $1.local.episode, $1.local.url.lastPathComponent) }
        case "canonical": return filtered.sorted { let a = chosenEpisodeIDs[$0.local.url].flatMap { canonical[$0] }; let b = chosenEpisodeIDs[$1.local.url].flatMap { canonical[$0] }; return (a?.season ?? Int.max, a?.number ?? Int.max, $0.local.url.lastPathComponent) < (b?.season ?? Int.max, b?.number ?? Int.max, $1.local.url.lastPathComponent) }
        default: return filtered.sorted { $0.local.url.lastPathComponent.localizedStandardCompare($1.local.url.lastPathComponent) == .orderedAscending }
        }
    }
    private func episodesForPicker(_ mapping: EpisodeMapping) -> [TVEpisode] {
        let query = canonicalEpisodeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return canonicalEpisodes }
        let chosen = chosenEpisodeIDs[mapping.local.url]
        return canonicalEpisodes.filter { $0.tvdbID == chosen || "S\($0.season)E\($0.number) \($0.title)".localizedCaseInsensitiveContains(query) }
    }
    private func nfoChanges(for mapping: EpisodeMapping) -> [NFOFieldDifference]? {
        guard let id = chosenEpisodeIDs[mapping.local.url], let episode = canonicalEpisodes.first(where: { $0.tvdbID == id }) else { return nil }
        return try? NFORepairInspector.differences(at: mapping.local.url.deletingPathExtension().appendingPathExtension("nfo"), comparedTo: episode)
    }
    private var packagePreview: some View {
        let selected = approved()
        let moveCount = selected.filter { destinationPaths[$0.local.url] != nil && destinationPaths[$0.local.url] != $0.local.url.path }.count
        let artworkCount = selected.filter { downloadArtwork && $0.downloadArtwork && $0.canonical.artworkURL != nil }.count
        return GroupBox("Frozen package preview") {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(selected.count) episode(s) · \(moveCount) video rename/move(s) · \(selected.count) episode NFO(s) · \(artworkCount) TVDB JPG download(s)")
                Text("Also generates tvshow.nfo and season.nfo files for represented folders. Existing matching sidecars move with their video; generated NFO/JPG files replace their target sidecars only when apply.sh runs.").font(.caption).foregroundStyle(.secondary)
                if !excludedTVPaths.isEmpty { Text("\(excludedTVPaths.count) local video(s) are recorded as excluded and are not touched.").font(.caption).foregroundStyle(.secondary) }
                HStack { Button("Choose output and freeze…", action: freezePreviewedJob).buttonStyle(.borderedProminent); Button("Close") { showPackagePreview = false } }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var artworkReview: some View {
        GroupBox("TVDB artwork review") {
            VStack(alignment: .leading, spacing: 5) {
                Text("Compare the current local JPG with the actual TVDB image. Turn replacement off to keep the local JPG unchanged; this only becomes a change in the frozen package.").font(.caption).foregroundStyle(.secondary)
                ScrollView { LazyVStack(alignment: .leading, spacing: 10) { ForEach(approved(), id: \.local.url) { mapping in HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) { Text("Current").font(.caption2); localArtworkThumbnail(for: mapping.local.url) }
                    VStack(alignment: .leading, spacing: 3) { Text("TVDB").font(.caption2); artworkThumbnail(for: mapping.canonical.artworkURL) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(mapping.local.url.lastPathComponent).lineLimit(1)
                        let local = MovieLibraryAudit.primaryArtworkURL(for: mapping.local.url.deletingPathExtension())
                        Text(mapping.canonical.artworkURL == nil ? "No TVDB image" : (artworkSelections[mapping.local.url] ?? false ? (local == nil ? "Create TVDB JPG" : "Replace local JPG with TVDB image") : "Keep existing JPG")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Replace artwork", isOn: Binding(get: { artworkSelections[mapping.local.url] ?? false }, set: { artworkSelections[mapping.local.url] = $0 })).labelsHidden().disabled(mapping.canonical.artworkURL == nil)
                } } }.frame(maxHeight: 460) }
                Button("Done") { showArtworkReview = false }
            }
        }
    }
    @ViewBuilder private func artworkThumbnail(for url: URL?) -> some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                case .failure: Color.secondary.opacity(0.2).overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                default: ProgressView()
                }
            }
            .frame(width: 104, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Color.secondary.opacity(0.12)
                .overlay(Image(systemName: "photo.slash").foregroundStyle(.secondary))
                .frame(width: 104, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
    @ViewBuilder private func localArtworkThumbnail(for video: URL) -> some View {
        if let url = MovieLibraryAudit.primaryArtworkURL(for: video.deletingPathExtension()), let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFill().frame(width: 104, height: 58).clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Color.secondary.opacity(0.12)
                .overlay(Image(systemName: "photo.slash").foregroundStyle(.secondary))
                .frame(width: 104, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
    private func review(_ result: TVSeriesSearchResult, in directory: URL) { isWorking = true; status = "Scanning local files and fetching TVDB episodes…"; Task { do { let source = try client(); let locals = try await EpisodeFolderScanner.scanIncludingEmbeddedMetadata(directory: directory); async let series = source.series(id: result.tvdbID); let episodes = try await source.episodes(forSeriesID: result.tvdbID); canonicalEpisodes = episodes; mappings = EpisodeMappingPlanner.propose(localFiles: locals, canonicalEpisodes: episodes); chosenEpisodeIDs = Dictionary(uniqueKeysWithValues: mappings.compactMap { mapping in mapping.canonical.map { episode in (mapping.local.url, episode.tvdbID) } }); artworkSelections = Dictionary(uniqueKeysWithValues: mappings.map { ($0.local.url, $0.canonical?.artworkURL != nil) }); destinationPaths = Dictionary(uniqueKeysWithValues: mappings.map { ($0.local.url, $0.local.url.path) }); nfoDifferenceCounts = Dictionary(uniqueKeysWithValues: mappings.compactMap { mapping in try? mapping.canonical.map { (mapping.local.url, try NFORepairInspector.differences(at: mapping.local.url.deletingPathExtension().appendingPathExtension("nfo"), comparedTo: $0).count) } }.compactMap { $0 }); nfoReplacementFields = Dictionary(uniqueKeysWithValues: mappings.map { ($0.local.url, Set(NFORepairInspector.comparableFields)) }); let duplicatesNeedDecision = duplicateDecisionGroups.contains { duplicateKeepPaths[$0.id] == nil }; mappingFilter = duplicatesNeedDecision ? "duplicates" : (mappings.contains { $0.canonical == nil } ? "needsDecision" : "ready"); reviewedSeries = try await series; status = "Review each mapping before applying." } catch { status = error.localizedDescription }; isWorking = false } }
    private var mappingIssues: [String] {
        var issues = mappings.filter { !excludedTVPaths.contains($0.local.url) && chosenEpisodeIDs[$0.local.url] == nil }.map { "Unmapped: \($0.local.url.lastPathComponent)" }
        for duplicate in duplicateDecisionGroups {
            let candidates = duplicate.videoPaths.map(URL.init(fileURLWithPath:))
            let included = candidates.filter { !excludedTVPaths.contains($0) }
            if duplicateKeepPaths[duplicate.id] == nil || included.count != 1 {
                issues.append("Duplicate \(duplicate.label) needs exactly one kept file")
            }
        }
        return issues
    }
    private func approved() -> [ApprovedEpisodeMapping] { let index = Dictionary(uniqueKeysWithValues: canonicalEpisodes.map { ($0.tvdbID, $0) }); return mappings.compactMap { mapping in guard !isEffectivelyExcluded(mapping.local.url) else { return nil }; return chosenEpisodeIDs[mapping.local.url].flatMap { index[$0] }.map { ApprovedEpisodeMapping(local: mapping.local, canonical: $0, downloadArtwork: artworkSelections[mapping.local.url] ?? false, nfoFieldsToReplace: nfoReplacementFields[mapping.local.url, default: Set(NFORepairInspector.comparableFields)]) } } }
    private func renamePlan() throws -> MediaRenamePlan? { let moves = mappings.compactMap { mapping -> MediaRename? in let path = destinationPaths[mapping.local.url] ?? mapping.local.url.path; return path == mapping.local.url.path ? nil : MediaRename(source: mapping.local.url, destination: URL(fileURLWithPath: path)) }; return moves.isEmpty ? nil : try MediaRenamePlan(renames: moves) }
    private func planDocument() -> MappingPlanDocument? { guard let directory = destination, let series = reviewedSeries else { return nil }; return MappingPlanDocument(seriesTVDBID: series.tvdbID, libraryPath: directory.path, entries: mappings.map { MappingPlanDocument.Entry(sourcePath: $0.local.url.path, canonicalEpisodeID: chosenEpisodeIDs[$0.local.url], destinationPath: destinationPaths[$0.local.url], downloadArtwork: artworkSelections[$0.local.url] ?? false, excluded: isEffectivelyExcluded($0.local.url)) }) }
    private func exportPlan() { guard let plan = planDocument(), let destination else { return }; let panel = NSSavePanel(); panel.nameFieldStringValue = "\(reviewedSeries?.title ?? "TV") mapping preset.json"; panel.directoryURL = destination; guard panel.runModal() == .OK, let url = panel.url else { return }; do { try TVMappingPreset.from(plan: plan, named: url.deletingPathExtension().lastPathComponent, showRoot: destination).write(to: url); status = "Named source-relative preset exported: \(url.lastPathComponent)" } catch { status = error.localizedDescription } }
    private func importPlan() { guard let series = reviewedSeries, let destination else { return }; let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = false; panel.allowedContentTypes = [.json]; guard panel.runModal() == .OK, let url = panel.url else { return }; do { let plan: MappingPlanDocument; if let preset = try? TVMappingPreset.read(from: url) { plan = preset.plan(at: destination); status = "Loaded preset ‘\(preset.name)’. Recheck duplicate decisions and preview before freezing." } else { plan = try MappingPlanDocument.read(from: url); status = "Loaded legacy reusable mapping plan. Recheck duplicate decisions and preview before freezing." }; guard plan.seriesTVDBID == series.tvdbID else { status = "That plan belongs to TVDB \(plan.seriesTVDBID), not \(series.tvdbID)."; return }; let livePaths = Set(mappings.map { $0.local.url.path }); guard plan.entries.allSatisfy({ livePaths.contains($0.sourcePath) }) else { status = "That plan references video files not found in this selected folder."; return }; for entry in plan.entries { let source = URL(fileURLWithPath: entry.sourcePath); chosenEpisodeIDs[source] = entry.canonicalEpisodeID; if let target = entry.destinationPath { destinationPaths[source] = target }; artworkSelections[source] = entry.downloadArtwork; if entry.excluded == true { excludedTVPaths.insert(source) } else { excludedTVPaths.remove(source) } } } catch { status = error.localizedDescription } }
    private func generateJob() { showPackagePreview = true }
    private func freezePreviewedJob() { guard let series = reviewedSeries, let directory = destination else { return }; guard mappingIssues.isEmpty else { status = "Resolve or exclude every discovered video before freezing: \(mappingIssues.first ?? "review issue")."; return }; let selected = approved(); guard !selected.isEmpty else { status = "Select at least one canonical episode."; return }; let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.allowsMultipleSelection = false; panel.directoryURL = configuredJobsFolder(); panel.message = "Choose where to create the portable job package (saved Jobs folder is preselected)"; guard panel.runModal() == .OK, let parent = panel.url else { return }; let output = parent.appendingPathComponent("NoSide-MMM-TVDB-\(series.tvdbID)-job", isDirectory: true); let paths = Dictionary(uniqueKeysWithValues: selected.map { mapping in (mapping.local.url, URL(fileURLWithPath: destinationPaths[mapping.local.url] ?? mapping.local.url.path)) }); let excluded = effectiveExcludedTVPaths; let exclusionNotes = excluded.sorted { $0.path < $1.path }.map { "Excluded local video after review: \($0.path)" }; isWorking = true; showPackagePreview = false; status = "Creating a portable job package…"; Task { do { let manifest = try await PortableJobBundle.create(at: output, showRoot: directory, series: series, mappings: selected, destinations: paths, downloadArtwork: downloadArtwork, notes: ["Every discovered local video was mapped or explicitly excluded in macOS review."] + exclusionNotes); status = "Job \(manifest.jobID) created for \(selected.count) included episode(s); \(excluded.count) local video(s) were explicitly excluded. Dry-run it before apply." } catch { status = error.localizedDescription }; isWorking = false } }
    private func write(_ result: TVSeriesSearchResult, into directory: URL) { isWorking = true; status = "Fetching \(result.title) and writing NFO files…"; Task { do { let files = try await NFOImportService(source: client()).importSeries(id: result.tvdbID, into: directory); status = "Wrote \(files.count) NFO files to \(directory.lastPathComponent)." } catch { status = error.localizedDescription }; isWorking = false } }
}

@MainActor
private struct MMMSettingsView: View {
    @ObservedObject private var runtime = CompanionRuntime.shared
    @State private var apiKey = TVDBCredentialStore.value(named: "TVDB_API_KEY") ?? ""
    @State private var pin = TVDBCredentialStore.value(named: "TVDB_PIN") ?? ""
    @State private var tmdbAPIKey = TVDBCredentialStore.value(named: "TMDB_API_KEY") ?? ""
    @State private var jobsRoot = UserDefaults.standard.string(forKey: "companion.jobsRoot") ?? MMMDefaults.jobsRoot
    @State private var libraryRoot = UserDefaults.standard.string(forKey: "companion.libraryRoot") ?? ""
    @State private var tvLibraryRoot = UserDefaults.standard.string(forKey: "companion.tvLibraryRoot") ?? ""
    @State private var token = UserDefaults.standard.string(forKey: "companion.token") ?? ""
    @State private var port = UserDefaults.standard.string(forKey: "companion.port") ?? "8347"
    @State private var lanVisible = UserDefaults.standard.object(forKey: "companion.lanVisible") as? Bool ?? true
    @State private var status = "Settings are stored on this Mac."
    @State private var showsAPIKey = false
    @State private var showsPIN = false
    @State private var showsTMDBKey = false
    @State private var showsToken = false
    var body: some View { VStack(alignment: .leading, spacing: 16) {
        Text("Settings").font(.largeTitle.weight(.semibold)); Text("TVDB is shared by TV work and phone-initiated searches. Keys stay in Keychain.").foregroundStyle(.secondary)
        ConcealedSettingField("TVDB API key", text: $apiKey, isRevealed: $showsAPIKey)
        ConcealedSettingField("TVDB subscriber PIN (optional)", text: $pin, isRevealed: $showsPIN)
        ConcealedSettingField("TMDB API key", text: $tmdbAPIKey, isRevealed: $showsTMDBKey)
        TextField("Jobs folder", text: $jobsRoot); TextField("Movie library root", text: $libraryRoot); TextField("TV shows library root", text: $tvLibraryRoot)
        HStack(spacing: 8) {
            ConcealedSettingField("Pairing token", text: $token, isRevealed: $showsToken)
            Button(action: copyToken) { Label("Copy pairing token", systemImage: "doc.on.doc") }
                .disabled(token.isEmpty)
                .accessibilityLabel("Copy pairing token")
        }
        HStack { TextField("Port", text: $port).frame(width: 100); Toggle("Allow devices on local network", isOn: $lanVisible) }
        HStack { Button("Save settings", action: save).buttonStyle(.borderedProminent); Button("New pairing token") { token = UUID().uuidString.replacingOccurrences(of: "-", with: "") }; Spacer(); Button(runtime.isRunning ? "Stop Companion" : "Start Companion", action: toggle).disabled(!runtime.isRunning && (libraryRoot.isEmpty || token.isEmpty)) }
        Text("microMM \(MMMAppRelease.display) · Built-in CLI: microMM.app/Contents/MacOS/noside-media").font(.caption).foregroundStyle(.secondary)
        Text("Companion starts automatically whenever microMM opens. It exposes authenticated remote audit, search, and frozen-package actions; it is not a file share.").font(.caption).foregroundStyle(.secondary); Text(runtime.isRunning ? runtime.status : status).foregroundStyle(.secondary); Spacer()
    }.padding(24) }
    private func copyToken() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
        status = "Pairing token copied."
    }
    private func save() { do { try TVDBCredentialStore.set(apiKey, named: "TVDB_API_KEY"); try TVDBCredentialStore.set(pin, named: "TVDB_PIN"); try TVDBCredentialStore.set(tmdbAPIKey, named: "TMDB_API_KEY"); let d = UserDefaults.standard; d.set(jobsRoot, forKey: "companion.jobsRoot"); d.set(libraryRoot, forKey: "companion.libraryRoot"); d.set(tvLibraryRoot, forKey: "companion.tvLibraryRoot"); d.set(token, forKey: "companion.token"); d.set(port, forKey: "companion.port"); d.set(lanVisible, forKey: "companion.lanVisible"); status = "Saved. Restart Companion to use changed paths, token, or port." } catch { status = error.localizedDescription } }
    private func toggle() { if runtime.isRunning { runtime.stop(); return }; save(); runtime.startFromStoredSettings() }
}

/// A settings field that stays concealed by default but can be briefly revealed
/// without changing its stored value.
private struct ConcealedSettingField: View {
    let title: String
    @Binding var text: String
    @Binding var isRevealed: Bool

    init(_ title: String, text: Binding<String>, isRevealed: Binding<Bool>) {
        self.title = title
        _text = text
        _isRevealed = isRevealed
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isRevealed {
                    TextField(title, text: $text)
                } else {
                    SecureField(title, text: $text)
                }
            }
            Button { isRevealed.toggle() } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isRevealed ? "Hide \(title)" : "Show \(title)")
            .help(isRevealed ? "Hide" : "Show")
        }
    }
}

@MainActor
private struct PackageOperationsView: View {
    @State private var jobs = [CompanionJob]()
    @State private var selected: CompanionJob?
    @State private var status = "Load frozen packages to dry-run, apply, or roll back them."
    @State private var log = ""
    @State private var history = [CompanionOperationHistoryEntry]()
    @State private var working = false
    @State private var confirmApply = false
    @State private var confirmDelete = false
    @State private var packageQuery = ""
    @State private var packageState = "all"
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Package Operations").font(.largeTitle.weight(.semibold))
            Text("Packages are the only way microMM changes a media library. Always dry-run first.").foregroundStyle(.secondary)
            HStack { Button("Refresh packages", action: refresh).disabled(working); if let selected { Text(selected.title).lineLimit(1).foregroundStyle(.secondary) } }
            HStack {
                TextField("Filter packages", text: $packageQuery)
                Picker("State", selection: $packageState) { Text("All").tag("all"); Text("Ready").tag("ready"); Text("Applied").tag("applied"); Text("Rolled back").tag("rolledBack") }.pickerStyle(.menu).frame(width: 130)
            }
            List(filteredJobs, selection: $selected) { job in
                VStack(alignment: .leading) {
                    Text(job.title)
                    Text("\(job.state == .applied ? "APPLIED · " : job.state == .rolledBack ? "ROLLED BACK · " : "READY · ")\(job.mediaKind.uppercased()) · \(job.provider.uppercased()) · \(job.moves) moves · \(job.generatedFiles) generated files\(job.createdAt.map { " · \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")").font(.caption).foregroundStyle(.secondary)
                    if job.unavailableArtwork > 0 { Text("\(job.unavailableArtwork) artwork download(s) unavailable when frozen").font(.caption2).foregroundStyle(.orange) }
                }
                .tag(job)
                .contextMenu {
                    Button("Dry-run") { run(.dryRun, job: job) }.disabled(job.state == .applied || working)
                    Button("Apply", role: .destructive) { selected = job; confirmApply = true }.disabled(job.state == .applied || working)
                    Button("Rollback") { run(.rollback, job: job) }.disabled(job.state != .applied || working)
                    Divider()
                    Button("Reveal in Finder") { revealPackage(job) }
                    Button("Export ZIP…") { exportPackage(job) }.disabled(working)
                    Divider()
                    Button("Delete package…", role: .destructive) { selected = job; confirmDelete = true }.disabled(job.state == .applied || working)
                }
            }
            Text("Right-click a package for dry-run, apply, rollback, Finder, ZIP, or delete actions. Applied packages retain their rollback evidence.").font(.caption).foregroundStyle(.secondary)
            if !log.isEmpty { ScrollView { Text(log).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 160) }
            if !history.isEmpty { VStack(alignment: .leading, spacing: 6) { HStack { Text("Operation history").font(.headline); Spacer(); Button("Copy latest log") { copyLatestHistoryLog() }; Button("Export history…") { exportHistory() } }; ForEach(history.reversed()) { entry in VStack(alignment: .leading, spacing: 2) { Text("\(entry.operation.rawValue) · \(entry.succeeded ? "completed" : "failed") · \(entry.date.formatted(date: .abbreviated, time: .shortened))").font(.caption); if !entry.log.isEmpty { Text(entry.log).font(.system(.caption2, design: .monospaced)).lineLimit(2).foregroundStyle(.secondary) } } } } }
            Text(status).foregroundStyle(.secondary)
        }.padding(24).task { refresh() }.onChange(of: selected) { _ in loadHistory() }.confirmationDialog("Apply this frozen package?", isPresented: $confirmApply, titleVisibility: .visible) { Button("Apply", role: .destructive) { run(.apply) } } message: { Text("This performs the reviewed package on the configured media-library root. A rollback remains available afterward.") }.confirmationDialog("Delete this frozen package?", isPresented: $confirmDelete, titleVisibility: .visible) { Button("Delete package", role: .destructive) { deleteSelectedPackage() } } message: { Text("This removes only the package folder and its generated files. It does not change media files. Applied packages cannot be deleted because their rollback evidence is retained.") }
    }
    private func service() -> CompanionJobService? { let d = UserDefaults.standard; guard let root = d.string(forKey: "companion.libraryRoot"), !root.isEmpty else { return nil }; let jobs = d.string(forKey: "companion.jobsRoot") ?? MMMDefaults.jobsRoot; let token = d.string(forKey: "companion.token") ?? ""; return CompanionJobService(configuration: .init(jobsRoot: URL(fileURLWithPath: jobs), libraryRoot: URL(fileURLWithPath: root), token: token, version: MMMAppRelease.display)) }
    private var filteredJobs: [CompanionJob] {
        jobs.filter { job in
            let stateMatches = packageState == "all" || job.state.rawValue == packageState
            let query = packageQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let textMatches = query.isEmpty || "\(job.title) \(job.id) \(job.mediaKind) \(job.provider)".localizedCaseInsensitiveContains(query)
            return stateMatches && textMatches
        }
    }
    private func refresh() { guard let service = service() else { status = "Set Jobs folder and Movie library root in Settings first."; return }; working = true; Task { jobs = await service.jobs(); selected = jobs.first; status = "Loaded \(jobs.count) frozen package(s)."; working = false; loadHistory() } }
    private func run(_ operation: CompanionOperation, job: CompanionJob? = nil) { guard let selected = job ?? selected, let service = service() else { return }; self.selected = selected; working = true; Task { do { let result = try await service.run(jobID: selected.id, operation: operation); log = result.log; status = result.succeeded ? "\(operation.rawValue) completed." : "\(operation.rawValue) failed; review the log."; jobs = await service.jobs(); self.selected = jobs.first(where: { $0.id == selected.id }); loadHistory() } catch { status = error.localizedDescription }; working = false } }
    private func loadHistory() { guard let selected, let service = service() else { history = []; return }; Task { history = (try? await service.history(jobID: selected.id)) ?? [] } }
    private func deleteSelectedPackage() { guard let selected, let service = service() else { return }; working = true; Task { do { try await service.deletePackage(jobID: selected.id); jobs = await service.jobs(); self.selected = jobs.first; log = ""; history = []; status = "Deleted frozen package ‘\(selected.title)’. No media-library files were changed." } catch { status = error.localizedDescription }; working = false } }
    private func revealPackage(_ job: CompanionJob) { guard let service = service() else { return }; Task { if let directory = await service.packageDirectory(jobID: job.id) { NSWorkspace.shared.activateFileViewerSelecting([directory]) } else { status = "The selected package is no longer present." } } }
    private func exportPackage(_ selected: CompanionJob) {
        guard let service = service() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(selected.title.replacingOccurrences(of: "/", with: "-"))-\(selected.id).zip"
        panel.message = "Export the frozen package as a portable ZIP"
        guard panel.runModal() == .OK, let output = panel.url else { return }
        working = true
        status = "Creating a portable ZIP from the frozen package…"
        Task {
            defer { working = false }
            guard let directory = await service.packageDirectory(jobID: selected.id) else { status = "The selected package is no longer present."; return }
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", directory.path, output.path]
                let errors = Pipe(); process.standardError = errors
                try process.run(); process.waitUntilExit()
                guard process.terminationStatus == 0 else { throw NSError(domain: "NoSideMMM", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)]) }
                status = "Exported \(output.lastPathComponent). The original folder remains the inspected source package."
            } catch { status = error.localizedDescription }
        }
    }
    private func copyLatestHistoryLog() {
        guard let latest = history.last else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(latest.log, forType: .string)
        status = "Copied the latest operation log."
    }
    private func exportHistory() {
        guard let selected else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(selected.title.replacingOccurrences(of: "/", with: "-"))-operation-history.json"
        panel.message = "Export immutable package-operation history"
        guard panel.runModal() == .OK, let output = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(history).write(to: output, options: .atomic)
            status = "Exported \(history.count) operation record(s) to \(output.lastPathComponent)."
        } catch { status = error.localizedDescription }
    }
}

@MainActor
private final class MovieAuditSession: ObservableObject {
    static let shared = MovieAuditSession()
    @Published var folder: URL? = {
        guard let path = UserDefaults.standard.string(forKey: "companion.libraryRoot"), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }()
    @Published var items = [MovieAuditItem]()
    @Published var selectedPaths = Set<String>()
    @Published var auditFilter = "all"
    @Published var lowResolutionHeight = 720
    @Published var status = "The saved Movie library is selected. Audit it, or choose another folder. MMM will not modify it."
    @Published var isWorking = false
    @Published var reviewedFiles = 0
    @Published var totalFiles = 0
    @Published var ignoreRules = [String]()
    @Published var invalidNFOPaths = Set<String>()
    @Published var duplicateTMDBIDs = [String: [String]]()
    @Published var orphanSidecars = [String]()

    func auditSelectedFolder() {
        guard let folder else { status = "Set Movie library root in Settings first, or choose another folder."; return }
        let configuredRoot = UserDefaults.standard.string(forKey: "companion.libraryRoot").map(URL.init(fileURLWithPath:))?.standardizedFileURL
        if folder.standardizedFileURL == configuredRoot, let sharedService = CompanionRuntime.shared.service {
            isWorking = true; reviewedFiles = 0; totalFiles = 0; status = "Joining the shared media-server audit…"
            Task { [weak self] in
                var snapshot = await sharedService.startMovieAudit()
                while snapshot.phase == .running {
                    self?.updateSharedAudit(snapshot)
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    snapshot = await sharedService.movieAuditStatus()
                }
                self?.updateSharedAudit(snapshot)
                self?.isWorking = false
            }
            return
        }
        isWorking = true; reviewedFiles = 0; totalFiles = 0; status = "Finding video files…"
        Task { [weak self] in
            let report = await MovieLibraryAudit.health(directory: folder) { completed, total in
                self?.reviewedFiles = completed; self?.totalFiles = total
                self?.status = total == 0 ? "No video files found." : "Reviewing \(completed) of \(total) video files…"
            }
            guard let self else { return }
            self.items = report.items; self.invalidNFOPaths = Set(report.invalidNFOs); self.duplicateTMDBIDs = report.duplicateTMDBIDs; self.orphanSidecars = report.orphanSidecars; self.ignoreRules = MovieLibraryAudit.ignoreRules(in: folder); self.status = "Audited \(report.items.count) videos; \(self.orphanSidecars.count) orphan sidecar(s) reported."; self.isWorking = false
        }
    }
    private func updateSharedAudit(_ snapshot: CompanionMovieAuditSnapshot) {
        reviewedFiles = snapshot.completedVideos; totalFiles = snapshot.totalVideos
        if let folder { ignoreRules = MovieLibraryAudit.ignoreRules(in: folder) }
        if let report = snapshot.report { items = report.items; invalidNFOPaths = Set(report.invalidNFOPaths); duplicateTMDBIDs = report.duplicateTMDBIDs; removeIgnoredRows(); status = "Audited \(items.count) videos." }
        else if snapshot.phase == .running { status = snapshot.totalVideos == 0 ? "Finding video files…" : "Reviewing \(snapshot.completedVideos) of \(snapshot.totalVideos) video files…" }
        else if snapshot.phase == .failed { status = snapshot.error ?? "Shared audit failed." }
    }
    func removeIgnoredRows() {
        guard let folder else { return }
        let removed = Set(items.filter { MovieLibraryAudit.isIgnored(URL(fileURLWithPath: $0.videoPath), libraryRoot: folder) }.map(\.videoPath))
        guard !removed.isEmpty else { return }
        items.removeAll { removed.contains($0.videoPath) }
        selectedPaths.subtract(removed)
        let pairs = items.compactMap { item -> (String, String)? in item.tmdbID.map { (String($0), item.videoPath) } }
        duplicateTMDBIDs = Dictionary(grouping: pairs, by: \.0).compactMapValues { values in values.count > 1 ? values.map(\.1).sorted() : nil }
    }
    func restoreSavedAuditIfAvailable() {
        guard let folder,
              let configured = UserDefaults.standard.string(forKey: "companion.libraryRoot"),
              folder.standardizedFileURL == URL(fileURLWithPath: configured).standardizedFileURL else { return }
        Task { [weak self] in
            // Companion starts alongside the app. Give it a brief chance to load
            // the retained audit before treating this screen as a fresh session.
            for _ in 0..<10 {
                if let service = CompanionRuntime.shared.service {
                    let snapshot = await service.movieAuditStatus()
                    guard snapshot.phase == .complete, snapshot.report != nil else { return }
                    guard self?.isWorking != true else { return }
                    self?.updateSharedAudit(snapshot)
                    if let completed = snapshot.completedAt {
                        let freshness = await service.movieAuditIsCurrent()
                        self?.status = freshness == true ? "Loaded current saved Movie audit from \(completed.formatted(date: .abbreviated, time: .shortened))." : freshness == false ? "Loaded saved Movie audit from \(completed.formatted(date: .abbreviated, time: .shortened)); the library has changed, so audit again before packaging." : "Loaded saved Movie audit from \(completed.formatted(date: .abbreviated, time: .shortened)); audit again before packaging because this older result cannot be freshness-checked."
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }
}

@MainActor
private struct MovieToolsView: View {
    @ObservedObject private var session = MovieAuditSession.shared
    @State private var ignoreRule = ""
    @State private var showTMDBReview = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
            Text("Movie Manager").font(.largeTitle.weight(.semibold))
            Text("Audit first. Complete movies can be reorganised without rewriting their NFOs or artwork.").foregroundStyle(.secondary)
            HStack { Button(movieFolderIsSaved ? "Audit saved Movie library" : "Audit selected Movie folder", action: { session.auditSelectedFolder() }).disabled(session.folder == nil || session.isWorking); Button("Choose another folder…", action: chooseFolder).disabled(session.isWorking); Button("Export health report…", action: exportHealthReport).disabled(session.folder == nil || session.isWorking); if let folder = session.folder { Text(folder.path).lineLimit(1).font(.caption).foregroundStyle(.secondary) } }
            if session.isWorking { ProgressView(value: Double(session.reviewedFiles), total: Double(max(session.totalFiles, 1))) { Text(session.totalFiles == 0 ? "Finding video files…" : "Reviewing \(session.reviewedFiles) of \(session.totalFiles) video files") }.progressViewStyle(.linear) }
            DisclosureGroup("Audit exclusions (\(session.ignoreRules.count))") {
                if session.ignoreRules.isEmpty { Text("No custom exclusions. Standard iTunes Extras clips are already ignored.").font(.caption).foregroundStyle(.secondary) }
                else {
                    ForEach(session.ignoreRules, id: \.self) { rule in
                        HStack {
                            Text(rule).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            Spacer()
                            Button("Remove") { removeIgnoreRule(rule) }
                                .buttonStyle(.borderless)
                        }
                    }
                }
                HStack { TextField("Relative folder or file to ignore", text: $ignoreRule); Button("Add exclusion") { addIgnoreRule() }.disabled(ignoreRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.folder == nil) }
                Text("This changes only the visible .noside-mmm-ignore configuration file; it never changes a movie. Removing an exclusion makes the item visible again after the next audit.").font(.caption2).foregroundStyle(.secondary)
            }
            Picker("Show", selection: $session.auditFilter) { Text("All (\(session.items.count))").tag("all"); Text("Needs attention (\(attentionItems.count))").tag("attention"); Text("Needs folder normalisation (\(session.items.filter(\.isPreservationReady).count))").tag("needsFolder"); Text("Shared multi-part movies (\(session.items.filter(\.isMultiPart).count))").tag("multipart"); Text("Special content / alternate encodes (\(session.items.filter { $0.contentKind?.requiresExplicitReview == true }.count))").tag("specialContent"); Text("Low resolution (\(lowResolutionItems.count))").tag("lowResolution"); Text("Artwork comparison candidates (\(artworkMismatchItems.count))").tag("artworkMismatch"); Text("Needs artwork sidecar (\(session.items.filter(\.isArtworkRepairReady).count))").tag("artworkRepair"); Text("Needs TMDB match (\(session.items.filter { $0.state == .bareNeedsTMDB }.count))").tag("tmdbMatch"); Text("Invalid NFO XML (\(session.invalidNFOPaths.count))").tag("invalidNFO"); Text("Duplicate TMDB IDs (\(duplicateTMDBPaths.count))").tag("duplicateTMDB"); Text("Cannot extract title (\(session.items.filter { $0.state == .embeddedMetadataNeedsSidecars && !$0.isEmbeddedSidecarReady }.count))").tag("unextractable") }.pickerStyle(.menu)
            if session.auditFilter == "lowResolution" {
                Stepper("Resolution threshold: \(session.lowResolutionHeight)p", value: $session.lowResolutionHeight, in: 360...2160, step: 180)
                    .font(.caption)
                Text("Only videos with readable dimensions below this height are shown. Uninspectable containers remain visible in their normal review categories.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if !session.selectedPaths.isEmpty {
                HStack {
                    Text("\(session.selectedPaths.count) selected").foregroundStyle(.secondary)
                    if !tmdbSelections.isEmpty {
                        Button("Find TMDB match…") { showTMDBReview = true }
                            .buttonStyle(.borderedProminent)
                            .disabled(session.isWorking)
                    }
                    Spacer()
                    Menu("Selection") {
                        Button("Select all shown") { session.selectedPaths.formUnion(filteredItems.map(\.videoPath)) }
                        Button("Clear selection") { session.selectedPaths.removeAll() }
                    }
                    .disabled(session.isWorking)
                }
                Text(tmdbSelections.isEmpty ? "Choose a package action below for the selected movies." : "Next: review the TMDB result, destination folder, and poster choice before freezing a package.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            List(filteredItems, id: \.videoPath, selection: $session.selectedPaths) { item in
                VStack(alignment: .leading) {
                    Text(item.nfoTitle ?? URL(fileURLWithPath: item.videoPath).lastPathComponent)
                    Text("\(item.state.rawValue) · \(folderLabel(item.folderState))\(item.contentKind.map { " · \($0.rawValue)" } ?? "")\(item.editionHint.map { " (\($0))" } ?? "")").font(.caption).foregroundStyle(item.contentKind?.requiresExplicitReview == true || item.isMultiPartPreservationReady || item.state == .bareNeedsTMDB ? .orange : .secondary)
                    if let languages = item.subtitleLanguages, !languages.isEmpty { Text("Embedded subtitles: \(languages.joined(separator: ", "))").font(.caption2).foregroundStyle(.secondary) }
                    if item.isMultiPartPreservationReady { Text(URL(fileURLWithPath: item.videoPath).lastPathComponent).font(.caption2).foregroundStyle(.secondary) }
                    if item.artworkMismatchCandidate == true { Text("Embedded cover differs from the primary local artwork — review before replacing.").font(.caption2).foregroundStyle(.orange) }
                    if duplicateTMDBPaths.contains(item.videoPath) || session.auditFilter == "lowResolution" {
                        Text(movieFacts(item)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .contextMenu {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.videoPath)]) }
                    Divider()
                    Button(session.selectedPaths.contains(item.videoPath) ? "Deselect" : "Select") {
                        if session.selectedPaths.contains(item.videoPath) { session.selectedPaths.remove(item.videoPath) } else { session.selectedPaths.insert(item.videoPath) }
                    }
                    Button("Select only this movie") { session.selectedPaths = [item.videoPath] }
                    if item.state == .bareNeedsTMDB {
                        Divider()
                        Button("Find TMDB match…") { session.selectedPaths = [item.videoPath]; showTMDBReview = true }
                    }
                    Divider()
                    if session.selectedPaths.contains(item.videoPath), session.selectedPaths.count > 1 {
                        Button("Ignore \(session.selectedPaths.count) selected movies in future audits") { ignoreSelectedMovies() }
                    } else {
                        Button("Ignore this movie in future audits") { ignoreMovies([item]) }
                    }
                }
            }
            .frame(height: min(max(CGFloat(filteredItems.count) * 58, 180), 420))
            if !session.orphanSidecars.isEmpty { DisclosureGroup("Orphan sidecars (\(session.orphanSidecars.count))") { Text("These have no same-stem video. They are reported only; MMM will not move or delete them without a future explicit package review.").font(.caption).foregroundStyle(.secondary); ForEach(session.orphanSidecars, id: \.self) { Text(URL(fileURLWithPath: $0).lastPathComponent).font(.caption) } } }
            HStack {
                Menu("Create package…") {
                    Button("Sidecars from embedded metadata…", action: createEmbeddedPackage).disabled(session.items.filter { session.selectedPaths.contains($0.videoPath) && $0.isEmbeddedSidecarReady }.isEmpty)
                    Button("Artwork repair…", action: createArtworkRepairPackage).disabled(session.items.filter { session.selectedPaths.contains($0.videoPath) && $0.isArtworkRepairReady }.isEmpty)
                    Button("Folder normalisation…", action: createSelectedPreservationPackage).disabled(!session.items.contains { session.selectedPaths.contains($0.videoPath) && $0.isPreservationReady })
                    Button("Shared multi-part movie…", action: createSelectedMultiPartPackage).disabled(!session.items.contains { session.selectedPaths.contains($0.videoPath) && $0.isMultiPartPreservationReady })
                }
                .disabled(session.selectedPaths.isEmpty || session.isWorking)
                Spacer()
                Text("Right-click a movie for selection and matching actions.").font(.caption).foregroundStyle(.secondary)
            }
            Text("Artwork repair extracts only an embedded poster and preserves the existing valid NFO. Preservation packages move only complete, valid-NFO movies. TMDB matches and unextractable containers need review first.").font(.caption).foregroundStyle(.secondary)
            Text(session.status).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(24)
        .sheet(isPresented: $showTMDBReview) { if !tmdbSelections.isEmpty, let folder = session.folder { TMDBMovieReviewSheet(items: tmdbSelections, libraryRoot: folder) { message in session.status = message; session.selectedPaths.subtract(tmdbSelections.map(\.videoPath)) } } }
        .task { session.restoreSavedAuditIfAvailable() }
    }
    private func chooseFolder() { let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; if let folder = session.folder { panel.directoryURL = folder }; guard panel.runModal() == .OK, let url = panel.url else { return }; session.folder = url; session.status = "Folder selected. Click Audit selected Movie folder to review it." }
    private var movieFolderIsSaved: Bool {
        guard let folder = session.folder, let saved = UserDefaults.standard.string(forKey: "companion.libraryRoot"), !saved.isEmpty else { return false }
        return folder.standardizedFileURL.path == URL(fileURLWithPath: saved).standardizedFileURL.path
    }
    private func selectedItems(of state: MovieSidecarState) -> [MovieAuditItem] { session.items.filter { session.selectedPaths.contains($0.videoPath) && $0.state == state } }
    private var duplicateTMDBPaths: Set<String> { Set(session.duplicateTMDBIDs.values.flatMap { $0 }) }
    private func movieFacts(_ item: MovieAuditItem) -> String {
        var facts = [String]()
        if let fileSize = item.fileSize { facts.append(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)) }
        if let width = item.width, let height = item.height { facts.append("\(width)×\(height)") }
        if let bytes = item.fileSize, let seconds = item.durationSeconds, seconds > 0 { facts.append(String(format: "%.1f Mbps", Double(bytes) * 8 / seconds / 1_000_000)) }
        if let languages = item.audioLanguages, !languages.isEmpty { facts.append("audio: \(languages.joined(separator: ", "))") }
        if let languages = item.subtitleLanguages, !languages.isEmpty { facts.append("subtitles: \(languages.joined(separator: ", "))") }
        return facts.isEmpty ? "Media details unavailable" : facts.joined(separator: " · ")
    }
    private var attentionItems: [MovieAuditItem] { session.items.filter { $0.state != .complete || $0.folderState == .needsNormalization || session.invalidNFOPaths.contains($0.videoPath) || duplicateTMDBPaths.contains($0.videoPath) } }
    private var lowResolutionItems: [MovieAuditItem] { session.items.filter { ($0.height ?? 0) > 0 && ($0.height ?? 0) < session.lowResolutionHeight } }
    private var artworkMismatchItems: [MovieAuditItem] { session.items.filter { $0.artworkMismatchCandidate == true } }
    private var filteredItems: [MovieAuditItem] { switch session.auditFilter { case "attention": attentionItems; case "needsFolder": session.items.filter(\.isPreservationReady); case "multipart": session.items.filter(\.isMultiPart); case "specialContent": session.items.filter { $0.contentKind?.requiresExplicitReview == true }; case "lowResolution": lowResolutionItems; case "artworkMismatch": artworkMismatchItems; case "artworkRepair": session.items.filter(\.isArtworkRepairReady); case "tmdbMatch": session.items.filter { $0.state == .bareNeedsTMDB }; case "invalidNFO": session.items.filter { session.invalidNFOPaths.contains($0.videoPath) }; case "duplicateTMDB": session.items.filter { duplicateTMDBPaths.contains($0.videoPath) }; case "unextractable": session.items.filter { $0.state == .embeddedMetadataNeedsSidecars && !$0.isEmbeddedSidecarReady }; default: session.items } }
    private var tmdbSelections: [MovieAuditItem] { session.items.filter { session.selectedPaths.contains($0.videoPath) && $0.state == .bareNeedsTMDB } }
    private func addIgnoreRule() { guard let folder = session.folder else { return }; do { try MovieLibraryAudit.addIgnoreRule(ignoreRule, in: folder); session.ignoreRules = MovieLibraryAudit.ignoreRules(in: folder); session.removeIgnoredRows(); session.status = "Added audit exclusion: \(ignoreRule). Matching rows were removed from this audit."; ignoreRule = "" } catch { session.status = error.localizedDescription } }
    private func removeIgnoreRule(_ rule: String) {
        guard let folder = session.folder else { return }
        do {
            try MovieLibraryAudit.removeIgnoreRule(rule, in: folder)
            session.ignoreRules = MovieLibraryAudit.ignoreRules(in: folder)
            session.status = "Removed audit exclusion: \(rule). It will be included when you next audit this library."
        } catch { session.status = error.localizedDescription }
    }
    private func ignoreSelectedMovies() {
        ignoreMovies(session.items.filter { session.selectedPaths.contains($0.videoPath) })
    }
    private func ignoreMovies(_ movies: [MovieAuditItem]) {
        guard let folder = session.folder else { return }
        let root = folder.standardizedFileURL.path + "/"
        let paths = movies.map { URL(fileURLWithPath: $0.videoPath).standardizedFileURL.path }
        guard !paths.isEmpty else { return }
        guard paths.allSatisfy({ $0.hasPrefix(root) }) else { session.status = "One or more selected movies are outside the selected Movie library."; return }
        let relativePaths = paths.map { String($0.dropFirst(root.count)) }
        do {
            for relativePath in relativePaths { try MovieLibraryAudit.addIgnoreRule(relativePath, in: folder) }
            session.ignoreRules = MovieLibraryAudit.ignoreRules(in: folder)
            let ignoredPaths = Set(paths)
            session.items.removeAll { ignoredPaths.contains(URL(fileURLWithPath: $0.videoPath).standardizedFileURL.path) }
            session.selectedPaths.subtract(movies.map(\.videoPath))
            let pairs = session.items.compactMap { item -> (String, String)? in item.tmdbID.map { (String($0), item.videoPath) } }
            session.duplicateTMDBIDs = Dictionary(grouping: pairs, by: \.0).compactMapValues { values in values.count > 1 ? values.map(\.1).sorted() : nil }
            session.status = "Ignored \(relativePaths.count) movie\(relativePaths.count == 1 ? "" : "s") in future Movie audits. Video files were not changed."
        } catch { session.status = error.localizedDescription }
    }
    private func exportHealthReport() { guard let folder = session.folder else { return }; let panel = NSSavePanel(); panel.nameFieldStringValue = "noside-mmm-movie-health.html"; panel.message = "Save a read-only movie health report"; guard panel.runModal() == .OK, let output = panel.url else { return }; session.isWorking = true; session.status = "Creating a readable movie health report…"; Task { let report = await MovieLibraryAudit.health(directory: folder); do { try MovieLibraryAudit.htmlReport(report).write(to: output, atomically: true, encoding: .utf8); session.status = "Saved health report: \(output.lastPathComponent)" } catch { session.status = error.localizedDescription }; session.isWorking = false } }
    private func folderLabel(_ state: MovieFolderState) -> String { switch state { case .normalized: "folder ready"; case .needsNormalization: "needs folder normalisation"; case .metadataIncomplete: "folder not assessed"; case .sharedMultiPart: "shared multi-part sidecars" } }
    private func createEmbeddedPackage() { guard let folder = session.folder else { return }; let selected = session.items.filter { session.selectedPaths.contains($0.videoPath) && $0.isEmbeddedSidecarReady }; guard !selected.isEmpty else { return }; let output = NSOpenPanel(); output.canChooseDirectories = true; output.canChooseFiles = false; output.canCreateDirectories = true; output.allowsMultipleSelection = false; output.directoryURL = configuredJobsFolder(); output.message = "Choose where to create the portable sidecar package (saved Jobs folder is preselected)"; guard output.runModal() == .OK, let parent = output.url else { return }; session.isWorking = true; session.status = "Extracting selected embedded metadata into a portable package…"; Task { do { var approved = [EmbeddedMovieBundleItem](); var missingTitles = [String](); for item in selected { let video = URL(fileURLWithPath: item.videoPath); let metadata = try await MediaFileInspector.extractMovieMetadata(video); guard let title = metadata.title, !title.isEmpty else { missingTitles.append(video.lastPathComponent); continue }; approved.append(.init(source: video, title: title, creationDate: metadata.creationDate, overview: metadata.overview, genres: metadata.genres, studio: metadata.studio, artist: metadata.artist, credits: metadata.credits, cast: metadata.cast, rating: metadata.rating, artwork: metadata.artwork)) }; guard missingTitles.isEmpty else { throw NSError(domain: "NoSideMMM", code: 1, userInfo: [NSLocalizedDescriptionKey: "MMM could no longer extract a title from these selected video file(s): \(missingTitles.sorted().joined(separator: ", ")). Re-audit them, or use the TMDB review workflow."]) }; let job = parent.appendingPathComponent("NoSide-MMM-Embedded-Selected-job"); let manifest = try PortableJobBundle.createEmbeddedMovies(at: job, libraryRoot: folder, items: approved); session.status = "Job \(manifest.jobID) created for \(approved.count) selected movie(s). Dry-run it on the media server." } catch { session.status = error.localizedDescription }; session.isWorking = false } }
    private func createArtworkRepairPackage() { guard let folder = session.folder else { return }; let selected = session.items.filter { session.selectedPaths.contains($0.videoPath) && $0.isArtworkRepairReady }; guard !selected.isEmpty else { return }; let output = NSOpenPanel(); output.canChooseDirectories = true; output.canChooseFiles = false; output.canCreateDirectories = true; output.allowsMultipleSelection = false; output.directoryURL = configuredJobsFolder(); output.message = "Choose where to create the portable artwork-repair package (saved Jobs folder is preselected)"; guard output.runModal() == .OK, let parent = output.url else { return }; session.isWorking = true; session.status = "Extracting poster artwork into a portable repair package…"; Task { do { var repairs = [EmbeddedArtworkRepairItem](); var missing = [String](); for item in selected { let video = URL(fileURLWithPath: item.videoPath); let metadata = try await MediaFileInspector.extractMovieMetadata(video); guard let artwork = metadata.artwork else { missing.append(video.lastPathComponent); continue }; repairs.append(.init(source: video, artwork: artwork)) }; guard missing.isEmpty else { throw NSError(domain: "NoSideMMM", code: 1, userInfo: [NSLocalizedDescriptionKey: "MMM could no longer extract poster artwork from: \(missing.sorted().joined(separator: ", ")). Re-audit them before packaging."]) }; let job = parent.appendingPathComponent("NoSide-MMM-Artwork-Repair-Selected-job"); let manifest = try PortableJobBundle.createEmbeddedArtworkRepairs(at: job, libraryRoot: folder, items: repairs); session.status = "Job \(manifest.jobID) created for \(repairs.count) selected movie(s). Existing NFOs are preserved; dry-run it on the media server." } catch { session.status = error.localizedDescription }; session.isWorking = false } }
    private func exportPreservationPlan() {
        guard let folder = session.folder else { return }
        let plan = MoviePlanDocument.preservationProposal(library: folder, items: session.items)
        guard !plan.entries.isEmpty else { session.status = "No complete movies with valid TMDB NFOs are ready to preserve."; return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "mmm-movie-preservation-plan.json"; panel.message = "Save the editable preservation plan for review"
        guard panel.runModal() == .OK, let output = panel.url else { return }
        do { try plan.write(to: output); session.status = "Saved a preservation plan for \(plan.entries.count) movie(s). Review destination paths, then freeze it." } catch { session.status = error.localizedDescription }
    }
    private func createPreservationPackage() {
        let input = NSOpenPanel(); input.canChooseDirectories = false; input.canChooseFiles = true; input.allowsMultipleSelection = false; input.message = "Choose the reviewed preservation plan"
        guard input.runModal() == .OK, let planURL = input.url else { return }
        let output = NSOpenPanel(); output.canChooseDirectories = true; output.canChooseFiles = false; output.canCreateDirectories = true; output.allowsMultipleSelection = false; output.directoryURL = configuredJobsFolder(); output.message = "Choose where to create the portable preservation package (saved Jobs folder is preselected)"
        guard output.runModal() == .OK, let parent = output.url else { return }
        session.isWorking = true; session.status = "Freezing preservation package…"
        Task { do { let plan = try MoviePlanDocument.read(from: planURL); let job = parent.appendingPathComponent("NoSide-MMM-Movie-Preservation-job"); let manifest = try PortableJobBundle.createExistingMoviePreservation(at: job, plan: plan); session.status = "Job \(manifest.jobID) created. Copy it to the media server and dry-run apply.sh." } catch { session.status = error.localizedDescription }; session.isWorking = false }
    }
    private func createSelectedPreservationPackage() {
        guard let folder = session.folder else { return }
        let selected = session.items.filter { session.selectedPaths.contains($0.videoPath) && $0.isPreservationReady }
        let plan = MoviePlanDocument.preservationProposal(library: folder, items: selected)
        guard !plan.entries.isEmpty else { session.status = "Select at least one complete movie that needs folder normalisation."; return }
        let output = NSOpenPanel(); output.canChooseDirectories = true; output.canChooseFiles = false; output.canCreateDirectories = true; output.allowsMultipleSelection = false; output.directoryURL = configuredJobsFolder(); output.message = "Choose where to create the portable preservation package (saved Jobs folder is preselected)"
        guard output.runModal() == .OK, let parent = output.url else { return }
        session.isWorking = true; session.status = "Freezing preservation package for \(plan.entries.count) selected movie(s)…"
        Task { do { let job = parent.appendingPathComponent("NoSide-MMM-Movie-Preservation-Selected-job"); let manifest = try PortableJobBundle.createExistingMoviePreservation(at: job, plan: plan); session.status = "Job \(manifest.jobID) created for \(plan.entries.count) selected movie(s). Dry-run it on the media server." } catch { session.status = error.localizedDescription }; session.isWorking = false }
    }
    private func createSelectedMultiPartPackage() {
        guard let folder = session.folder else { return }
        let selected = session.items.filter { session.selectedPaths.contains($0.videoPath) && $0.isMultiPartPreservationReady }
        guard MoviePlanDocument.isCompleteMultiPartSelection(selected, from: session.items) else { session.status = "Select every part of each shared multi-part movie before freezing it."; return }
        let plan = MoviePlanDocument.preservationProposal(library: folder, items: selected)
        let output = NSOpenPanel(); output.canChooseDirectories = true; output.canChooseFiles = false; output.canCreateDirectories = true; output.allowsMultipleSelection = false; output.directoryURL = configuredJobsFolder(); output.message = "Choose where to create the portable multi-part movie package (saved Jobs folder is preselected)"
        guard output.runModal() == .OK, let parent = output.url else { return }
        session.isWorking = true; session.status = "Freezing multi-part package for \(selected.count) movie parts…"
        Task { do { let job = parent.appendingPathComponent("NoSide-MMM-Multipart-Selected-job"); let manifest = try PortableJobBundle.createExistingMoviePreservation(at: job, plan: plan); session.status = "Job \(manifest.jobID) created for \(selected.count) Emby-stacked movie parts. Dry-run it on the media server." } catch { session.status = error.localizedDescription }; session.isWorking = false }
    }
}

@MainActor
private struct TMDBMovieReviewSheet: View {
    let items: [MovieAuditItem]
    let libraryRoot: URL
    let onFrozen: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var currentPath = ""
    @State private var query = ""
    @State private var results = [MovieSearchResult]()
    @State private var matches = [String: Int]()
    @State private var reviewedMovies = [String: Movie]()
    @State private var destinationPaths = [String: String]()
    @State private var downloadArtwork = [String: Bool]()
    @State private var status = "Review a TMDB match for every selected movie, then freeze one portable package."
    @State private var working = false
    var body: some View { VStack(alignment: .leading, spacing: 14) {
        Text("TMDB batch review").font(.title2.weight(.semibold))
        Text("\(matches.count) of \(items.count) selected movies matched").foregroundStyle(.secondary)
        HStack(spacing: 12) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(items, id: \.videoPath) { item in
                        Button {
                            currentPath = item.videoPath
                            select(item.videoPath)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(URL(fileURLWithPath: item.videoPath).lastPathComponent).lineLimit(1)
                                    Text(matches[item.videoPath].map { "TMDB \($0)" } ?? "Needs a reviewed match")
                                        .font(.caption)
                                        .foregroundStyle(matches[item.videoPath] == nil ? .orange : .secondary)
                                }
                                Spacer()
                                if matches[item.videoPath] != nil {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                            }
                            .padding(8)
                            .background(currentPath == item.videoPath ? Color.accentColor.opacity(0.16) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(minWidth: 230)
            VStack(alignment: .leading, spacing: 10) {
                if let currentItem {
                    Text(URL(fileURLWithPath: currentItem.videoPath).lastPathComponent).font(.headline).lineLimit(1)
                    HStack { TextField("TMDB search", text: $query); Button("Search") { search() }.disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || working) }
                    List(results, id: \.tmdbID) { result in Button { choose(result) } label: { VStack(alignment: .leading) { Text(result.title); Text("TMDB \(result.tmdbID)\(result.year.map { " · \($0)" } ?? "")").font(.caption).foregroundStyle(.secondary); if let overview = result.overview { Text(overview).font(.caption).lineLimit(2).foregroundStyle(.secondary) } } }.buttonStyle(.plain) }
                    if reviewedMovies[currentPath] != nil {
                        TextField("Destination video path", text: Binding(get: { destinationPaths[currentPath] ?? "" }, set: { destinationPaths[currentPath] = $0 }))
                            .textFieldStyle(.roundedBorder)
                        PosterComparison(localURL: localPosterURL, providerURL: reviewedMovies[currentPath]?.posterURL)
                        Toggle("Replace primary poster from TMDB", isOn: Binding(get: { downloadArtwork[currentPath] ?? true }, set: { downloadArtwork[currentPath] = $0 }))
                            .font(.caption)
                        GroupBox("Sidecar review") {
                            VStack(alignment: .leading, spacing: 3) {
                                let sidecars = sidecarReview(for: currentItem)
                                if sidecars.isEmpty {
                                    Text("No existing sidecars. MMM will create a locked TMDB NFO\(downloadArtwork[currentPath] ?? true ? " and poster" : "").")
                                } else {
                                    ForEach(sidecars, id: \.self) { sidecar in Text(sidecar).font(.caption) }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text("NFOs are replaced with the explicitly reviewed, locked TMDB NFO; subtitles, fanart, clearlogos, and other sidecars move unchanged. The toggle is the explicit keep/replace decision for the TMDB poster.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } else { Text("Choose a local movie.").foregroundStyle(.secondary) }
            }.frame(minWidth: 340)
        }.frame(minHeight: 300)
        HStack { Button("Freeze batch of \(items.count) reviewed movies") { freeze() }.buttonStyle(.borderedProminent).disabled(matches.count != items.count || working); Spacer(); Button("Cancel") { dismiss() } }
        Text(status).font(.caption).foregroundStyle(.secondary)
    }.padding(24).frame(minWidth: 700, minHeight: 500).onAppear { selectFirstUnmatched() }.onChange(of: currentPath) { path in select(path) } }
    private var currentItem: MovieAuditItem? { items.first { $0.videoPath == currentPath } }
    private var localPosterURL: URL? { currentItem.flatMap { MovieLibraryAudit.primaryArtworkURL(for: URL(fileURLWithPath: $0.videoPath).deletingPathExtension()) } }
    private func tmdb() throws -> TMDBClient { guard let key = TVDBCredentialStore.value(named: "TMDB_API_KEY"), !key.isEmpty else { throw NSError(domain: "NoSideMMM", code: 1, userInfo: [NSLocalizedDescriptionKey: "Add the TMDB API key in Settings first."]) }; return TMDBClient(apiKey: key) }
    private func selectFirstUnmatched() { currentPath = items.first(where: { matches[$0.videoPath] == nil })?.videoPath ?? items.first?.videoPath ?? ""; select(currentPath) }
    private func select(_ path: String) { guard !path.isEmpty else { return }; query = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent; results = [] }
    private func sidecarReview(for item: MovieAuditItem?) -> [String] {
        guard let item else { return [] }
        let video = URL(fileURLWithPath: item.videoPath)
        let stem = video.deletingPathExtension().lastPathComponent
        let parent = video.deletingLastPathComponent()
        let files = (try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return files.filter { file in
            let name = file.lastPathComponent
            guard file.path != video.path, name.hasPrefix(stem) else { return false }
            let remainder = String(name.dropFirst(stem.count))
            return remainder.hasPrefix(".") || remainder.hasPrefix("-")
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }.map { file in
            let lower = file.pathExtension.lowercased()
            if lower == "nfo" { return "\(file.lastPathComponent) — replace with reviewed TMDB NFO" }
            if ["jpg", "jpeg", "png"].contains(lower), downloadArtwork[currentPath] ?? true { return "\(file.lastPathComponent) — move, then replace poster if it is the canonical poster" }
            return "\(file.lastPathComponent) — move unchanged"
        }
    }
    private func search() { working = true; Task { defer { working = false }; do { results = try await tmdb().searchMovies(named: query); status = "Choose the correct TMDB result for this movie." } catch { status = error.localizedDescription } } }
    private func choose(_ result: MovieSearchResult) {
        guard !currentPath.isEmpty else { return }
        working = true
        Task {
            defer { working = false }
            do {
                let movie = try await tmdb().movie(id: result.tmdbID)
                let proposed = try MoviePlanDocument(libraryPath: libraryRoot.path, entries: [.init(sourcePath: currentPath, tmdbID: movie.tmdbID)]).normalized(movies: [movie.tmdbID: movie], oneFolderPerMovie: true)
                guard let destination = proposed.entries.first?.destinationPath else { throw NSError(domain: "NoSideMMM", code: 1, userInfo: [NSLocalizedDescriptionKey: "MMM could not prepare a destination."]) }
                matches[currentPath] = movie.tmdbID
                reviewedMovies[currentPath] = movie
                destinationPaths[currentPath] = destination
                downloadArtwork[currentPath] = true
                status = "TMDB \(movie.tmdbID) selected. Confirm the destination and poster choice, then continue."
            } catch { status = error.localizedDescription }
        }
    }
    private func freeze() {
        guard matches.count == items.count, reviewedMovies.count == items.count else { return }
        let missingDestinations = items.contains { (destinationPaths[$0.videoPath] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !missingDestinations else { status = "Every selected movie needs a destination path."; return }
        working = true
        Task {
            defer { working = false }
            do {
                let bundleItems = try items.map { item -> MovieBundleItem in
                    guard let movie = reviewedMovies[item.videoPath], let destination = destinationPaths[item.videoPath] else { throw NSError(domain: "NoSideMMM", code: 1, userInfo: [NSLocalizedDescriptionKey: "A reviewed movie is incomplete."]) }
                    return .init(movie: movie, source: URL(fileURLWithPath: item.videoPath), destination: URL(fileURLWithPath: destination), downloadArtwork: downloadArtwork[item.videoPath] ?? true)
                }
                let parent = configuredJobsFolder() ?? FileManager.default.temporaryDirectory
                let bundle = parent.appendingPathComponent("NoSide-MMM-TMDB-Batch-\(UUID().uuidString.lowercased())-job", isDirectory: true)
                let manifest = try await PortableJobBundle.createMovies(at: bundle, libraryRoot: libraryRoot, items: bundleItems, notes: ["TMDB matches, destinations, and poster choices were explicitly reviewed in the macOS app."])
                onFrozen("Job \(manifest.jobID) created for \(bundleItems.count) reviewed movies. Dry-run it before apply.")
                dismiss()
            } catch { status = error.localizedDescription }
        }
    }
}

/// A review surface only. The selected toggle remains the sole instruction
/// that a frozen package may replace a primary local poster.
private struct PosterComparison: View {
    let localURL: URL?
    let providerURL: URL?

    var body: some View {
        GroupBox("Poster comparison") {
            HStack(alignment: .top, spacing: 14) {
                poster(label: "Current local", localURL: localURL)
                poster(label: "TMDB", remoteURL: providerURL)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func poster(label: String, localURL: URL? = nil, remoteURL: URL? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold))
            if let localURL, let image = NSImage(contentsOf: localURL) {
                Image(nsImage: image).resizable().scaledToFit().frame(width: 100, height: 150)
            } else if let remoteURL {
                AsyncImage(url: remoteURL) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFit()
                    case .failure: missingPoster("Unavailable")
                    default: ProgressView()
                    }
                }.frame(width: 100, height: 150)
            } else {
                missingPoster("None")
            }
        }
        .frame(width: 110, alignment: .leading)
    }

    private func missingPoster(_ text: String) -> some View {
        VStack(spacing: 6) { Image(systemName: "photo").font(.title2); Text(text).font(.caption2) }
            .foregroundStyle(.secondary)
            .frame(width: 100, height: 150)
    }
}
