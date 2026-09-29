import SwiftUI
import AppKit
import NoSideMediaManager
import NoSideMediaCompanionCore

private enum MMMAppRelease {
    static let display = MMMBuildInfo.display(in: Bundle.main)
}

@main
struct NoSideMediaManagerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 720, idealWidth: 840, minHeight: 620, idealHeight: 700)
        }
    }
}

@MainActor
private final class CompanionRuntime: ObservableObject {
    static let shared = CompanionRuntime()
    @Published private(set) var server: CompanionHTTPServer?
    @Published private(set) var status = "Companion will start automatically when configured."
    var isRunning: Bool { server != nil }
    func startFromStoredSettings() {
        guard server == nil else { return }
        let defaults = UserDefaults.standard
        let jobs = defaults.string(forKey: "companion.jobsRoot") ?? "~/NoSideMediaManagerJobs"
        let movies = defaults.string(forKey: "companion.libraryRoot") ?? ""
        let tv = defaults.string(forKey: "companion.tvLibraryRoot") ?? "/Volumes/Movies/My/TV Shows"
        let token = defaults.string(forKey: "companion.token") ?? ""
        let port = defaults.string(forKey: "companion.port") ?? "8347"
        guard let number = UInt16(port), !jobs.isEmpty, !movies.isEmpty, !tv.isEmpty, !token.isEmpty else { status = "Companion needs saved jobs, movie-library, TV-library, token, and port settings."; return }
        do {
            let key = TVDBCredentialStore.value(named: "TVDB_API_KEY")
            let credentials = key.map { TVDBClient.Credentials(apiKey: $0, subscriberPIN: TVDBCredentialStore.value(named: "TVDB_PIN")) }
            let config = CompanionConfiguration(jobsRoot: URL(fileURLWithPath: jobs), libraryRoot: URL(fileURLWithPath: movies), tvLibraryRoot: URL(fileURLWithPath: tv), token: token, version: MMMAppRelease.display, tvdbCredentials: credentials)
            let server = CompanionHTTPServer(service: CompanionJobService(configuration: config), token: token)
            try server.start(port: number, lanVisible: defaults.object(forKey: "companion.lanVisible") as? Bool ?? true)
            self.server = server; status = "Companion started automatically on port \(number)."
        } catch { status = error.localizedDescription }
    }
    func stop() { server?.stop(); server = nil; status = "Companion stopped." }
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
    @State private var artworkSelections = [URL: Bool]()
    @State private var destinationPaths = [URL: String]()
    @State private var destination: URL? = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "companion.tvLibraryRoot") ?? "/Volumes/Movies/My/TV Shows")
    @State private var status = "The saved TV library is selected. Audit it, or choose one show folder before searching TVDB."
    @State private var isWorking = false
    @State private var tvAudit: TVLibraryAuditReport?
    @State private var tvAuditFilter = "all"

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
        VStack(alignment: .leading, spacing: 16) {
            Text("Media Manager").font(.largeTitle.weight(.semibold))
            Text("TVDB → Kodi NFO").foregroundStyle(.secondary)
            HStack { Button("Audit saved TV library", action: auditTVFolder).disabled(destination == nil || isWorking); Button("Choose TV show folder…", action: chooseTVFolder).disabled(isWorking); if let destination { Text(destination.path).lineLimit(1).font(.caption).foregroundStyle(.secondary) } }
            HStack { TextField("Search TVDB (suggested from chosen show folder)", text: $query); Button("Search TVDB", action: search).disabled(query.isEmpty || destination == nil || isWorking) }
            if let tvAudit { tvAuditSummary(tvAudit) }
            List(results, id: \.tvdbID) { result in
                HStack { VStack(alignment: .leading) { Text(result.title); Text("TVDB \(result.tvdbID)\(result.year.map { " · \($0)" } ?? "")").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Review selected folder") { if let destination { review(result, in: destination) } }.disabled(isWorking || destination == nil) }
            }
            if !mappings.isEmpty { mappingReview }
            Text(status).font(.callout).foregroundStyle(.secondary).lineLimit(2)
        }.padding(24)
    }

    private func client() throws -> TVDBClient { guard let apiKey = TVDBCredentialStore.value(named: "TVDB_API_KEY"), !apiKey.isEmpty else { throw NSError(domain: "NoSideMMM", code: 1, userInfo: [NSLocalizedDescriptionKey: "Add the TVDB API key in Settings first."]) }; return TVDBClient(credentials: .init(apiKey: apiKey, subscriberPIN: TVDBCredentialStore.value(named: "TVDB_PIN"))) }
    private func search() { isWorking = true; status = "Searching TVDB…"; Task { do { results = try await client().searchSeries(named: query); status = "Found \(results.count) series." } catch { status = error.localizedDescription }; isWorking = false } }
    private func chooseTVFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        destination = url
        tvAudit = nil
        query = url.lastPathComponent.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: #"(?i)season\s*\d+"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        status = "Folder selected. Check the suggested search, then choose the correct TVDB series."
    }
    private func auditTVFolder() { guard let destination else { return }; isWorking = true; status = "Auditing local TV files…"; Task { do { let report = try await TVLibraryAudit.inspect(directory: destination); tvAudit = report; status = "Audited \(report.items.count) videos; \(report.duplicates.count) duplicate episode candidate(s)." } catch { status = error.localizedDescription }; isWorking = false } }
    private func tvAuditSummary(_ audit: TVLibraryAuditReport) -> some View { VStack(alignment: .leading, spacing: 4) { Text("TV audit · \(audit.items.count) videos · \(audit.duplicates.count) duplicate episode candidate(s) · \(audit.unnumberedCount) unnumbered").font(.caption).foregroundStyle(.secondary); Picker("Show", selection: $tvAuditFilter) { Text("All").tag("all"); Text("Multiple copies").tag("duplicates"); Text("Folder season conflicts").tag("conflicts"); Text("Unnumbered").tag("unnumbered") }.pickerStyle(.menu); ScrollView { LazyVStack(alignment: .leading, spacing: 3) { ForEach(filteredTVAuditItems(audit)) { item in Text("\(item.episodeKey ?? "Unnumbered") · \(URL(fileURLWithPath: item.videoPath).lastPathComponent)").font(.caption).foregroundStyle(item.folderSeason.map { $0 != item.season } == true ? .orange : .secondary).lineLimit(1) } } }.frame(maxHeight: 120) } }
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
    private var mappingReview: some View { VStack(alignment: .leading) { Text("Mapping review").font(.headline); List(mappings) { mapping in VStack(alignment: .leading) { HStack { Text(mapping.local.url.lastPathComponent).lineLimit(1); if let count = nfoDifferenceCounts[mapping.local.url], count > 0 { Text("NFO Δ\(count)").foregroundStyle(.orange).font(.caption) }; Toggle("Artwork", isOn: Binding(get: { artworkSelections[mapping.local.url] ?? true }, set: { artworkSelections[mapping.local.url] = $0 })).labelsHidden(); Picker("Canonical episode", selection: Binding(get: { chosenEpisodeIDs[mapping.local.url] ?? mapping.canonical?.tvdbID ?? 0 }, set: { chosenEpisodeIDs[mapping.local.url] = $0 })) { Text("Needs review").tag(0); ForEach(canonicalEpisodes, id: \.tvdbID) { episode in Text("S\(episode.season)E\(episode.number) · \(episode.title)").tag(episode.tvdbID) } }.labelsHidden() }; TextField("Keep location, or enter a full destination video path", text: Binding(get: { destinationPaths[mapping.local.url] ?? mapping.local.url.path }, set: { destinationPaths[mapping.local.url] = $0 })).font(.caption) } }.frame(minHeight: 180); Toggle("Enable selected TVDB episode artwork downloads", isOn: $downloadArtwork); HStack { Button("Export JSON plan…", action: exportPlan).disabled(reviewedSeries == nil); Button("Generate portable job…", action: generateJob).disabled(reviewedSeries == nil || isWorking) }; Text("This Mac only creates a reviewed package; apply.sh changes the library on the target Mac.").font(.caption).foregroundStyle(.secondary) } }
    private func review(_ result: TVSeriesSearchResult, in directory: URL) { isWorking = true; status = "Scanning local files and fetching TVDB episodes…"; Task { do { let source = try client(); let locals = try await EpisodeFolderScanner.scanIncludingEmbeddedMetadata(directory: directory); async let series = source.series(id: result.tvdbID); let episodes = try await source.episodes(forSeriesID: result.tvdbID); canonicalEpisodes = episodes; mappings = EpisodeMappingPlanner.propose(localFiles: locals, canonicalEpisodes: episodes); chosenEpisodeIDs = Dictionary(uniqueKeysWithValues: mappings.compactMap { mapping in mapping.canonical.map { episode in (mapping.local.url, episode.tvdbID) } }); artworkSelections = Dictionary(uniqueKeysWithValues: mappings.map { ($0.local.url, $0.canonical?.artworkURL != nil) }); destinationPaths = Dictionary(uniqueKeysWithValues: mappings.map { ($0.local.url, $0.local.url.path) }); nfoDifferenceCounts = Dictionary(uniqueKeysWithValues: mappings.compactMap { mapping in try? mapping.canonical.map { (mapping.local.url, try NFORepairInspector.differences(at: mapping.local.url.deletingPathExtension().appendingPathExtension("nfo"), comparedTo: $0).count) } }.compactMap { $0 }); reviewedSeries = try await series; status = "Review each mapping before applying." } catch { status = error.localizedDescription }; isWorking = false } }
    private func approved() -> [ApprovedEpisodeMapping] { let index = Dictionary(uniqueKeysWithValues: canonicalEpisodes.map { ($0.tvdbID, $0) }); return mappings.compactMap { mapping in chosenEpisodeIDs[mapping.local.url].flatMap { index[$0] }.map { ApprovedEpisodeMapping(local: mapping.local, canonical: $0, downloadArtwork: artworkSelections[mapping.local.url] ?? false) } } }
    private func renamePlan() throws -> MediaRenamePlan? { let moves = mappings.compactMap { mapping -> MediaRename? in let path = destinationPaths[mapping.local.url] ?? mapping.local.url.path; return path == mapping.local.url.path ? nil : MediaRename(source: mapping.local.url, destination: URL(fileURLWithPath: path)) }; return moves.isEmpty ? nil : try MediaRenamePlan(renames: moves) }
    private func planDocument() -> MappingPlanDocument? { guard let directory = destination, let series = reviewedSeries else { return nil }; return MappingPlanDocument(seriesTVDBID: series.tvdbID, libraryPath: directory.path, entries: mappings.map { MappingPlanDocument.Entry(sourcePath: $0.local.url.path, canonicalEpisodeID: chosenEpisodeIDs[$0.local.url], destinationPath: destinationPaths[$0.local.url], downloadArtwork: artworkSelections[$0.local.url] ?? false) }) }
    private func exportPlan() { guard let plan = planDocument() else { return }; let panel = NSSavePanel(); panel.nameFieldStringValue = "noside-media-plan.json"; guard panel.runModal() == .OK, let url = panel.url else { return }; do { try plan.write(to: url); status = "Plan exported: \(url.lastPathComponent)" } catch { status = error.localizedDescription } }
    private func generateJob() { guard let series = reviewedSeries, let directory = destination else { return }; let selected = approved(); guard !selected.isEmpty else { status = "Select at least one canonical episode."; return }; let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.allowsMultipleSelection = false; panel.message = "Choose where to create the portable job package"; guard panel.runModal() == .OK, let parent = panel.url else { return }; let output = parent.appendingPathComponent("NoSide-MMM-TVDB-\(series.tvdbID)-job", isDirectory: true); let paths = Dictionary(uniqueKeysWithValues: selected.map { mapping in (mapping.local.url, URL(fileURLWithPath: destinationPaths[mapping.local.url] ?? mapping.local.url.path)) }); isWorking = true; status = "Creating a portable job package…"; Task { do { let manifest = try await PortableJobBundle.create(at: output, showRoot: directory, series: series, mappings: selected, destinations: paths, downloadArtwork: downloadArtwork); status = "Job \(manifest.jobID) created. Copy it to the media Mac and dry-run apply.sh." } catch { status = error.localizedDescription }; isWorking = false } }
    private func write(_ result: TVSeriesSearchResult, into directory: URL) { isWorking = true; status = "Fetching \(result.title) and writing NFO files…"; Task { do { let files = try await NFOImportService(source: client()).importSeries(id: result.tvdbID, into: directory); status = "Wrote \(files.count) NFO files to \(directory.lastPathComponent)." } catch { status = error.localizedDescription }; isWorking = false } }
}

