import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Offizielle Soundtracks aus MusicBrainz. Frei nutzbar, ohne Schlüssel, höchstens eine Anfrage pro Sekunde.
///
/// Gesucht werden Alben mit dem Typ „Soundtrack“, deren Titel mit dem Namen des Films oder der Serie beginnt.
/// Songs („Music From …“) stehen vor der Filmmusik („Original Score“).
public struct SoundtrackService: Sendable {
    private let transport: HTTPTransport
    private let base: URL
    private let pause: Duration
    /// MusicBrainz verlangt, dass sich jede Anwendung mit Namen meldet.
    static let userAgent = "Frames/0.1 (Stremio-Client)"

    public init(
        transport: HTTPTransport = URLSessionTransport(),
        base: URL = URL(string: "https://musicbrainz.org/ws/2")!,
        pause: Duration = .milliseconds(1100)
    ) {
        self.transport = transport
        self.base = base
        self.pause = pause
    }

    /// Bis zu `limit` Alben mit ihren Stücken. Wirft, wenn MusicBrainz nicht antwortet,
    /// damit die App „erneut versuchen“ anbieten kann statt „kein Soundtrack“ zu melden.
    public func soundtracks(for request: XRayRequest, limit: Int = 2) async throws -> [XRaySoundtrack] {
        let query = "releasegroup:\"\(request.name.replacingOccurrences(of: "\"", with: ""))\" AND secondarytype:soundtrack"
        guard let found: MBGroupSearch = try await get("release-group", ["query": query, "limit": "15"]) else { return [] }
        let picked = Self.pick(found.groups, for: request).prefix(limit)
        var result = [XRaySoundtrack]()
        for group in picked {
            let releases: MBReleaseBrowse? = try await get(
                "release", ["release-group": group.id, "inc": "recordings+artist-credits", "status": "official", "limit": "1"]
            )
            let tracks = releases?.releases.first?.tracks ?? []
            guard !tracks.isEmpty else { continue }
            result.append(XRaySoundtrack(id: group.id, title: group.title, year: group.year, isScore: group.isScore, tracks: tracks))
        }
        return result
    }

    /// Wählt aus den Treffern die Alben, die wirklich zu diesem Titel gehören.
    static func pick(_ groups: [MBGroup], for request: XRayRequest) -> [MBGroup] {
        let name = normalizedName(request.name)
        guard !name.isEmpty else { return [] }
        let matching = groups.filter { group in
            let title = normalizedName(group.title)
            guard title == name || title.hasPrefix(name + " ") else { return false }
            // Parodien, Cover-Alben und Hörspiele sind keine Soundtracks des Titels.
            let rest = title.dropFirst(name.count)
            if ["parody", "tribute", "inspired by", "karaoke", "cover"].contains(where: rest.contains) { return false }
            // Bei Filmen erscheint der Soundtrack fast immer im selben Jahr. So fallen Neuverfilmungen heraus.
            if !request.isSeries, let year = request.year, let released = group.year, abs(released - year) > 1 { return false }
            return true
        }
        return matching.enumerated().sorted { a, b in
            if a.element.isScore != b.element.isScore { return !a.element.isScore }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// nil heißt: MusicBrainz kennt das nicht. Ein Fehler heißt: keine Antwort.
    private func get<T: Decodable>(_ path: String, _ query: [String: String]) async throws -> T? {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = (query.merging(["fmt": "json"]) { a, _ in a })
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else { return nil }
        // MusicBrainz antwortet mit 503, wenn Anfragen zu dicht kommen, auch von anderen Geräten im selben Netz.
        // Dann mit wachsendem Abstand bis zu viermal versuchen.
        var lastError = FramesError.network("MusicBrainz antwortet nicht")
        for attempt in 0..<4 {
            await Self.throttle.wait(pause * (1 << attempt))
            do {
                let response = try await send(url)
                if response.status == 503 || response.status == 429 {
                    lastError = .http(response.status)
                    continue
                }
                guard (200..<300).contains(response.status) else { return nil }
                return try? decodeJSON(T.self, from: response.data)
            } catch let error as FramesError {
                lastError = error
            }
        }
        throw lastError
    }

    /// Hält alle Anfragen der App an MusicBrainz mindestens `pause` auseinander, auch über mehrere Player hinweg.
    static let throttle = Throttle()

    private func send(_ url: URL) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        do {
            return try await transport.send(request)
        } catch let error as FramesError {
            throw error
        } catch {
            throw FramesError.network(error.localizedDescription)
        }
    }
}

/// Reiht Anfragen mit festem Mindestabstand auf.
actor Throttle {
    private var next = ContinuousClock.now

    func wait(_ gap: Duration) async {
        let now = ContinuousClock.now
        let start = max(now, next)
        next = start + gap
        if start > now { try? await Task.sleep(until: start, clock: .continuous) }
    }
}

// MARK: Antworten von MusicBrainz

struct MBGroupSearch: Decodable {
    let groups: [MBGroup]

    enum CodingKeys: String, CodingKey { case groups = "release-groups" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        groups = (try? c.decode([Lossy<MBGroup>].self, forKey: .groups))?.compactMap(\.value) ?? []
    }
}

struct MBGroup: Decodable {
    let id: String
    let title: String
    let year: Int?

    init(id: String, title: String, year: Int? = nil) {
        self.id = id
        self.title = title
        self.year = year
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let id = c.string("id"), let title = c.string("title") else {
            throw DecodingError.keyNotFound(AnyKey("id"), .init(codingPath: c.codingPath, debugDescription: "Album ohne id"))
        }
        self.id = id
        self.title = title
        year = c.string("first-release-date").flatMap { Int($0.prefix(4)) }
    }

    var isScore: Bool {
        let title = normalizedName(self.title)
        return title.contains("score") && !title.contains("songs") && !title.contains("music from")
    }
}

struct MBReleaseBrowse: Decodable {
    let releases: [MBRelease]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        releases = c.list("releases")
    }
}

struct MBRelease: Decodable {
    let tracks: [XRayTrack]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let media: [MBMedium] = c.list("media")
        tracks = media.flatMap(\.tracks)
    }
}

private struct MBMedium: Decodable {
    let tracks: [XRayTrack]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        tracks = c.list("tracks", of: MBTrack.self).map(\.track)
    }
}

private struct MBTrack: Decodable {
    let track: XRayTrack

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let id = c.string("id"), let title = c.string("title") else {
            throw DecodingError.keyNotFound(AnyKey("id"), .init(codingPath: c.codingPath, debugDescription: "Stück ohne Titel"))
        }
        let credits: [MBCredit] = c.list("artist-credit")
        let artist = credits.map { $0.name + $0.joinphrase }.joined().trimmingCharacters(in: .whitespaces)
        let length = c.double("length").map { $0 / 1000 }
        track = XRayTrack(id: id, title: title, artist: artist, duration: length)
    }
}

private struct MBCredit: Decodable {
    let name: String
    let joinphrase: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        name = c.string("name") ?? ""
        joinphrase = (try? c.decode(String.self, forKey: AnyKey("joinphrase"))) ?? ""
    }
}
