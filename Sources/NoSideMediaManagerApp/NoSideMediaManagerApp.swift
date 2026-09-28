import SwiftUI
import NoSideMediaManager
import NoSideMediaCompanionCore

@main
struct NoSideMediaManagerApp: App {
    var body: some Scene { WindowGroup { ContentView().frame(minWidth: 620, minHeight: 420) } }
}

@MainActor
private struct ContentView: View {
    @State private var apiKey = ""
    @State private var pin = ""
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
    @State private var destination: URL?
    @State private var status = "Enter a TVDB key and search for a series."
    @State private var isWorking = false

    var body: some View { TabView { tvScreen.tabItem { Text("TV") }; MovieToolsView().tabItem { Text("Movies") }; CompanionServerView().tabItem { Text("Companion") } } }

    private var tvScreen: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Media Manager").font(.largeTitle.weight(.semibold))
            Text("TVDB → Kodi NFO").foregroundStyle(.secondary)
            HStack { TextField("TVDB API key", text: $apiKey); SecureField("Subscriber PIN (optional)", text: $pin) }
            HStack { TextField("Find a series", text: $query); Button("Search", action: search).disabled(query.isEmpty || apiKey.isEmpty || isWorking) }
            List(results, id: \.tvdbID) { result in
                HStack { VStack(alignment: .leading) { Text(result.title); Text("TVDB \(result.tvdbID)\(result.year.map { " · \($0)" } ?? "")").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Review folder…") { chooseDestination(for: result) }.disabled(isWorking) }
            }
            if !mappings.isEmpty { mappingReview }
            Text(status).font(.callout).foregroundStyle(.secondary).lineLimit(2)
        }.padding(24)
    }