@MainActor
private struct MMMSettingsView: View {
    @ObservedObject private var runtime = CompanionRuntime.shared
    @State private var apiKey = TVDBCredentialStore.value(named: "TVDB_API_KEY") ?? ""
    @State private var pin = TVDBCredentialStore.value(named: "TVDB_PIN") ?? ""
    @State private var jobsRoot = UserDefaults.standard.string(forKey: "companion.jobsRoot") ?? "~/NoSideMediaManagerJobs"
    @State private var libraryRoot = UserDefaults.standard.string(forKey: "companion.libraryRoot") ?? ""
    @State private var tvLibraryRoot = UserDefaults.standard.string(forKey: "companion.tvLibraryRoot") ?? "/Volumes/Movies/My/TV Shows"
    @State private var token = UserDefaults.standard.string(forKey: "companion.token") ?? ""
    @State private var port = UserDefaults.standard.string(forKey: "companion.port") ?? "8347"
    @State private var lanVisible = UserDefaults.standard.object(forKey: "companion.lanVisible") as? Bool ?? true
    @State private var status = "Settings are stored on this Mac."
    @State private var showsAPIKey = false
    @State private var showsPIN = false
    @State private var showsToken = false
    var body: some View { VStack(alignment: .leading, spacing: 16) {
        Text("Settings").font(.largeTitle.weight(.semibold)); Text("TVDB is shared by TV work and phone-initiated searches. Keys stay in Keychain.").foregroundStyle(.secondary)
        ConcealedSettingField("TVDB API key", text: $apiKey, isRevealed: $showsAPIKey)
        ConcealedSettingField("TVDB subscriber PIN (optional)", text: $pin, isRevealed: $showsPIN)
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
    private func save() { do { try TVDBCredentialStore.set(apiKey, named: "TVDB_API_KEY"); try TVDBCredentialStore.set(pin, named: "TVDB_PIN"); let d = UserDefaults.standard; d.set(jobsRoot, forKey: "companion.jobsRoot"); d.set(libraryRoot, forKey: "companion.libraryRoot"); d.set(tvLibraryRoot, forKey: "companion.tvLibraryRoot"); d.set(token, forKey: "companion.token"); d.set(port, forKey: "companion.port"); d.set(lanVisible, forKey: "companion.lanVisible"); status = "Saved. Restart Companion to use changed paths, token, or port." } catch { status = error.localizedDescription } }
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
    @State private var working = false
    @State private var confirmApply = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Package Operations").font(.largeTitle.weight(.semibold))
            Text("Packages are the only way microMM changes a media library. Always dry-run first.").foregroundStyle(.secondary)
            HStack { Button("Refresh packages", action: refresh).disabled(working); if let selected { Text(selected.title).lineLimit(1).foregroundStyle(.secondary) } }
            List(jobs, selection: $selected) { job in VStack(alignment: .leading) { Text(job.title); Text("\(job.state == .applied ? "APPLIED · " : job.state == .rolledBack ? "ROLLED BACK · " : "")\(job.moves) moves · \(job.generatedFiles) generated files").font(.caption).foregroundStyle(.secondary) }.tag(job) }
            HStack { Button("Dry-run", action: { run(.dryRun) }).disabled(selected == nil || selected?.state == .applied || working); Button("Apply", role: .destructive) { confirmApply = true }.disabled(selected == nil || selected?.state == .applied || working); Button("Rollback") { run(.rollback) }.disabled(selected?.state != .applied || working) }
            if !log.isEmpty { ScrollView { Text(log).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 160) }
            Text(status).foregroundStyle(.secondary)
        }.padding(24).task { refresh() }.confirmationDialog("Apply this frozen package?", isPresented: $confirmApply, titleVisibility: .visible) { Button("Apply", role: .destructive) { run(.apply) } } message: { Text("This performs the reviewed package on the configured media-library root. A rollback remains available afterward.") }
    }
    private func service() -> CompanionJobService? { let d = UserDefaults.standard; guard let root = d.string(forKey: "companion.libraryRoot"), !root.isEmpty else { return nil }; let jobs = d.string(forKey: "companion.jobsRoot") ?? "~/NoSideMediaManagerJobs"; let token = d.string(forKey: "companion.token") ?? ""; return CompanionJobService(configuration: .init(jobsRoot: URL(fileURLWithPath: jobs), libraryRoot: URL(fileURLWithPath: root), token: token, version: MMMAppRelease.display)) }
    private func refresh() { guard let service = service() else { status = "Set Jobs folder and Movie library root in Settings first."; return }; working = true; Task { jobs = await service.jobs(); selected = jobs.first; status = "Loaded \(jobs.count) frozen package(s)."; working = false } }
    private func run(_ operation: CompanionOperation) { guard let selected, let service = service() else { return }; working = true; Task { do { let result = try await service.run(jobID: selected.id, operation: operation); log = result.log; status = result.succeeded ? "\(operation.rawValue) completed." : "\(operation.rawValue) failed; review the log."; jobs = await service.jobs(); self.selected = jobs.first(where: { $0.id == selected.id }) } catch { status = error.localizedDescription }; working = false } }
}

