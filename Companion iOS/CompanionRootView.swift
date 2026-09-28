import SwiftUI

struct CompanionRootView: View {
    @EnvironmentObject private var session: CompanionSession
    var body: some View {
        NavigationStack {
            Group { if session.server == nil { PairingView() } else { JobListView() } }
                .navigationTitle("microMM")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink(destination: PairingView()) { Image(systemName: "gear") } } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        }.task { if !session.host.isEmpty && !session.token.isEmpty { await session.refresh() } }
    }
}

private struct PairingView: View {
    @EnvironmentObject private var session: CompanionSession
    var body: some View {
        Form {
            Section("microMM") {
                TextField("Old MBA address", text: $session.host).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Port", text: Binding(get: { String(session.port) }, set: { session.port = Int($0) ?? session.port })).keyboardType(.numberPad)
                SecureField("Pairing token", text: $session.token)
            }
            Section { Button("Connect") { session.save(); Task { await session.refresh() } }.disabled(session.host.isEmpty || session.token.isEmpty) }
            Section { Text("Start microMM on the old MBA, then copy its pairing token here. The phone controls frozen jobs; it never receives direct disk access.").font(.footnote).foregroundStyle(.secondary) }
            Text(session.status).foregroundStyle(.secondary)
        }.navigationTitle("Pair microMM")
    }
}

private struct JobListView: View {
    @EnvironmentObject private var session: CompanionSession
    var body: some View {
        List {
            Section { Text(session.status).font(.footnote).foregroundStyle(.secondary) }
            Section { NavigationLink("Remote audit & TVDB search", destination: RemoteToolsView()) }
            ForEach(session.jobs) { job in
                NavigationLink(value: job) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.title)
                        Text("\(job.state == .applied ? "APPLIED · " : "")\(job.mediaKind.uppercased()) · \(job.provider.uppercased()) · \(job.moves) moves · \(job.generatedFiles) sidecars").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.navigationDestination(for: CompanionJob.self) { JobDetailView(job: $0) }
        }.refreshable { await session.refresh() }
            .overlay { if session.isLoading { ProgressView() } }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { Task { await session.refresh() } } label: { Image(systemName: "arrow.clockwise") } } }
    }
}