    private func client() -> TVDBClient { TVDBClient(credentials: .init(apiKey: apiKey, subscriberPIN: pin)) }
    private func search() { isWorking = true; status = "Searching TVDB…"; Task { do { results = try await client().searchSeries(named: query); status = "Found \(results.count) series." } catch { status = error.localizedDescription }; isWorking = false } }
    private func chooseDestination(for result: TVSeriesSearchResult) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        destination = url; review(result, in: url)
    }
    private var mappingReview: some View { VStack(alignment: .leading) { Text("Mapping review").font(.headline); List(mappings) { mapping in VStack(alignment: .leading) { HStack { Text(mapping.local.url.lastPathComponent).lineLimit(1); if let count = nfoDifferenceCounts[mapping.local.url], count > 0 { Text("NFO Δ\(count)").foregroundStyle(.orange).font(.caption) }; Toggle("Artwork", isOn: Binding(get: { artworkSelections[mapping.local.url] ?? true }, set: { artworkSelections[mapping.local.url] = $0 })).labelsHidden(); Picker("Canonical episode", selection: Binding(get: { chosenEpisodeIDs[mapping.local.url] ?? mapping.canonical?.tvdbID ?? 0 }, set: { chosenEpisodeIDs[mapping.local.url] = $0 })) { Text("Needs review").tag(0); ForEach(canonicalEpisodes, id: \.tvdbID) { episode in Text("S\(episode.season)E\(episode.number) · \(episode.title)").tag(episode.tvdbID) } }.labelsHidden() }; TextField("Keep location, or enter a full destination video path", text: Binding(get: { destinationPaths[mapping.local.url] ?? mapping.local.url.path }, set: { destinationPaths[mapping.local.url] = $0 })).font(.caption) } }.frame(minHeight: 180); Toggle("Enable selected TVDB episode artwork downloads", isOn: $downloadArtwork); HStack { Button("Export JSON plan…", action: exportPlan).disabled(reviewedSeries == nil); Button("Generate portable job…", action: generateJob).disabled(reviewedSeries == nil || isWorking) }; Text("This Mac only creates a reviewed package; apply.sh changes the library on the target Mac.").font(.caption).foregroundStyle(.secondary) } }
    private func review(_ result: TVSeriesSearchResult, in directory: URL) { isWorking = true; status = "Scanning local files and fetching TVDB episodes…"; Task { do { let locals = try await EpisodeFolderScanner.scanIncludingEmbeddedMetadata(directory: directory); async let series = client().series(id: result.tvdbID); let episodes = try await client().episodes(forSeriesID: result.tvdbID); canonicalEpisodes = episodes; mappings = EpisodeMappingPlanner.propose(localFiles: locals, canonicalEpisodes: episodes); chosenEpisodeIDs = Dictionary(uniqueKeysWithValues: mappings.compactMap { mapping in mapping.canonical.map { episode in (mapping.local.url, episode.tvdbID) } }); artworkSelections = Dictionary(uniqueKeysWithValues: mappings.map { ($0.local.url, $0.canonical?.artworkURL != nil) }); destinationPaths = Dictionary(uniqueKeysWithValues: mappings.map { ($0.local.url, $0.local.url.path) }); nfoDifferenceCounts = Dictionary(uniqueKeysWithValues: mappings.compactMap { mapping in try? mapping.canonical.map { (mapping.local.url, try NFORepairInspector.differences(at: mapping.local.url.deletingPathExtension().appendingPathExtension("nfo"), comparedTo: $0).count) } }.compactMap { $0 }); reviewedSeries = try await series; status = "Review each mapping before applying." } catch { status = error.localizedDescription }; isWorking = false } }
    private func approved() -> [ApprovedEpisodeMapping] { let index = Dictionary(uniqueKeysWithValues: canonicalEpisodes.map { ($0.tvdbID, $0) }); return mappings.compactMap { mapping in chosenEpisodeIDs[mapping.local.url].flatMap { index[$0] }.map { ApprovedEpisodeMapping(local: mapping.local, canonical: $0, downloadArtwork: artworkSelections[mapping.local.url] ?? false) } } }
    private func renamePlan() throws -> MediaRenamePlan? { let moves = mappings.compactMap { mapping -> MediaRename? in let path = destinationPaths[mapping.local.url] ?? mapping.local.url.path; return path == mapping.local.url.path ? nil : MediaRename(source: mapping.local.url, destination: URL(fileURLWithPath: path)) }; return moves.isEmpty ? nil : try MediaRenamePlan(renames: moves) }
    private func planDocument() -> MappingPlanDocument? { guard let directory = destination, let series = reviewedSeries else { return nil }; return MappingPlanDocument(seriesTVDBID: series.tvdbID, libraryPath: directory.path, entries: mappings.map { MappingPlanDocument.Entry(sourcePath: $0.local.url.path, canonicalEpisodeID: chosenEpisodeIDs[$0.local.url], destinationPath: destinationPaths[$0.local.url], downloadArtwork: artworkSelections[$0.local.url] ?? false) }) }
    private func exportPlan() { guard let plan = planDocument() else { return }; let panel = NSSavePanel(); panel.nameFieldStringValue = "noside-media-plan.json"; guard panel.runModal() == .OK, let url = panel.url else { return }; do { try plan.write(to: url); status = "Plan exported: \(url.lastPathComponent)" } catch { status = error.localizedDescription } }
    private func generateJob() { guard let series = reviewedSeries, let directory = destination else { return }; let selected = approved(); guard !selected.isEmpty else { status = "Select at least one canonical episode."; return }; let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.allowsMultipleSelection = false; panel.message = "Choose where to create the portable job package"; guard panel.runModal() == .OK, let parent = panel.url else { return }; let output = parent.appendingPathComponent("NoSide-MMM-TVDB-\(series.tvdbID)-job", isDirectory: true); let paths = Dictionary(uniqueKeysWithValues: selected.map { mapping in (mapping.local.url, URL(fileURLWithPath: destinationPaths[mapping.local.url] ?? mapping.local.url.path)) }); isWorking = true; status = "Creating a portable job package…"; Task { do { let manifest = try await PortableJobBundle.create(at: output, showRoot: directory, series: series, mappings: selected, destinations: paths, downloadArtwork: downloadArtwork); status = "Job \(manifest.jobID) created. Copy it to the media Mac and dry-run apply.sh." } catch { status = error.localizedDescription }; isWorking = false } }
    private func write(_ result: TVSeriesSearchResult, into directory: URL) { isWorking = true; status = "Fetching \(result.title) and writing NFO files…"; Task { do { let files = try await NFOImportService(source: client()).importSeries(id: result.tvdbID, into: directory); status = "Wrote \(files.count) NFO files to \(directory.lastPathComponent)." } catch { status = error.localizedDescription }; isWorking = false } }
}