@MainActor
private struct MovieToolsView: View {
    @State private var folder: URL? = {
        guard let path = UserDefaults.standard.string(forKey: "companion.libraryRoot"), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }()
    @State private var items = [MovieAuditItem]()
    @State private var selectedPaths = Set<String>()
    @State private var auditFilter = "all"
    @State private var status = "The saved Movie library is selected. Audit it, or choose another folder. MMM will not modify it."
    @State private var isWorking = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Movie Manager").font(.largeTitle.weight(.semibold))
            Text("Audit first. Complete movies can be reorganised without rewriting their NFOs or artwork.").foregroundStyle(.secondary)
            HStack { Button("Audit saved Movie library", action: auditCurrentFolder).disabled(folder == nil || isWorking); Button("Choose another folder…", action: chooseFolder).disabled(isWorking); if let folder { Text(folder.path).lineLimit(1).font(.caption).foregroundStyle(.secondary) } }
            Picker("Show", selection: $auditFilter) { Text("All").tag("all"); Text("Needs folder normalisation").tag("needsFolder"); Text("Embedded metadata").tag("embedded"); Text("Incomplete metadata or sidecars").tag("incomplete") }.pickerStyle(.menu)
            List(filteredItems, id: \.videoPath, selection: $selectedPaths) { item in
                VStack(alignment: .leading) {
                    Text(item.nfoTitle ?? URL(fileURLWithPath: item.videoPath).lastPathComponent)
                    Text("\(item.state.rawValue) · \(folderLabel(item.folderState))\(item.editionHint.map { " · \($0)" } ?? "")").font(.caption).foregroundStyle(item.state == .bareNeedsTMDB ? .orange : .secondary)
                }
            }
            HStack {
                Button("Select filtered") { selectedPaths.formUnion(filteredItems.map(\.videoPath)) }.disabled(filteredItems.isEmpty)
                Button("Clear selection") { selectedPaths.removeAll() }.disabled(selectedPaths.isEmpty)
                Spacer()
                Button("Freeze sidecar package…", action: createEmbeddedPackage).disabled(selectedItems(of: .embeddedMetadataNeedsSidecars).isEmpty || isWorking)
                Button("Freeze preservation package…", action: createSelectedPreservationPackage).disabled(!items.contains { selectedPaths.contains($0.videoPath) && $0.isPreservationReady } || isWorking)
            }
            Text("Select any audited items. Sidecar packages accept only files with embedded metadata; preservation packages accept only complete, valid-NFO movies needing folder normalisation. Other selected items are safely ignored.").font(.caption).foregroundStyle(.secondary)
            Text(status).foregroundStyle(.secondary).lineLimit(2)
        }.padding(24)
    }
    private func chooseFolder() { let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; if let folder { panel.directoryURL = folder }; guard panel.runModal() == .OK, let url = panel.url else { return }; folder = url; auditCurrentFolder() }
    private func auditCurrentFolder() { guard let folder else { status = "Set Movie library root in Settings first, or choose another folder."; return }; isWorking = true; status = "Auditing videos and sidecars…"; Task { items = await MovieLibraryAudit.inspect(directory: folder); status = "Audited \(items.count) videos."; isWorking = false } }
    private func selectedItems(of state: MovieSidecarState) -> [MovieAuditItem] { items.filter { selectedPaths.contains($0.videoPath) && $0.state == state } }
    private var filteredItems: [MovieAuditItem] { switch auditFilter { case "needsFolder": items.filter(\.isPreservationReady); case "embedded": items.filter { $0.state == .embeddedMetadataNeedsSidecars }; case "incomplete": items.filter { $0.state != .complete }; default: items } }
    private func folderLabel(_ state: MovieFolderState) -> String { switch state { case .normalized: "folder ready"; case .needsNormalization: "needs folder normalisation"; case .metadataIncomplete: "folder not assessed"; case .sharedMultiPart: "shared multi-part sidecars" } }
    private func createEmbeddedPackage() { guard let folder else { return }; let selected = selectedItems(of: .embeddedMetadataNeedsSidecars); guard !selected.isEmpty else { return }; let output = NSOpenPanel(); output.canChooseDirectories = true; output.canChooseFiles = false; output.canCreateDirectories = true; output.allowsMultipleSelection = false; output.message = "Choose where to create the portable sidecar package"; guard output.runModal() == .OK, let parent = output.url else { return }; isWorking = true; status = "Extracting selected embedded metadata into a portable package…"; Task { do { var approved = [EmbeddedMovieBundleItem](); var missingTitles = [String](); for item in selected { let video = URL(fileURLWithPath: item.videoPath); let metadata = try await MediaFileInspector.extractMovieMetadata(video); guard let title = metadata.title, !title.isEmpty else { missingTitles.append(video.lastPathComponent); continue }; approved.append(.init(source: video, title: title, creationDate: metadata.creationDate, artwork: metadata.artwork)) }; guard missingTitles.isEmpty else { throw NSError(domain: "NoSideMMM", code: 1, userInfo: [NSLocalizedDescriptionKey: "MMM could no longer extract a title from these selected video file(s): \(missingTitles.sorted().joined(separator: ", ")). Re-audit them, or use the TMDB review workflow."]) }; let job = parent.appendingPathComponent("NoSide-MMM-Embedded-Selected-job"); let manifest = try PortableJobBundle.createEmbeddedMovies(at: job, libraryRoot: folder, items: approved); status = "Job \(manifest.jobID) created for \(approved.count) selected movie(s). Dry-run it on the media Mac." } catch { status = error.localizedDescription }; isWorking = false } }
    private func exportPreservationPlan() {
        guard let folder else { return }
        let plan = MoviePlanDocument.preservationProposal(library: folder, items: items)
        guard !plan.entries.isEmpty else { status = "No complete movies with valid TMDB NFOs are ready to preserve."; return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "mmm-movie-preservation-plan.json"; panel.message = "Save the editable preservation plan for review"
        guard panel.runModal() == .OK, let output = panel.url else { return }
        do { try plan.write(to: output); status = "Saved a preservation plan for \(plan.entries.count) movie(s). Review destination paths, then freeze it." } catch { status = error.localizedDescription }
    }
    private func createPreservationPackage() {
        let input = NSOpenPanel(); input.canChooseDirectories = false; input.canChooseFiles = true; input.allowsMultipleSelection = false; input.message = "Choose the reviewed preservation plan"
        guard input.runModal() == .OK, let planURL = input.url else { return }
        let output = NSOpenPanel(); output.canChooseDirectories = true; output.canChooseFiles = false; output.canCreateDirectories = true; output.allowsMultipleSelection = false; output.message = "Choose where to create the portable preservation package"
        guard output.runModal() == .OK, let parent = output.url else { return }
        isWorking = true; status = "Freezing preservation package…"
        Task { do { let plan = try MoviePlanDocument.read(from: planURL); let job = parent.appendingPathComponent("NoSide-MMM-Movie-Preservation-job"); let manifest = try PortableJobBundle.createExistingMoviePreservation(at: job, plan: plan); status = "Job \(manifest.jobID) created. Copy it to the media Mac and dry-run apply.sh." } catch { status = error.localizedDescription }; isWorking = false }
    }
    private func createSelectedPreservationPackage() {
        guard let folder else { return }
        let selected = items.filter { selectedPaths.contains($0.videoPath) && $0.isPreservationReady }
        let plan = MoviePlanDocument.preservationProposal(library: folder, items: selected)
        guard !plan.entries.isEmpty else { status = "Select at least one complete movie that needs folder normalisation."; return }
        let output = NSOpenPanel(); output.canChooseDirectories = true; output.canChooseFiles = false; output.canCreateDirectories = true; output.allowsMultipleSelection = false; output.message = "Choose where to create the portable preservation package"
        guard output.runModal() == .OK, let parent = output.url else { return }
        isWorking = true; status = "Freezing preservation package for \(plan.entries.count) selected movie(s)…"
        Task { do { let job = parent.appendingPathComponent("NoSide-MMM-Movie-Preservation-Selected-job"); let manifest = try PortableJobBundle.createExistingMoviePreservation(at: job, plan: plan); status = "Job \(manifest.jobID) created for \(plan.entries.count) selected movie(s). Dry-run it on the media Mac." } catch { status = error.localizedDescription }; isWorking = false }
    }
}
