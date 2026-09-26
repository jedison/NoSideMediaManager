import Foundation
import Testing
@testable import NoSideMediaManager

@Test func companionPlanMovesSidecarsAndRepairsNFOReferences() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let target = root.appendingPathComponent("Season 08", isDirectory: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let video = root.appendingPathComponent("GBBO.S07E01.m4v")
    let nfo = root.appendingPathComponent("GBBO.S07E01.nfo")
    let jpg = root.appendingPathComponent("GBBO.S07E01.jpg")
    FileManager.default.createFile(atPath: video.path, contents: Data())
    FileManager.default.createFile(atPath: jpg.path, contents: Data())
    try "<episodedetails><original_filename>GBBO.S07E01.m4v</original_filename></episodedetails>".data(using: .utf8)!.write(to: nfo)
    let destination = target.appendingPathComponent("GBBO.S08E01.m4v")
    let plan = try CompanionRenamePlanner.expand(videoPlan: MediaRenamePlan(renames: [MediaRename(source: video, destination: destination)]))
    try CompanionRenamePlanner.execute(plan)
    #expect(FileManager.default.fileExists(atPath: destination.path))
    #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("GBBO.S08E01.jpg").path))
    #expect(String(decoding: try Data(contentsOf: target.appendingPathComponent("GBBO.S08E01.nfo")), as: UTF8.self).contains("GBBO.S08E01.m4v"))
}