private struct RemoteToolsView: View {
    @EnvironmentObject private var session: CompanionSession
    @State private var query = ""
    @State private var results = [TVSeriesSearchResult]()
    @State private var audit: CompanionMovieAuditReport?
    @State private var selectedPaths = Set<String>()
    @State private var auditFilter = "all"
    @State private var packageKind = ""
    @State private var confirmPackage = false
    @State private var status = "These requests run on the old MBA and do not change media files."
    @State private var working = false
    var body: some View { List {
        Section("Movie library") {
            Button("Audit configured movie/library root") { runAudit() }.disabled(working)
            if let audit {
                Text("\(audit.totalVideos) videos · \(audit.invalidNFOs) invalid NFOs")
                ForEach(audit.byFolderState.sorted(by: { $0.key < $1.key }), id: \.key) { Text("\($0.key): \($0.value)") }
                Picker("Show", selection: $auditFilter) { Text("All").tag("all"); Text("Needs folder normalisation").tag("needsFolder"); Text("Embedded metadata").tag("embedded"); Text("Incomplete").tag("incomplete") }
                HStack { Button("Select filtered") { selectedPaths.formUnion(filteredAuditItems(from: audit).map(\.videoPath)) }; Button("Clear") { selectedPaths.removeAll() } }
                Button("Freeze selected sidecar package") { packageKind = "sidecar"; confirmPackage = true }.disabled(!audit.items.contains { selectedPaths.contains($0.videoPath) && $0.sidecarReady } || working)
                Button("Freeze selected preservation package") { packageKind = "preservation"; confirmPackage = true }.disabled(!audit.items.contains { selectedPaths.contains($0.videoPath) && $0.preservationReady } || working)
            }
        }
        if let audit { Section("Audited movies") { ForEach(filteredAuditItems(from: audit)) { item in Toggle(isOn: Binding(get: { selectedPaths.contains(item.videoPath) }, set: { if $0 { selectedPaths.insert(item.videoPath) } else { selectedPaths.remove(item.videoPath) } })) { VStack(alignment: .leading) { Text(item.nfoTitle ?? URL(fileURLWithPath: item.videoPath).deletingPathExtension().lastPathComponent); Text("\(item.state) · \(item.folderState)").font(.caption).foregroundStyle(item.preservationReady ? .orange : .secondary) } } } } }
        Section("TVDB") { TextField("Search series", text: $query); Button("Search TVDB") { runSearch() }.disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || working); ForEach(results) { result in VStack(alignment: .leading) { Text(result.title); Text("TVDB \(result.tvdbID)\(result.year.map { " · \($0)" } ?? "")").font(.caption).foregroundStyle(.secondary) } } }
        Section { Text(status).font(.footnote).foregroundStyle(.secondary) }
    }.navigationTitle("Remote tools").confirmationDialog("Create frozen package?", isPresented: $confirmPackage, titleVisibility: .visible) { Button("Create package") { freezeSelected() } } message: { Text("This creates a reviewed package on the old MBA. It does not modify the media library.") } }
    private func runAudit() { working = true; Task { defer { working = false }; do { audit = try await session.client.movieAudit(); status = "Audit complete." } catch { status = error.localizedDescription } } }
    private func runSearch() { working = true; Task { defer { working = false }; do { results = try await session.client.searchTV(query); status = "Found \(results.count) series." } catch { status = error.localizedDescription } } }
    private func freezeSelected() { guard let audit else { return }; let eligible = audit.items.filter { selectedPaths.contains($0.videoPath) && (packageKind == "sidecar" ? $0.sidecarReady : $0.preservationReady) }; guard !eligible.isEmpty else { return }; working = true; Task { defer { working = false }; do { let job = try await session.client.freezeMoviePackage(packageKind, videoPaths: eligible.map(\.videoPath)); status = "Frozen job \(job.id) created for \(eligible.count) selected movie(s)."; await session.refresh() } catch { status = error.localizedDescription } } }
    private func filteredAuditItems(from audit: CompanionMovieAuditReport) -> [CompanionMovieAuditItem] { switch auditFilter { case "needsFolder": audit.items.filter(\.preservationReady); case "embedded": audit.items.filter(\.sidecarReady); case "incomplete": audit.items.filter { !$0.preservationReady && !$0.sidecarReady }; default: audit.items } }
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
                LabeledContent("Status", value: job.state == .applied ? "Applied" : "Ready"); LabeledContent("Provider", value: job.provider.uppercased()); LabeledContent("Moves", value: String(job.moves)); LabeledContent("Generated files", value: String(job.generatedFiles))
                if job.unavailableArtwork > 0 { LabeledContent("Unavailable artwork", value: String(job.unavailableArtwork)) }
            }
            Section("Package operations") { Button("Dry run") { run(.dryRun) }.disabled(isWorking || job.state == .applied); Button("Apply", role: .destructive) { showApply = true }.disabled(isWorking || job.state == .applied); Button("Rollback") { run(.rollback) }.disabled(isWorking || job.state != .applied) }
            if let result { Section("\(result.operation.rawValue) result") { Text(result.log.isEmpty ? "No output." : result.log).font(.system(.caption, design: .monospaced)).textSelection(.enabled); Text(result.succeeded ? "Completed." : "Failed; review the log before proceeding.").foregroundStyle(result.succeeded ? .secondary : .red) } }
        }.navigationTitle(job.title)
            .confirmationDialog("Apply this frozen job?", isPresented: $showApply, titleVisibility: .visible) { Button("Apply \(job.title)", role: .destructive) { run(.apply) } } message: { Text("This runs the exact reviewed package on the old MBA. Review its dry-run result first; rollback remains available after apply.") }
    }
    private func run(_ operation: CompanionOperation) { isWorking = true; Task { defer { isWorking = false }; do { result = try await session.client.run(job, operation: operation) } catch { result = CompanionOperationResult(jobID: job.id, operation: operation, succeeded: false, log: error.localizedDescription) } } }
}
