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

@Test func companionRestoresCompletedMovieAuditFromDisk() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let jobs = root.appendingPathComponent("jobs", isDirectory: true); let library = root.appendingPathComponent("library", isDirectory: true)
    try FileManager.default.createDirectory(at: jobs, withIntermediateDirectories: true); try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let report = MovieLibraryHealthReport(items: [], duplicateTMDBIDs: [:], invalidNFOs: [], ignoredVideoFiles: [])
    let saved = CompanionMovieAuditSnapshot(phase: .complete, completedVideos: 0, totalVideos: 0, startedAt: Date(timeIntervalSince1970: 1), completedAt: Date(timeIntervalSince1970: 2), report: .init(report: report))
    try JSONEncoder().encode(saved).write(to: jobs.appendingPathComponent(".noside-mmm-last-movie-audit.json"))
    let service = CompanionJobService(configuration: .init(jobsRoot: jobs, libraryRoot: library, token: "secret", version: "test"))
    let restored = await service.movieAuditStatus()
    #expect(restored.phase == .complete)
    #expect(restored.completedAt == saved.completedAt)
    #expect(restored.report?.totalVideos == 0)
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

@Test func companionDeletesReadyPackageButRetainsAppliedRollbackEvidence() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let jobs = root.appendingPathComponent("jobs", isDirectory: true); let library = root.appendingPathComponent("library", isDirectory: true)
    let ready = jobs.appendingPathComponent("ready", isDirectory: true); let applied = jobs.appendingPathComponent("applied", isDirectory: true)
    try FileManager.default.createDirectory(at: ready, withIntermediateDirectories: true); try FileManager.default.createDirectory(at: applied, withIntermediateDirectories: true); try FileManager.default.createDirectory(at: library.appendingPathComponent(".noside-mmm-backups/mmm-applied"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try JSONEncoder().encode(PortableJobManifest(jobID: "mmm-ready", series: TVSeries(tvdbID: 1, title: "Ready"), moves: [], generatedFiles: [])).write(to: ready.appendingPathComponent("manifest.json"))
    try JSONEncoder().encode(PortableJobManifest(jobID: "mmm-applied", series: TVSeries(tvdbID: 2, title: "Applied"), moves: [], generatedFiles: [])).write(to: applied.appendingPathComponent("manifest.json"))
    let service = CompanionJobService(configuration: .init(jobsRoot: jobs, libraryRoot: library, token: "secret", version: "test"))
    try await service.deletePackage(jobID: "mmm-ready")
    #expect(!FileManager.default.fileExists(atPath: ready.path))
    do {
        try await service.deletePackage(jobID: "mmm-applied")
        Issue.record("Expected an applied package deletion to be rejected")
    } catch let error as CompanionJobServiceError {
        #expect(error == .appliedPackageCannotBeDeleted)
    }
    #expect(FileManager.default.fileExists(atPath: applied.path))
    #expect(FileManager.default.fileExists(atPath: library.appendingPathComponent(".noside-mmm-backups/mmm-applied").path))
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
