import Foundation

/// Was das X-Ray im Player zeigt: wer mitspielt und welche Musik zum Titel gehört.
///
/// Szenengenaue Angaben, wie Prime Video sie hat, gibt es nicht als freie Quelle. Frames zeigt deshalb
/// die Besetzung des Titels (bei Serien mit den Gaststars der laufenden Folge) und den offiziellen Soundtrack.
public struct XRayRequest: Sendable, Hashable {
    /// IMDb-id des Titels, etwa „tt0903747“. Andere ids (Kitsu und Co.) gehen auch, dann ohne Fotos.
    public var metaId: String
    public var type: String
    public var name: String
    public var year: Int?
    public var season: Int?
    public var episode: Int?
    /// Namen der Besetzung, wie das Addon sie liefert. Grundlage, wenn TVmaze den Titel nicht kennt.
    public var castNames: [String]

    public init(
        metaId: String, type: String, name: String, year: Int? = nil,
        season: Int? = nil, episode: Int? = nil, castNames: [String] = []
    ) {
        self.metaId = metaId
        self.type = type
        self.name = name
        self.year = year
        self.season = season
        self.episode = episode
        self.castNames = castNames
    }

    /// Liest Staffel und Folge aus einer Stremio-id wie „tt0903747:2:3“.
    public init(metaId: String, type: String, name: String, videoId: String, year: Int? = nil, castNames: [String] = []) {
        let parts = videoId.split(separator: ":")
        var season: Int?
        var episode: Int?
        if parts.count >= 3, let s = Int(parts[parts.count - 2]), let e = Int(parts[parts.count - 1]) {
            season = s
            episode = e
        }
        self.init(metaId: metaId, type: type, name: name, year: year, season: season, episode: episode, castNames: castNames)
    }

    var imdbId: String? {
        let id = metaId.split(separator: ":").first.map(String.init) ?? metaId
        return id.hasPrefix("tt") && id.dropFirst(2).allSatisfy(\.isNumber) && id.count > 2 ? id : nil
    }

    var isSeries: Bool { type == "series" || season != nil }
}

/// Eine Person aus der Besetzung.
public struct XRayPerson: Sendable, Hashable, Identifiable {
    public var name: String
    /// Rolle, etwa „Walter White“. Spielt jemand mehrere, stehen sie mit „ / “ getrennt.
    public var character: String?
    public var photo: URL?
    /// Nur in dieser Folge dabei.
    public var isGuest: Bool

    public var id: String { name }

    public init(name: String, character: String? = nil, photo: URL? = nil, isGuest: Bool = false) {
        self.name = name
        self.character = character
        self.photo = photo
        self.isGuest = isGuest
    }
}

/// Ein Stück aus einem Soundtrack.
public struct XRayTrack: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var artist: String
    public var duration: Double?

    public init(id: String, title: String, artist: String, duration: Double? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.duration = duration
    }

    /// „4:38“
    public var durationLabel: String? {
        duration.map { formatPlaybackTime($0) }
    }
}

/// Ein Soundtrack-Album, etwa „Music From the Original Series“ oder die Filmmusik.
public struct XRaySoundtrack: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var year: Int?
    /// Filmmusik (Score) statt Songs.
    public var isScore: Bool
    public var tracks: [XRayTrack]

    public init(id: String, title: String, year: Int? = nil, isScore: Bool = false, tracks: [XRayTrack] = []) {
        self.id = id
        self.title = title
        self.year = year
        self.isScore = isScore
        self.tracks = tracks
    }

    /// Cover des Albums aus dem Cover Art Archive. Fehlt dort eins, antwortet die Adresse mit 404.
    public var cover: URL? {
        URL(string: "https://coverartarchive.org/release-group/\(id)/front-250")
    }
}

/// Vergleicht Namen ohne Groß- und Kleinschreibung, Akzente und Satzzeichen.
func normalizedName(_ text: String) -> String {
    let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
    let kept = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
    return String(kept).split(separator: " ").joined(separator: " ")
}
