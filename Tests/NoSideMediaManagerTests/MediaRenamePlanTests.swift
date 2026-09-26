import Foundation
import Testing
@testable import NoSideMediaManager

@Test func renamePlanProducesQuotedReversibleScript() throws {
    let plan = try MediaRenamePlan(renames: [MediaRename(source: URL(fileURLWithPath: "/Volumes/TV/Bake Off's S01E01.m4v"), destination: URL(fileURLWithPath: "/Volumes/TV/Bake Off's S08E01.m4v"))])
    let script = plan.bashScript()
    #expect(script.contains("mv -- "))
    #expect(script.contains("S01E01.m4v"))
    #expect(script.contains("S08E01.m4v"))
    #expect(plan.reversed.renames == [MediaRename(source: URL(fileURLWithPath: "/Volumes/TV/Bake Off's S08E01.m4v"), destination: URL(fileURLWithPath: "/Volumes/TV/Bake Off's S01E01.m4v"))])
}

@Test func renamePlanPreflightsBeforeMovingAnything() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let existing = directory.appendingPathComponent("existing.m4v")
    let collision = directory.appendingPathComponent("collision.m4v")
    FileManager.default.createFile(atPath: existing.path, contents: Data())
    FileManager.default.createFile(atPath: collision.path, contents: Data())
    let plan = try MediaRenamePlan(renames: [MediaRename(source: existing, destination: directory.appendingPathComponent("renamed.m4v")), MediaRename(source: directory.appendingPathComponent("missing.m4v"), destination: collision)])
    #expect(throws: MediaRenameError.sourceMissing(directory.appendingPathComponent("missing.m4v"))) { try plan.execute() }
    #expect(FileManager.default.fileExists(atPath: existing.path))
}

@Test func renamePlanCanMoveIntoAnExistingSeasonFolder() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sourceFolder = root.appendingPathComponent("Incoming", isDirectory: true)
    let seasonFolder = root.appendingPathComponent("Season 08", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: seasonFolder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = sourceFolder.appendingPathComponent("GBBO.S01E01.m4v")
    let destination = seasonFolder.appendingPathComponent("GBBO.S08E01.m4v")
    FileManager.default.createFile(atPath: source.path, contents: Data())
    try MediaRenamePlan(renames: [MediaRename(source: source, destination: destination)]).execute()
    #expect(FileManager.default.fileExists(atPath: destination.path))
}
