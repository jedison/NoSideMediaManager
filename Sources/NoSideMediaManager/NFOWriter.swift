import Foundation

public enum NFOWriter {
    public static func embeddedMovieData(title: String, creationDate: String?) throws -> Data {
        let root = XMLElement(name: "movie"); add("title", title, to: root); add("premiered", creationDate, to: root)
        addLockData(to: root)
        let xml = XMLDocument(rootElement: root); xml.characterEncoding = "UTF-8"; xml.version = "1.0"; return xml.xmlData(options: [.nodePrettyPrint])
    }
    public static func movieData(_ movie: Movie) throws -> Data {
        let root = XMLElement(name: "movie")
        add("title", movie.title, to: root)
        add("originaltitle", movie.originalTitle, to: root)
        add("plot", movie.overview, to: root)
        add("premiered", movie.releaseDate, to: root)
        add("year", movie.year, to: root)
        add("runtime", movie.runtimeMinutes.map(String.init), to: root)
        add("rating", movie.rating.map { String($0) }, to: root)
        for genre in movie.genres { add("genre", genre, to: root) }
        uniqueID(movie.tmdbID, type: "tmdb", defaultID: true, to: root)
        addLockData(to: root)
        let xml = XMLDocument(rootElement: root); xml.characterEncoding = "UTF-8"; xml.version = "1.0"
        return xml.xmlData(options: [.nodePrettyPrint])
    }
    public static func seasonData(number: Int, title: String? = nil) throws -> Data {
        let root = XMLElement(name: "season")
        add("title", title ?? "Season \(number)", to: root)
        add("seasonnumber", String(number), to: root)
        addLockData(to: root)
        let xml = XMLDocument(rootElement: root)
        xml.characterEncoding = "UTF-8"
        xml.version = "1.0"
        return xml.xmlData(options: [.nodePrettyPrint])
    }

    public static func seriesData(_ series: TVSeries) throws -> Data {
        let xml = XMLDocument(rootElement: seriesElement(series))
        xml.characterEncoding = "UTF-8"
        xml.version = "1.0"
        return xml.xmlData(options: [.nodePrettyPrint])
    }

    public static func episodeData(_ episode: TVEpisode) throws -> Data {
        let root = XMLElement(name: "episodedetails")
        add("title", episode.title, to: root)
        add("season", String(episode.season), to: root)
        add("episode", String(episode.number), to: root)
        add("plot", episode.overview, to: root)
        add("aired", episode.aired, to: root)
        add("rating", episode.rating.map { String($0) }, to: root)
        uniqueID(episode.tvdbID, type: "tvdb", defaultID: true, to: root)
        addLockData(to: root)
        let xml = XMLDocument(rootElement: root)
        xml.characterEncoding = "UTF-8"
        xml.version = "1.0"
        return xml.xmlData(options: [.nodePrettyPrint])
    }

    private static func seriesElement(_ series: TVSeries) -> XMLElement {
        let root = XMLElement(name: "tvshow")
        add("title", series.title, to: root)
        add("plot", series.overview, to: root)
        add("premiered", series.firstAired, to: root)
        add("status", series.status, to: root)
        add("studio", series.network, to: root)
        add("rating", series.rating.map { String($0) }, to: root)
        for genre in series.genres { add("genre", genre, to: root) }
        uniqueID(series.tvdbID, type: "tvdb", defaultID: true, to: root)
        addLockData(to: root)
        return root
    }

    private static func add(_ name: String, _ value: String?, to parent: XMLElement) {
        guard let value, !value.isEmpty else { return }
        let element = XMLElement(name: name, stringValue: value)
        parent.addChild(element)
    }

    private static func uniqueID(_ value: Int, type: String, defaultID: Bool, to parent: XMLElement) {
        let element = XMLElement(name: "uniqueid", stringValue: String(value))
        element.addAttribute(XMLNode.attribute(withName: "type", stringValue: type) as! XMLNode)
        element.addAttribute(XMLNode.attribute(withName: "default", stringValue: defaultID ? "true" : "false") as! XMLNode)
        parent.addChild(element)
    }

    /// Emby's whole-item metadata lock. This preserves MMM's reviewed NFO
    /// values during future library scans while still allowing the NFO itself
    /// to be deliberately edited and refreshed by the owner.
    private static func addLockData(to parent: XMLElement) {
        add("lockdata", "true", to: parent)
    }
}
