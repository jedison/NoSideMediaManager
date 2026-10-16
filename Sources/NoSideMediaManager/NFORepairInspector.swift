import Foundation

public struct NFOFieldDifference: Sendable, Equatable, Identifiable {
    public let field: String
    public let localValue: String?
    public let canonicalValue: String?
    public var id: String { field }
}

public enum NFORepairInspector {
    public static let comparableFields = ["title", "plot", "aired", "season", "episode"]
    public static func differences(at url: URL, comparedTo episode: TVEpisode) throws -> [NFOFieldDifference] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let document = try XMLDocument(contentsOf: url, options: [])
        var values = [String: String?]()
        for field in comparableFields { values[field] = try document.nodes(forXPath: "//\(field)").first?.stringValue }
        let expected = ["title": episode.title, "plot": episode.overview, "aired": episode.aired, "season": String(episode.season), "episode": String(episode.number)]
        return expected.compactMap { key, value in values[key] == value ? nil : NFOFieldDifference(field: key, localValue: values[key] ?? nil, canonicalValue: value) }.sorted { $0.field < $1.field }
    }

    /// Builds a locked canonical NFO while retaining fields a reviewer chose
    /// not to replace. It runs only while a frozen package is created.
    public static func mergedEpisodeData(existingNFO: URL, canonical: TVEpisode, replacing fields: Set<String>) throws -> Data {
        guard FileManager.default.fileExists(atPath: existingNFO.path) else { return try NFOWriter.episodeData(canonical) }
        guard let existing = try? XMLDocument(contentsOf: existingNFO, options: []) else { return try NFOWriter.episodeData(canonical) }
        let generated = try XMLDocument(data: NFOWriter.episodeData(canonical), options: [])
        guard let root = generated.rootElement() else { return try NFOWriter.episodeData(canonical) }
        for field in comparableFields where !fields.contains(field) {
            guard let value = try existing.nodes(forXPath: "//\(field)").first?.stringValue else { continue }
            if let destination = try generated.nodes(forXPath: "//\(field)").first as? XMLElement { destination.stringValue = value }
            else { root.addChild(XMLElement(name: field, stringValue: value)) }
        }
        return generated.xmlData(options: [.nodePrettyPrint])
    }
}
