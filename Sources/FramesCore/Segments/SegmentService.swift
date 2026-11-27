import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Eine Folge, wie Stremio sie benennt: „tt0903747:1:2“ für Serien mit IMDb-Nummer,
/// „kitsu:1376:5“ für Anime aus Kitsu-Katalogen.
public enum EpisodeRef: Sendable, Hashable {
    case imdb(id: String, season: Int, episode: Int)
    case kitsu(id: Int, episode: Int)

    public init?(videoId: String) {
        let parts = videoId.split(separator: ":").map(String.init)
        if parts.count == 3, parts[0].hasPrefix("tt"), let season = Int(parts[1]), let episode = Int(parts[2]) {
            self = .imdb(id: parts[0], season: season, episode: episode)
        } else if parts.count == 3, parts[0] == "kitsu", let id = Int(parts[1]), let episode = Int(parts[2]) {
            self = .kitsu(id: id, episode: episode)
        } else {
            return nil
        }
    }
}

/// Holt Zeitmarken für Rückblick, Intro und Abspann aus offenen Datenbanken.
///
/// - IntroDB (introdb.app) und TheIntroDB (theintrodb.org) kennen Serien über die IMDb-Nummer.
///   Beide werden gefragt, IntroDB hat Vorrang, TheIntroDB füllt Lücken.
/// - AniSkip kennt Anime über die MyAnimeList-Nummer. Die kommt aus der Zuordnung von arm.haglund.dev.
///
/// Die Marken stammen von Nutzern und gelten für die übliche Fassung. Bei einer anderen Schnittfassung
/// können sie ein paar Sekunden danebenliegen. Ohne Antwort bleibt die Liste leer, die Wiedergabe läuft normal.
public struct SegmentService: Sendable {
    private let http: any HTTPTransport

    public init(http: any HTTPTransport = URLSessionTransport()) {
        self.http = http
    }

    public func segments(for videoId: String) async -> MediaSegments {
        guard let ref = EpisodeRef(videoId: videoId) else { return MediaSegments() }
        switch ref {
        case .imdb(let id, let season, let episode):
            async let first = introDB(imdb: id, season: season, episode: episode)
            async let second = theIntroDB(imdb: id, season: season, episode: episode)
            return MediaSegments.merged([await first, await second])
        case .kitsu(let id, let episode):
            return await aniSkip(kitsu: id, episode: episode)
        }
    }

    // MARK: IntroDB

    func introDB(imdb: String, season: Int, episode: Int) async -> MediaSegments {
        let url = Self.url("https://api.introdb.app/segments", [
            ("imdb_id", imdb), ("season", String(season)), ("episode", String(episode)),
        ])
        guard let url, let answer = try? await http.getJSON(IntroDBAnswer.self, from: url) else { return MediaSegments() }
        return answer.segments
    }

    struct IntroDBAnswer: Decodable {
        var segments: MediaSegments

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            var list: [MediaSegment] = []
            for (key, kind) in [("recap", SegmentKind.recap), ("intro", .intro), ("outro", .credits)] {
                guard let part = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey(key)) else { continue }
                let start = part.double("start_sec") ?? part.double("start_ms").map { $0 / 1000 }
                let end = part.double("end_sec") ?? part.double("end_ms").map { $0 / 1000 }
                guard let start else { continue }
                list.append(MediaSegment(kind: kind, start: start, end: end, source: .introDB))
            }
            segments = MediaSegments(list)
        }
    }

    // MARK: TheIntroDB

    func theIntroDB(imdb: String, season: Int, episode: Int) async -> MediaSegments {
        let url = Self.url("https://api.theintrodb.org/v2/media", [
            ("imdb_id", imdb), ("season", String(season)), ("episode", String(episode)),
        ])
        guard let url, let answer = try? await http.getJSON(TheIntroDBAnswer.self, from: url) else { return MediaSegments() }
        return answer.segments
    }

    struct TheIntroDBAnswer: Decodable {
        var segments: MediaSegments

        private struct Range: Decodable {
            var start: Double?
            var end: Double?
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: AnyKey.self)
                start = c.double("start_ms").map { $0 / 1000 }
                end = c.double("end_ms").map { $0 / 1000 }
            }
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            var list: [MediaSegment] = []
            let kinds: [(String, SegmentKind)] = [("recap", .recap), ("intro", .intro), ("credits", .credits), ("preview", .preview)]
            for (key, kind) in kinds {
                for range in c.list(key, of: Range.self) {
                    // Fehlt der Anfang, beginnt der Abschnitt mit der Folge.
                    let start = range.start ?? 0
                    if range.start == nil, range.end == nil { continue }
                    list.append(MediaSegment(kind: kind, start: start, end: range.end, source: .theIntroDB))
                }
            }
            segments = MediaSegments(list)
        }
    }

    // MARK: AniSkip

    func aniSkip(kitsu: Int, episode: Int) async -> MediaSegments {
        guard let mapping = Self.url("https://arm.haglund.dev/api/v2/ids", [("source", "kitsu"), ("id", String(kitsu))]),
              let ids = try? await http.getJSON(AnimeIds.self, from: mapping),
              let mal = ids.myanimelist else { return MediaSegments() }
        return await aniSkip(mal: mal, episode: episode)
    }

    func aniSkip(mal: Int, episode: Int) async -> MediaSegments {
        let url = Self.url("https://api.aniskip.com/v2/skip-times/\(mal)/\(episode)", [
            ("types", "op"), ("types", "ed"), ("types", "recap"), ("types", "mixed-op"), ("types", "mixed-ed"),
            ("episodeLength", "0"),
        ])
        guard let url, let answer = try? await http.getJSON(AniSkipAnswer.self, from: url) else { return MediaSegments() }
        return answer.segments
    }

    struct AnimeIds: Decodable {
        var myanimelist: Int?
        init(from decoder: Decoder) throws {
            myanimelist = try decoder.container(keyedBy: AnyKey.self).int("myanimelist")
        }
    }

    struct AniSkipAnswer: Decodable {
        var segments: MediaSegments

        private struct Result: Decodable {
            var kind: SegmentKind?
            var start: Double?
            var end: Double?
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: AnyKey.self)
                switch c.string("skipType") {
                case "op", "mixed-op": kind = .intro
                case "ed", "mixed-ed": kind = .credits
                case "recap": kind = .recap
                default: kind = nil
                }
                let interval = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("interval"))
                start = interval?.double("startTime")
                end = interval?.double("endTime")
            }
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            let results = c.list("results", of: Result.self)
            segments = MediaSegments(results.compactMap { result in
                guard let kind = result.kind, let start = result.start else { return nil }
                return MediaSegment(kind: kind, start: start, end: result.end, source: .aniSkip)
            })
        }
    }

    // MARK: Hilfen

    private static func url(_ base: String, _ query: [(String, String)]) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        return components?.url
    }
}
