import Foundation

/// Was die Top-Shelf-Erweiterung auf dem Apple TV zeigt: der Stand von „Weiter ansehen“.
/// Die App schreibt ihn in einen gemeinsamen Ordner, die Erweiterung liest ihn dort.
public struct TopShelfSnapshot: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public var type: String
        public var id: String
        public var name: String
        /// Zweite Zeile, etwa „S02 E04“. Leer bei Filmen.
        public var subtitle: String?
        public var poster: URL?
        /// Breites Bild für das Karussell. Fehlt es, zeigt die Erweiterung Poster in einer Reihe.
        public var background: URL?
        /// Anteil zwischen 0 und 1.
        public var progress: Double?

        public init(
            type: String, id: String, name: String, subtitle: String? = nil,
            poster: URL? = nil, background: URL? = nil, progress: Double? = nil
        ) {
            self.type = type
            self.id = id
            self.name = name
            self.subtitle = subtitle
            self.poster = poster
            self.background = background
            self.progress = progress
        }

        /// Link, mit dem ein Eintrag im Top Shelf die App auf der Detailseite öffnet.
        public var link: URL? {
            var parts = URLComponents()
            parts.scheme = TopShelfSnapshot.scheme
            parts.host = "detail"
            parts.queryItems = [URLQueryItem(name: "type", value: type), URLQueryItem(name: "id", value: id)]
            return parts.url
        }
    }

    public var entries: [Entry]
    public var updated: Date

    public init(entries: [Entry], updated: Date = Date()) {
        self.entries = entries
        self.updated = updated
    }

    /// Das Linkschema der App.
    public static let scheme = "frames"
    /// Gemeinsamer Ordner von App und Erweiterung. Das Kennzeichen muss in beiden Berechtigungen stehen.
    public static let appGroup = "group.app.frames.Frames"
    public static let fileName = "topshelf.json"
    /// Mehr als acht Einträge zeigt das Top Shelf nicht sinnvoll.
    public static let maxEntries = 8

    /// Die Einträge aus der Bibliothek: angefangen, aber nicht zu Ende gesehen, zuletzt Gesehenes zuerst.
    public static func entries(from library: [LibraryItem], backgrounds: [String: URL] = [:]) -> [Entry] {
        library
            .filter(\.isContinueWatching)
            .sorted { ($0.lastWatched ?? $0.modified ?? .distantPast) > ($1.lastWatched ?? $1.modified ?? .distantPast) }
            .prefix(maxEntries)
            .map { item in
                Entry(
                    type: item.type, id: item.id, name: item.name,
                    subtitle: episodeLabel(videoId: item.videoId, metaId: item.id),
                    poster: item.poster, background: backgrounds[item.id], progress: item.progress
                )
            }
    }

    /// „S02 E04“ aus einer Folgen-id wie `tt1234567:2:4`. Bei Filmen `nil`.
    public static func episodeLabel(videoId: String?, metaId: String) -> String? {
        guard let videoId else { return nil }
        let parts = videoId.split(separator: ":").map(String.init)
        guard parts.count >= 3, parts[0] == metaId.split(separator: ":").first.map(String.init),
              let season = Int(parts[parts.count - 2]), let episode = Int(parts[parts.count - 1]) else { return nil }
        return String(format: "S%02d E%02d", season, episode)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> TopShelfSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TopShelfSnapshot.self, from: data)
    }

    #if !os(Linux)
    /// Ablageort im gemeinsamen Ordner. `nil`, wenn das Gerät den Ordner nicht freigibt,
    /// zum Beispiel bei einer App, die mit einem kostenlosen Apple-Konto signiert wurde.
    public static func fileURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(fileName)
    }

    public func write() -> Bool {
        guard let url = Self.fileURL(), let data = try? encoded() else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    public static func read() -> TopShelfSnapshot? {
        guard let url = fileURL(), let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }
    #endif
}
