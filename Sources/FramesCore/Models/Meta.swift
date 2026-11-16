import Foundation

/// Ein Film, eine Serie oder ein anderer Titel. Kataloge liefern die Kurzform, `/meta` die volle.
public struct Meta: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var type: String
    public var name: String
    public var poster: URL?
    public var posterShape: PosterShape
    public var background: URL?
    public var logo: URL?
    public var description: String?
    public var releaseInfo: String?
    public var runtime: String?
    public var genres: [String]
    public var imdbRating: String?
    public var cast: [String]
    public var directors: [String]
    public var released: Date?
    public var videos: [Video]
    public var defaultVideoId: String?

    public init(
        id: String, type: String, name: String, poster: URL? = nil, posterShape: PosterShape = .poster,
        background: URL? = nil, logo: URL? = nil, description: String? = nil, releaseInfo: String? = nil,
        runtime: String? = nil, genres: [String] = [], imdbRating: String? = nil, cast: [String] = [],
        directors: [String] = [], released: Date? = nil, videos: [Video] = [], defaultVideoId: String? = nil
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.poster = poster
        self.posterShape = posterShape
        self.background = background
        self.logo = logo
        self.description = description
        self.releaseInfo = releaseInfo
        self.runtime = runtime
        self.genres = genres
        self.imdbRating = imdbRating
        self.cast = cast
        self.directors = directors
        self.released = released
        self.videos = videos
        self.defaultVideoId = defaultVideoId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let id = c.string("id") ?? c.string("imdb_id") else {
            throw DecodingError.keyNotFound(AnyKey("id"), .init(codingPath: c.codingPath, debugDescription: "Titel ohne id"))
        }
        self.id = id
        type = c.string("type") ?? "other"
        name = c.string("name") ?? id
        poster = c.string("poster").flatMap(URL.init(string:))
        posterShape = c.string("posterShape").flatMap(PosterShape.init(rawValue:)) ?? .poster
        background = c.string("background").flatMap(URL.init(string:))
        logo = c.string("logo").flatMap(URL.init(string:))
        description = c.string("description")
        releaseInfo = c.string("releaseInfo") ?? c.string("year")
        runtime = c.string("runtime")
        let genres = c.strings("genres")
        self.genres = genres.isEmpty ? c.strings("genre") : genres
        imdbRating = c.string("imdbRating")
        cast = c.strings("cast")
        directors = c.strings("director")
        released = c.date("released")
        videos = c.list("videos")
        let hints = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("behaviorHints"))
        defaultVideoId = hints?.string("defaultVideoId")
    }

    public var isSeries: Bool { !videos.isEmpty && defaultVideoId == nil && videos.contains { $0.season != nil } }

    /// Staffelnummern aufsteigend, Specials (Staffel 0) ans Ende.
    public var seasons: [Int] {
        let all = Set(videos.compactMap(\.season)).sorted()
        return all.filter { $0 > 0 } + all.filter { $0 == 0 }
    }

    public func episodes(inSeason season: Int) -> [Video] {
        videos.filter { $0.season == season }.sorted { ($0.episode ?? 0) < ($1.episode ?? 0) }
    }

    /// Die id, mit der Streams angefragt werden: bei Filmen die des Titels, bei Serien die der Folge.
    public func streamId(for video: Video? = nil) -> String {
        video?.id ?? defaultVideoId ?? id
    }
}

public enum PosterShape: String, Sendable, Hashable {
    case poster, landscape, square

    /// Breite geteilt durch Höhe.
    public var aspectRatio: Double {
        switch self {
        case .poster: return 2.0 / 3.0
        case .landscape: return 16.0 / 9.0
        case .square: return 1
        }
    }
}

public struct Video: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var season: Int?
    public var episode: Int?
    public var released: Date?
    public var thumbnail: URL?
    public var overview: String?

    public init(
        id: String, title: String, season: Int? = nil, episode: Int? = nil,
        released: Date? = nil, thumbnail: URL? = nil, overview: String? = nil
    ) {
        self.id = id
        self.title = title
        self.season = season
        self.episode = episode
        self.released = released
        self.thumbnail = thumbnail
        self.overview = overview
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let id = c.string("id") else {
            throw DecodingError.keyNotFound(AnyKey("id"), .init(codingPath: c.codingPath, debugDescription: "Folge ohne id"))
        }
        self.id = id
        title = c.string("title") ?? c.string("name") ?? id
        season = c.int("season")
        episode = c.int("episode") ?? c.int("number")
        released = c.date("released") ?? c.date("firstAired")
        thumbnail = c.string("thumbnail").flatMap(URL.init(string:))
        overview = c.string("overview") ?? c.string("description")
    }

    /// Kurzform wie „S03 E01“.
    public var code: String? {
        guard let season, let episode else { return nil }
        return String(format: "S%02d E%02d", season, episode)
    }
}

public struct CatalogPage: Decodable, Sendable {
    public var metas: [Meta]
    public var hasMore: Bool

    public init(metas: [Meta], hasMore: Bool = false) {
        self.metas = metas
        self.hasMore = hasMore
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        metas = c.list("metas")
        hasMore = c.bool("hasMore") ?? false
    }
}

struct MetaEnvelope: Decodable {
    let meta: Meta
}

extension Meta {
    /// Laufzeit in Minuten, gelesen aus Angaben wie „148 min“, „2h 28min“ oder „2:28“.
    public var runtimeMinutes: Int? { Self.minutes(from: runtime) }

    static func minutes(from text: String?) -> Int? {
        guard let text = text?.lowercased() else { return nil }
        func number(_ pattern: String) -> Int? {
            guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
            return Int(text[range].filter(\.isNumber))
        }
        let hours = number(#"[0-9]+\s*(h|std)"#)
        let minutes = number(#"[0-9]+\s*m"#)
        if hours != nil || minutes != nil {
            let total = (hours ?? 0) * 60 + (minutes ?? 0)
            return total > 0 ? total : nil
        }
        let parts = text.split(separator: ":").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 2, let hours = parts[0], let minutes = parts[1] { return hours * 60 + minutes }
        if let plain = Int(text.trimmingCharacters(in: .whitespaces)), plain > 0 { return plain }
        return nil
    }
}
