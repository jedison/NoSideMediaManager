import SwiftUI

struct CompanionRootView: View {
    @EnvironmentObject private var session: CompanionSession
    @State private var isShowingInfo = false
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            Group { if session.server == nil { PairingView() } else { JobListView() } }
                .navigationTitle("microMM")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { isShowingInfo = true } label: {
                            Image(systemName: "info.circle")
                        }
                        .accessibilityLabel("How microMM works")
                        .accessibilityIdentifier("micromm.home.info")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { isShowingSettings = true } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                        .accessibilityIdentifier("micromm.home.settings")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        }
        .sheet(isPresented: $isShowingInfo) {
            NavigationStack {
                CompanionInfoView()
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { isShowingInfo = false } } }
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            NavigationStack {
                CompanionSettingsView()
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { isShowingSettings = false } } }
            }
        }
        .task { if !session.host.isEmpty && !session.token.isEmpty { await session.refresh() } }
    }
}

private struct PairingView: View {
    @EnvironmentObject private var session: CompanionSession
    var body: some View {
        List {
            Section("Connect microMM") {
                Text("Enter the media server address and pairing token in Settings, then connect.")
                NavigationLink("Open Settings", destination: CompanionSettingsView())
            }
            Section("Safety") {
                Text("The phone can request and review frozen jobs. It does not receive direct disk access or make unreviewed library changes.")
                    .foregroundStyle(.secondary)
            }
            Text(session.status).foregroundStyle(.secondary)
        }.navigationTitle("Connect")
    }
}

private struct CompanionSettingsView: View {
    @EnvironmentObject private var session: CompanionSession

