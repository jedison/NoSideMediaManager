import SwiftUI

struct CompanionRootView: View {
    @EnvironmentObject private var session: CompanionSession
    var body: some View {
        NavigationStack {
            Group { if session.server == nil { PairingView() } else { JobListView() } }
                .navigationTitle("Media Manager")
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
            Section("MMM Companion") {
                TextField("Old MBA address", text: $session.host).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Port", value: $session.port, format: .number).keyboardType(.numberPad)
                SecureField("Pairing token", text: $session.token)
            }
            Section { Button("Connect") { session.save(); Task { await session.refresh() } }.disabled(session.host.isEmpty || session.token.isEmpty) }
            Section { Text("Start Companion in the MMM Mac app, then copy its pairing token here. The phone controls frozen jobs; it never receives direct disk access.").font(.footnote).foregroundStyle(.secondary) }
            Text(session.status).foregroundStyle(.secondary)
        }.navigationTitle("Pair MMM")
    }
}

private struct JobListView: View {
    @EnvironmentObject private var session: CompanionSession
    var body: some View {
        List {
            Section { Text(session.status).font(.footnote).foregroundStyle(.secondary) }
            ForEach(session.jobs) { job in
                NavigationLink(value: job) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.title)
                        Text("\(job.mediaKind.uppercased()) · \(job.provider.uppercased()) · \(job.moves) moves · \(job.generatedFiles) sidecars").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.navigationDestination(for: CompanionJob.self) { JobDetailView(job: $0) }
        }.refreshable { await session.refresh() }
            .overlay { if session.isLoading { ProgressView() } }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { Task { await session.refresh() } } label: { Image(systemName: "arrow.clockwise") } } }
    }
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
                LabeledContent("Provider", value: job.provider.uppercased()); LabeledContent("Moves", value: String(job.moves)); LabeledContent("Generated files", value: String(job.generatedFiles))
                if job.unavailableArtwork > 0 { LabeledContent("Unavailable artwork", value: String(job.unavailableArtwork)) }
            }
            Section("Operations") { Button("Dry run") { run(.dryRun) }.disabled(isWorking); Button("Apply", role: .destructive) { showApply = true }.disabled(isWorking); Button("Rollback") { run(.rollback) }.disabled(isWorking) }
            if let result { Section("\(result.operation.rawValue) log") { Text(result.log.isEmpty ? "No output." : result.log).font(.system(.caption, design: .monospaced)).textSelection(.enabled); if !result.succeeded { Text("Operation failed; no further action was taken automatically.").foregroundStyle(.red) } } }
        }.navigationTitle(job.title)
            .confirmationDialog("Apply this frozen job?", isPresented: $showApply, titleVisibility: .visible) { Button("Apply \(job.title)", role: .destructive) { run(.apply) } } message: { Text("This changes files only on the old MBA. Run dry-run first and keep its rollback backup.") }
    }
    private func run(_ operation: CompanionOperation) { isWorking = true; Task { defer { isWorking = false }; do { result = try await session.client.run(job, operation: operation) } catch { result = CompanionOperationResult(jobID: job.id, operation: operation, succeeded: false, log: error.localizedDescription) } } }
}