@MainActor
private struct CompanionServerView: View {
    @State private var jobsRoot = "~/NoSideMediaManagerJobs"
    @State private var libraryRoot = ""
    @State private var token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    @State private var port = "8347"
    @State private var lanVisible = true
    @State private var server: CompanionHTTPServer?
    @State private var status = "Configure the old MBA paths, then start the authenticated Companion."
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MMM Companion").font(.largeTitle.weight(.semibold))
            Text("Runs inside this MMM Mac app. It exposes jobs—not a general file share.").foregroundStyle(.secondary)
            pathField("Jobs directory", value: $jobsRoot)
            pathField("Library root for these jobs", value: $libraryRoot)
            HStack { SecureField("Pairing token", text: $token); Button("New token") { token = UUID().uuidString.replacingOccurrences(of: "-", with: "") }; Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(token, forType: .string) } }
            HStack { TextField("Port", text: $port).frame(width: 90); Toggle("Allow devices on local network", isOn: $lanVisible); Spacer(); Button(server == nil ? "Start Companion" : "Stop Companion", action: toggle).disabled(server == nil && (libraryRoot.isEmpty || token.isEmpty)) }
            GroupBox("Phone pairing") { VStack(alignment: .leading, spacing: 6) { Text("Enter this Mac’s local IP address, port, and pairing token in the iOS app."); Text("Apply requires a second confirmation carrying the exact job ID. Keep this on your trusted home network or VPN.").font(.caption).foregroundStyle(.secondary) } }
            Text(status).foregroundStyle(.secondary).lineLimit(3)
            Spacer()
        }.padding(24)
    }
    private func pathField(_ label: String, value: Binding<String>) -> some View { HStack { TextField(label, text: value); Button("Choose…") { let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; if panel.runModal() == .OK, let url = panel.url { value.wrappedValue = url.path } } } }
    private func toggle() { if let server { server.stop(); self.server = nil; status = "Companion stopped."; return }; guard let number = UInt16(port), !jobsRoot.isEmpty, !libraryRoot.isEmpty else { status = "Enter a valid port and both directory paths."; return }; do { let config = CompanionConfiguration(jobsRoot: URL(fileURLWithPath: jobsRoot), libraryRoot: URL(fileURLWithPath: libraryRoot), token: token, version: "0.3.1"); let server = CompanionHTTPServer(service: CompanionJobService(configuration: config), token: token); try server.start(port: number, lanVisible: lanVisible); self.server = server; status = "Companion started on port \(number). \(lanVisible ? "LAN access is enabled." : "Loopback only.")" } catch { status = error.localizedDescription } }
}

@MainActor
private struct MovieToolsView: View {
    @State private var folder: URL?
    @State private var items = [MovieAuditItem]()
    @State private var selectedPath: String?
    @State private var status = "Choose a movie folder to audit. MMM will not modify it."
    @State private var isWorking = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Movie Manager").font(.largeTitle.weight(.semibold))
            Text("Audit embedded metadata first; use TMDB only for bare files.").foregroundStyle(.secondary)
            HStack { Button("Choose and audit folder…", action: chooseFolder).disabled(isWorking); if let folder { Text(folder.path).lineLimit(1).font(.caption).foregroundStyle(.secondary) } }
            List(items, id: \.videoPath, selection: $selectedPath) { item in
                VStack(alignment: .leading) { Text(URL(fileURLWithPath: item.videoPath).lastPathComponent); Text(item.state.rawValue + (item.editionHint.map { " · \($0)" } ?? "")).font(.caption).foregroundStyle(item.state == .bareNeedsTMDB ? .orange : .secondary) }
            }
            HStack { Button("Create embedded sidecar package…", action: createEmbeddedPackage).disabled(items.first { $0.videoPath == selectedPath }?.state != .embeddedMetadataNeedsSidecars || isWorking); Text("Bare items require an explicit TMDB match in the CLI review flow.").font(.caption).foregroundStyle(.secondary) }
            Text(status).foregroundStyle(.secondary).lineLimit(2)
        }.padding(24)
    }
    private func chooseFolder() { let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; guard panel.runModal() == .OK, let url = panel.url else { return }; folder = url; isWorking = true; status = "Auditing videos and sidecars…"; Task { items = await MovieLibraryAudit.inspect(directory: url); status = "Audited \(items.count) videos."; isWorking = false } }
    private func createEmbeddedPackage() { guard let folder, let selected = items.first(where: { $0.videoPath == selectedPath }) else { return }; let output = NSOpenPanel(); output.canChooseDirectories = true; output.canChooseFiles = false; output.canCreateDirectories = true; output.allowsMultipleSelection = false; output.message = "Choose where to create the portable job"; guard output.runModal() == .OK, let parent = output.url else { return }; isWorking = true; status = "Extracting embedded metadata into a portable package…"; Task { do { let video = URL(fileURLWithPath: selected.videoPath); let metadata = try await MediaFileInspector.extractMovieMetadata(video); guard let title = metadata.title, !title.isEmpty else { throw NSError(domain: "NoSideMMM", code: 1, userInfo: [NSLocalizedDescriptionKey: "This container has no extractable title; use the TMDB review flow."]) }; let job = parent.appendingPathComponent("NoSide-MMM-Embedded-\(video.deletingPathExtension().lastPathComponent)-job"); let manifest = try PortableJobBundle.createEmbeddedMovie(at: job, libraryRoot: folder, source: video, title: title, creationDate: metadata.creationDate, artwork: metadata.artwork); status = "Job \(manifest.jobID) created. Copy it to the media Mac and dry-run apply.sh." } catch { status = error.localizedDescription }; isWorking = false } }
}
