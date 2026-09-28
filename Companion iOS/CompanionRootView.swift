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
    @State private var audit: CompanionMovieAuditSummary?
    @State private var status = "These requests run on the old MBA and do not change media files."
    @State private var working = false
    var body: some View { List {
        Section("Movie library") { Button("Audit configured movie/library root") { runAudit() }.disabled(working); if let audit { Text("\(audit.totalVideos) videos · \(audit.invalidNFOs) invalid NFOs"); ForEach(audit.byState.sorted(by: { $0.key < $1.key }), id: \.key) { Text("\($0.key): \($0.value)") } } }
        Section("TVDB") { TextField("Search series", text: $query); Button("Search TVDB") { runSearch() }.disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || working); ForEach(results) { result in VStack(alignment: .leading) { Text(result.title); Text("TVDB \(result.tvdbID)\(result.year.map { " · \($0)" } ?? "")").font(.caption).foregroundStyle(.secondary) } } }
        Section { Text(status).font(.footnote).foregroundStyle(.secondary) }
    }.navigationTitle("Remote tools") }
    private func runAudit() { working = true; Task { defer { working = false }; do { audit = try await session.client.movieAudit(); status = "Audit complete." } catch { status = error.localizedDescription } } }
    private func runSearch() { working = true; Task { defer { working = false }; do { results = try await session.client.searchTV(query); status = "Found \(results.count) series." } catch { status = error.localizedDescription } } }
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
            Section("Operations") { Button("Dry run") { run(.dryRun) }.disabled(isWorking || job.state == .applied); Button("Apply", role: .destructive) { showApply = true }.disabled(isWorking || job.state == .applied); Button("Rollback") { run(.rollback) }.disabled(isWorking || job.state != .applied) }
            if let result { Section("\(result.operation.rawValue) log") { Text(result.log.isEmpty ? "No output." : result.log).font(.system(.caption, design: .monospaced)).textSelection(.enabled); if !result.succeeded { Text("Operation failed; no further action was taken automatically.").foregroundStyle(.red) } } }
        }.navigationTitle(job.title)
            .confirmationDialog("Apply this frozen job?", isPresented: $showApply, titleVisibility: .visible) { Button("Apply \(job.title)", role: .destructive) { run(.apply) } } message: { Text("This changes files only on the old MBA. Run dry-run first and keep its rollback backup.") }
    }
    private func run(_ operation: CompanionOperation) { isWorking = true; Task { defer { isWorking = false }; do { result = try await session.client.run(job, operation: operation) } catch { result = CompanionOperationResult(jobID: job.id, operation: operation, succeeded: false, log: error.localizedDescription) } } }
}
