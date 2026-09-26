import Foundation

public struct CompanionRenamePlan: Sendable, Equatable {
    public let filePlan: MediaRenamePlan
    public let nfoReferenceUpdates: [MediaRename]
}

public enum CompanionRenamePlanner {
    /// Expands each approved video move to existing same-basename NFO/JPG/PNG
    /// sidecars. Destination names always follow the destination video basename.
    public static func expand(videoPlan: MediaRenamePlan, fileManager: FileManager = .default) throws -> CompanionRenamePlan {
        var all = videoPlan.renames
        var nfoUpdates = [MediaRename]()
        for video in videoPlan.renames {
            for ext in ["nfo", "jpg", "jpeg", "png"] {
                let source = video.source.deletingPathExtension().appendingPathExtension(ext)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                let destination = video.destination.deletingPathExtension().appendingPathExtension(ext)
                let companion = MediaRename(source: source, destination: destination)
                all.append(companion)
                if ext == "nfo" { nfoUpdates.append(video) }
            }
        }
        return CompanionRenamePlan(filePlan: try MediaRenamePlan(renames: all), nfoReferenceUpdates: nfoUpdates)
    }

    /// Applies the expanded move, then repairs NFO nodes such as
    /// `original_filename` when they reference the old video basename.
    public static func execute(_ plan: CompanionRenamePlan, fileManager: FileManager = .default) throws {
        try plan.filePlan.execute(fileManager: fileManager)
        for video in plan.nfoReferenceUpdates {
            let nfo = video.destination.deletingPathExtension().appendingPathExtension("nfo")
            guard fileManager.fileExists(atPath: nfo.path) else { continue }
            try updateReferences(in: nfo, oldFilename: video.source.lastPathComponent, newFilename: video.destination.lastPathComponent)
        }
    }

    private static func updateReferences(in url: URL, oldFilename: String, newFilename: String) throws {
        let document = try XMLDocument(contentsOf: url, options: [])
        for node in try document.nodes(forXPath: "//text()") where node.stringValue?.contains(oldFilename) == true { node.stringValue = node.stringValue?.replacingOccurrences(of: oldFilename, with: newFilename) }
        for node in try document.nodes(forXPath: "//@*") where node.stringValue?.contains(oldFilename) == true { node.stringValue = node.stringValue?.replacingOccurrences(of: oldFilename, with: newFilename) }
        try document.xmlData(options: [.nodePrettyPrint]).write(to: url, options: .atomic)
    }
}