    var body: some View {
        Form {
            Section("microMM connection") {
                TextField("Media server address", text: $session.host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Port", text: Binding(get: { String(session.port) }, set: { session.port = Int($0) ?? session.port }))
                    .keyboardType(.numberPad)
                SecureField("Pairing token", text: $session.token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section {
                Button("Connect") {
                    session.save()
                    Task { await session.refresh() }
                }
                // A stalled or in-flight network refresh must not trap the
                // user behind a disabled Connect button. They can retry using
                // the saved values; refresh itself serialises its state.
                .disabled(session.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section("Status") {
                Text(session.status).foregroundStyle(.secondary)
                if let server = session.server {
                    LabeledContent("Media server microMM", value: server.version)
                }
            }
            Section {
                Text("Connection details stay on this iPhone. The pairing token authorizes the companion service, not filesystem access.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .onDisappear { session.save() }
    }
}

private enum CompanionBuildVersion {
    static let label: String = {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        guard let url = bundle.url(forResource: "MMMBuildInfo", withExtension: "plist"),
              let values = NSDictionary(contentsOf: url) as? [String: String],
              let sequence = values["sequence"], let timestamp = values["timestamp"] else {
            return "v\(version) (\(build))"
        }
        return "v\(values["version"] ?? version) (\(values["bundleBuild"] ?? build)) • build \(sequence) • \(timestamp)"
    }()
}

private struct CompanionInfoView: View {
    @EnvironmentObject private var session: CompanionSession

    var body: some View {
        List {
            Section("How it works") {
                Label("Connect this iPhone to microMM on the media server with its address and pairing token.", systemImage: "1.circle.fill")
                Label("Audit, search, and choose items for a frozen package.", systemImage: "2.circle.fill")
                Label("Review dry-run, apply, and rollback results from the job detail.", systemImage: "3.circle.fill")
            }
            Section("Important") {
                Text("microMM on the phone does not directly change the media library. All library changes remain in reviewed, rollbackable packages on the media server.")
                    .foregroundStyle(.secondary)
            }
            Section("About") {
                LabeledContent("iPhone app", value: CompanionBuildVersion.label)
                LabeledContent("Media server microMM", value: session.server?.version ?? "Not connected")
            }
        }
        .navigationTitle("How microMM works")
    }
}

private struct JobListView: View {
    @EnvironmentObject private var session: CompanionSession
    var body: some View {
        List {
            Section { NavigationLink("Remote audit & TVDB search", destination: RemoteToolsView()) }
            Section {
                Text(session.status).font(.footnote).foregroundStyle(.secondary)
                Button { Task { await session.refresh() } } label: { Label("Refresh jobs", systemImage: "arrow.clockwise") }
                    .disabled(session.isLoading)
            }
            ForEach(session.jobs) { job in
                NavigationLink(destination: JobDetailView(job: job)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.title)
                        Text(jobSummary(job)).font(.caption).foregroundStyle(.secondary)
                        if let createdAt = job.createdAt { Text(createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
        }.refreshable { await session.refresh() }
            .overlay { if session.isLoading { ProgressView() } }
    }

    private func jobSummary(_ job: CompanionJob) -> String {
        let applied = job.state == .applied ? "APPLIED · " : job.state == .rolledBack ? "ROLLED BACK · " : ""
        return "\(applied)\(job.mediaKind.uppercased()) · \(job.provider.uppercased()) · \(job.moves) moves · \(job.generatedFiles) sidecars"
    }
}

private struct RemoteToolsView: View {
    @EnvironmentObject private var session: CompanionSession
    var body: some View {
        List {
            Section("Library tools") {
                NavigationLink("Movie audit", destination: MovieAuditView())
                NavigationLink("TV shows", destination: TVToolsView())
            }
            Section("Safety") {
                Text("Audits and reviews only read the media library. Changes are made later through reviewed frozen packages.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Remote tools")
        .task { await session.refreshMovieAuditStatus() }
    }
}

private struct MovieAuditView: View {
    @EnvironmentObject private var session: CompanionSession
    @State private var selectedPaths = Set<String>()
    @State private var auditFilter = "all"
    @State private var packageKind = ""
    @State private var confirmPackage = false
    @State private var confirmNewMovieAudit = false
    @State private var status = "Review the media-server audit, then select eligible movies to freeze a package."
    @State private var working = false
    @State private var errorMessage: String?
    var body: some View { List {
        Section("Movie library") {
            if session.movieAuditProgress?.phase == "complete" {
                Button("Run new movie audit…") { confirmNewMovieAudit = true }.disabled(working || session.isMovieAuditLoading)
            } else {
                Button(session.movieAuditProgress?.phase == "running" ? "Movie audit already running" : "Audit configured movie/library root") { session.startMovieAudit() }.disabled(working || session.isMovieAuditLoading)
            }
            if session.isMovieAuditLoading { ProgressView("Auditing on the media server…") }
            Text(session.movieAuditStatus).font(.footnote).foregroundStyle(.secondary)
            if let progress = session.movieAuditProgress, progress.phase == "running" {
                ProgressView(value: Double(progress.completedVideos), total: Double(max(progress.totalVideos, 1))) { Text(progress.totalVideos == 0 ? "Finding video files…" : "\(progress.completedVideos) of \(progress.totalVideos) video files audited") }.progressViewStyle(.linear)
                if let started = progress.startedAt { TimelineView(.periodic(from: .now, by: 1)) { context in Text("Elapsed \(elapsedTime(since: started, now: context.date))").font(.footnote).foregroundStyle(.secondary) } }
            }
            if let audit = session.movieAudit {
                Text("\(audit.totalVideos) videos · \(audit.ignoredVideos ?? 0) ignored extras · \(audit.invalidNFOs) invalid NFOs")
                ForEach(audit.byFolderState.sorted(by: { $0.key < $1.key }), id: \.key) { Text("\($0.key): \($0.value)") }
                let normalisationCount = audit.items.filter(\.preservationReady).count
                let multiPartCount = audit.items.filter(\.isMultiPart).count
                let embeddedCount = audit.items.filter { $0.sidecarReady && !$0.isMultiPart }.count
                let incompleteCount = audit.items.filter { $0.state != "complete" && !$0.isMultiPart }.count
                if multiPartCount > 0 { Button("\(multiPartCount) shared multi-part video\(multiPartCount == 1 ? "" : "s")") { auditFilter = "multipart" }.foregroundStyle(.orange) }
                Picker("Show", selection: $auditFilter) {
                    Text("All (\(audit.items.count))").tag("all")
                    Text("Needs folder normalisation (\(normalisationCount))").tag("needsFolder")
                    Text("Shared multi-part movies (\(multiPartCount))").tag("multipart")
                    Text("Embedded metadata (\(embeddedCount))").tag("embedded")
                    Text("Incomplete metadata or sidecars (\(incompleteCount))").tag("incomplete")
                }
                Text("\(selectedPaths.count) selected").font(.footnote).foregroundStyle(.secondary)
                Button("Freeze selected sidecar package") { packageKind = "sidecar"; confirmPackage = true }.disabled(!audit.items.contains { selectedPaths.contains($0.videoPath) && $0.sidecarReady } || working)
                Button("Freeze selected preservation package") { packageKind = "preservation"; confirmPackage = true }.disabled(!audit.items.contains { selectedPaths.contains($0.videoPath) && $0.preservationReady } || working)
                Button("Freeze selected multi-part package") { packageKind = "multipart"; confirmPackage = true }.disabled(!audit.items.contains { selectedPaths.contains($0.videoPath) && $0.multiPartReady } || working)
            }
            Text(status).font(.footnote).foregroundStyle(.secondary)
        }
        if let audit = session.movieAudit { Section("Audited movies") { ForEach(filteredAuditItems(from: audit)) { item in Toggle(isOn: Binding(get: { selectedPaths.contains(item.videoPath) }, set: { if $0 { selectedPaths.insert(item.videoPath) } else { selectedPaths.remove(item.videoPath) } })) { VStack(alignment: .leading) { Text(item.nfoTitle ?? URL(fileURLWithPath: item.videoPath).deletingPathExtension().lastPathComponent); Text("\(item.state) · \(item.folderState)").font(.caption).foregroundStyle(item.preservationReady || item.multiPartReady ? .orange : .secondary); if item.multiPartReady { Text(URL(fileURLWithPath: item.videoPath).lastPathComponent).font(.caption2).foregroundStyle(.secondary) } } } } } }
    }.navigationTitle("Movie audit").toolbar { ToolbarItem(placement: .topBarTrailing) { Menu { Button("Select all shown") { if let audit = session.movieAudit { selectedPaths.formUnion(filteredAuditItems(from: audit).map(\.videoPath)) } }; Button("Clear selection", role: .destructive) { selectedPaths.removeAll() } } label: { Image(systemName: "checklist") }.disabled(session.movieAudit == nil) } }.task { await session.refreshMovieAuditStatus() }.confirmationDialog("Create frozen package?", isPresented: $confirmPackage, titleVisibility: .visible) { Button("Create package") { freezeSelected() } } message: { Text("This creates a reviewed package on the media server. It does not modify the media library.") }.confirmationDialog("Run a new movie audit?", isPresented: $confirmNewMovieAudit, titleVisibility: .visible) { Button("Run new audit") { session.startMovieAudit() } } message: { Text("The previous audit remains visible until the new media-server audit completes. This only reads the library.") }.alert("Couldn’t create package", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "Unknown error") } }
    private func freezeSelected() { guard let audit = session.movieAudit else { return }; let eligible = audit.items.filter { selectedPaths.contains($0.videoPath) && (packageKind == "sidecar" ? $0.sidecarReady : packageKind == "multipart" ? $0.multiPartReady : $0.preservationReady) }; guard !eligible.isEmpty else { return }; working = true; Task { defer { working = false }; do { let job = try await session.client.freezeMoviePackage(packageKind, videoPaths: eligible.map(\.videoPath)); status = "Frozen job \(job.id) created for \(eligible.count) selected movie(s)."; await session.refresh() } catch { status = error.localizedDescription; errorMessage = error.localizedDescription } } }
    private func filteredAuditItems(from audit: CompanionMovieAuditReport) -> [CompanionMovieAuditItem] { switch auditFilter { case "needsFolder": audit.items.filter(\.preservationReady); case "multipart": audit.items.filter(\.isMultiPart); case "embedded": audit.items.filter { $0.sidecarReady && !$0.isMultiPart }; case "incomplete": audit.items.filter { $0.state != "complete" && !$0.isMultiPart }; default: audit.items } }
    private func elapsedTime(since start: Date, now: Date) -> String { let seconds = max(0, Int(now.timeIntervalSince(start))); return String(format: "%d:%02d", seconds / 60, seconds % 60) }
}

private struct TVToolsView: View {
    @EnvironmentObject private var session: CompanionSession
    @State private var query = ""
    @State private var results = [TVSeriesSearchResult]()
    @State private var tvFolders = [CompanionTVFolder]()
    @State private var selectedTVFolder = ""
    @State private var selectedTVSeries: TVSeriesSearchResult?
    @State private var tvAudit: CompanionTVAuditReport?
    @State private var tvReview: CompanionTVMappingReview?
    @State private var status = "These requests run on the media server and do not change media files."
    @State private var working = false
    var body: some View { List {
        Section("TVDB") { TextField("Search series", text: $query); Button("Search TVDB") { runSearch() }.disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || working); ForEach(results) { result in Button { selectedTVSeries = result; tvReview = nil; status = "Selected \(result.title). Choose its local show folder, then review the proposed episode mappings." } label: { HStack { VStack(alignment: .leading) { Text(result.title); Text("TVDB \(result.tvdbID)\(result.year.map { " · \($0)" } ?? "")").font(.caption).foregroundStyle(.secondary) }; Spacer(); if selectedTVSeries?.tvdbID == result.tvdbID { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) } } } } }
        Section("TV library") { Button("Load TV show folders") { loadTVFolders() }.disabled(working); if !tvFolders.isEmpty { Picker("Show folder", selection: $selectedTVFolder) { Text("Choose a show").tag(""); ForEach(tvFolders) { Text($0.name).tag($0.name) } }; Button("Audit selected TV folder") { runTVAudit() }.disabled(selectedTVFolder.isEmpty || working); Button("Search TVDB from folder") { query = selectedTVFolder; runSearch() }.disabled(selectedTVFolder.isEmpty || working); if let series = selectedTVSeries { Button("Review \(series.title) against this folder") { runTVReview(series) }.disabled(selectedTVFolder.isEmpty || working) } }; if let tvAudit { Text("\(tvAudit.folder): \(tvAudit.report.items.count) videos · \(tvAudit.report.duplicates.count) duplicate episode candidate(s) · \(tvAudit.report.unnumberedCount) unnumbered").font(.caption); ForEach(tvAudit.report.duplicates) { duplicate in Text("S\(duplicate.season)E\(duplicate.episode): \(duplicate.videoPaths.count) copies").font(.caption).foregroundStyle(.orange) } } }
        if let review = tvReview { Section("TV mapping review · \(review.seriesTitle)") { Text("\(review.mappings.count) files · \(review.unmatchedCount) need an explicit episode choice").font(.caption).foregroundStyle(review.unmatchedCount > 0 ? .orange : .secondary); ForEach(review.mappings) { mapping in VStack(alignment: .leading) { Text(URL(fileURLWithPath: mapping.videoPath).lastPathComponent).lineLimit(1); Text(mapping.proposedEpisode.map { "S\($0.season)E\($0.episode) · \($0.title)" } ?? "Needs explicit episode choice").font(.caption).foregroundStyle(mapping.proposedEpisode == nil ? .orange : .secondary) } }; Text("This is a review only. The Mac app remains the place to make explicit episode choices and freeze the TV package.").font(.footnote).foregroundStyle(.secondary) } }
        Section { Text(status).font(.footnote).foregroundStyle(.secondary) }
    }.navigationTitle("TV shows") }
    private func runSearch() { working = true; Task { defer { working = false }; do { results = try await session.client.searchTV(query); status = "Found \(results.count) series." } catch { status = error.localizedDescription } } }
    private func loadTVFolders() { working = true; Task { defer { working = false }; do { tvFolders = try await session.client.tvFolders(); status = "Loaded \(tvFolders.count) TV show folders." } catch { status = error.localizedDescription } } }
    private func runTVAudit() { working = true; Task { defer { working = false }; do { tvAudit = try await session.client.tvAudit(folder: selectedTVFolder); status = "TV audit complete." } catch { status = error.localizedDescription } } }
    private func runTVReview(_ series: TVSeriesSearchResult) { working = true; Task { defer { working = false }; do { tvReview = try await session.client.reviewTV(seriesID: series.tvdbID, folder: selectedTVFolder); status = "TV mapping review complete." } catch { status = error.localizedDescription } } }
}

private struct JobDetailView: View {
    @EnvironmentObject private var session: CompanionSession
    let job: CompanionJob
    @State private var result: CompanionOperationResult?
    @State private var showApply = false
    @State private var isWorking = false
    var body: some View {
        List {
            Section("Frozen job") {
                LabeledContent("Status", value: job.state == .applied ? "Applied" : job.state == .rolledBack ? "Rolled back" : "Ready"); LabeledContent("Provider", value: job.provider.uppercased()); LabeledContent("Moves", value: String(job.moves)); LabeledContent("Generated files", value: String(job.generatedFiles))
                if job.unavailableArtwork > 0 { LabeledContent("Unavailable artwork", value: String(job.unavailableArtwork)) }
            }
            Section("Package operations") { Button("Dry run") { run(.dryRun) }.disabled(isWorking || job.state == .applied); Button("Apply", role: .destructive) { showApply = true }.disabled(isWorking || job.state == .applied); Button("Rollback") { run(.rollback) }.disabled(isWorking || job.state != .applied) }
            if let result { Section("\(result.operation.rawValue) result") { Text(result.log.isEmpty ? "No output." : result.log).font(.system(.caption, design: .monospaced)).textSelection(.enabled); Text(result.succeeded ? "Completed." : "Failed; review the log before proceeding.").foregroundStyle(result.succeeded ? Color.secondary : Color.red) } }
        }.navigationTitle(job.title)
            .confirmationDialog("Apply this frozen job?", isPresented: $showApply, titleVisibility: .visible) { Button("Apply \(job.title)", role: .destructive) { run(.apply) } } message: { Text("This runs the exact reviewed package on the media server. Review its dry-run result first; rollback remains available after apply.") }
    }
    private func run(_ operation: CompanionOperation) { isWorking = true; Task { defer { isWorking = false }; do { result = try await session.client.run(job, operation: operation) } catch { result = CompanionOperationResult(jobID: job.id, operation: operation, succeeded: false, log: error.localizedDescription) } } }
}
