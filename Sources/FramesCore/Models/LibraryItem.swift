import Foundation

/// Ein Eintrag der Stremio-Bibliothek samt Wiedergabestand, wie ihn das Konto speichert.
public struct LibraryItem: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var type: String
    public var poster: URL?
    public var posterShape: PosterShape
    public var removed: Bool
    public var temp: Bool
    public var modified: Date?
    public var lastWatched: Date?
    /// Position und Länge in Millisekunden.
    public var timeOffset: Double
    public var duration: Double
    public var videoId: String?
    public var timesWatched: Int

    public init(
        id: String, name: String, type: String, poster: URL? = nil, posterShape: PosterShape = .poster,
        removed: Bool = false, temp: Bool = false, modified: Date? = nil, lastWatched: Date? = nil,
        timeOffset: Double = 0, duration: Double = 0, videoId: String? = nil, timesWatched: Int = 0
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.poster = poster
        self.posterShape = posterShape
        self.removed = removed
        self.temp = temp
        self.modified = modified
        self.lastWatched = lastWatched
        self.timeOffset = timeOffset
        self.duration = duration
        self.videoId = videoId
        self.timesWatched = timesWatched
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let id = c.string("_id") else {
            throw DecodingError.keyNotFound(AnyKey("_id"), .init(codingPath: c.codingPath, debugDescription: "Eintrag ohne id"))
        }
        self.id = id
        name = c.string("name") ?? id
        type = c.string("type") ?? "other"
        poster = c.string("poster").flatMap(URL.init(string:))
        posterShape = c.string("posterShape").flatMap(PosterShape.init(rawValue:)) ?? .poster
        removed = c.bool("removed") ?? false
        temp = c.bool("temp") ?? false
        modified = c.date("_mtime")
        let state = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("state"))
        lastWatched = state?.date("lastWatched")
        timeOffset = state?.double("timeOffset") ?? 0
        duration = state?.double("duration") ?? 0
        videoId = state?.string("video_id")
        timesWatched = state?.int("timesWatched") ?? 0
    }

    /// In der Bibliothek sichtbar: weder entfernt noch nur vorübergehend für den Wiedergabestand angelegt.
    public var isInLibrary: Bool { !removed && !temp }

    /// Anteil zwischen 0 und 1, `nil` wenn nichts angefangen wurde.
    public var progress: Double? {
        guard duration > 0, timeOffset > 0 else { return nil }
        return min(1, timeOffset / duration)
    }

    /// Angefangen, aber nicht zu Ende gesehen. Entfernte Einträge zählen mit, solange ihr Stand noch gilt.
    public var isContinueWatching: Bool {
        guard let progress else { return false }
        return progress < 0.95 && !(removed && !temp)
    }
}

extension Array where Element == LibraryItem {
    public var library: [LibraryItem] {
        filter(\.isInLibrary).sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
    }

    public var continueWatching: [LibraryItem] {
        filter(\.isContinueWatching).sorted { ($0.lastWatched ?? .distantPast) > ($1.lastWatched ?? .distantPast) }
    }
}
