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
    #expect(found == [CompanionJob(manifest: manifest)])
    #expect(await service.serverInfo().libraryRoot == library.path)
}
