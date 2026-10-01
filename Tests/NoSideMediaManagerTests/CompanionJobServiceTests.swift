import Foundation
import Testing
@testable import NoSideMediaManager
@testable import NoSideMediaCompanionCore

@Test func companionListsOnlyFrozenManifestJobs() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let jobs = root.appendingPathComponent("jobs", isDirectory: true); let library = root.appendingPathComponent("library", isDirectory: true); let job = jobs.appendingPathComponent("one", isDirectory: true)
    try FileManager.default.createDirectory(at: job, withIntermediateDirectories: true); try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let manifest = PortableJobManifest(jobID: "mmm-fixture", series: TVSeries(tvdbID: 1, title: "Fixture"), moves: [], generatedFiles: ["tvshow.nfo"])
    try JSONEncoder().encode(manifest).write(to: job.appendingPathComponent("manifest.json"))
    let service = CompanionJobService(configuration: .init(jobsRoot: jobs, libraryRoot: library, token: "secret", version: "test"))
    let found = await service.jobs()
    #expect(found.count == 1)
    #expect(found.first?.id == manifest.jobID)
    #expect(found.first?.createdAt != nil)
    #expect(await service.serverInfo().libraryRoot == library.path)
}

@Test func companionReadsLegacyManifestAndMarksBackupAsApplied() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let jobs = root.appendingPathComponent("jobs", isDirectory: true); let library = root.appendingPathComponent("library", isDirectory: true); let job = jobs.appendingPathComponent("legacy", isDirectory: true)
    try FileManager.default.createDirectory(at: job, withIntermediateDirectories: true); try FileManager.default.createDirectory(at: library.appendingPathComponent(".noside-mmm-backups/mmm-legacy"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let data = "{\"formatVersion\":1,\"jobID\":\"mmm-legacy\",\"seriesTVDBID\":1,\"seriesTitle\":\"Legacy show\",\"moves\":[],\"generatedFiles\":[],\"unavailableArtwork\":[],\"notes\":[]}".data(using: .utf8)!
    try data.write(to: job.appendingPathComponent("manifest.json"))
    let service = CompanionJobService(configuration: .init(jobsRoot: jobs, libraryRoot: library, token: "secret", version: "test"))
    #expect(await service.jobs().first?.state == .applied)
}

@Test func companionRecognisesExplicitRolledBackMarker() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let jobs = root.appendingPathComponent("jobs", isDirectory: true); let library = root.appendingPathComponent("library", isDirectory: true); let job = jobs.appendingPathComponent("rolled-back", isDirectory: true)
    let backup = library.appendingPathComponent(".noside-mmm-backups/mmm-rolled-back", isDirectory: true)
    try FileManager.default.createDirectory(at: job, withIntermediateDirectories: true); try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true); try Data().write(to: backup.appendingPathComponent("rolled-back"))
    defer { try? FileManager.default.removeItem(at: root) }
    let manifest = PortableJobManifest(jobID: "mmm-rolled-back", series: TVSeries(tvdbID: 1, title: "Fixture"), moves: [], generatedFiles: [])
    try JSONEncoder().encode(manifest).write(to: job.appendingPathComponent("manifest.json"))
    let service = CompanionJobService(configuration: .init(jobsRoot: jobs, libraryRoot: library, token: "secret", version: "test"))
    #expect(await service.jobs().first?.state == .rolledBack)
}

@Test func companionRetainsOperationHistoryBesideFrozenJob() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let jobs = root.appendingPathComponent("jobs", isDirectory: true); let library = root.appendingPathComponent("library", isDirectory: true); let job = jobs.appendingPathComponent("history", isDirectory: true)
    try FileManager.default.createDirectory(at: job, withIntermediateDirectories: true); try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let manifest = PortableJobManifest(jobID: "mmm-history", series: TVSeries(tvdbID: 1, title: "Fixture"), moves: [], generatedFiles: [])
    try JSONEncoder().encode(manifest).write(to: job.appendingPathComponent("manifest.json"))
    let script = job.appendingPathComponent("apply.sh")
    try "#!/bin/sh\necho dry-run fixture\n".write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    let service = CompanionJobService(configuration: .init(jobsRoot: jobs, libraryRoot: library, token: "secret", version: "test"))
    let result = try await service.run(jobID: manifest.jobID, operation: .dryRun)
    #expect(result.succeeded)
    let history = try await service.history(jobID: manifest.jobID)
    #expect(history.count == 1)
    #expect(history.first?.operation == .dryRun)
    #expect(history.first?.log.contains("dry-run fixture") == true)
}
