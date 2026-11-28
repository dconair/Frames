import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Besetzung mit Fotos und Rollen von TVmaze. Frei nutzbar, ohne Schlüssel, Lizenz CC BY-SA.
///
/// Serien findet TVmaze über die IMDb-id, dazu kommen die Gaststars der laufenden Folge.
/// Für Filme kennt TVmaze keine Besetzung, dort ergänzt es nur die Fotos zu den Namen aus dem Addon.
public struct CastService: Sendable {
    private let transport: HTTPTransport
    private let base: URL
    /// So viele Namen bekommen bei Filmen ein Foto. TVmaze erlaubt 20 Anfragen in zehn Sekunden.
    private let photoLimit = 12

    public init(transport: HTTPTransport = URLSessionTransport(), base: URL = URL(string: "https://api.tvmaze.com")!) {
        self.transport = transport
        self.base = base
    }

    public func cast(for request: XRayRequest) async -> [XRayPerson] {
        if request.isSeries, let imdb = request.imdbId, let show = await lookupShow(imdb: imdb) {
            async let main = showCast(show)
            async let guests = guestCast(show: show, season: request.season, episode: request.episode)
            let people = merge(await main, await guests)
            if !people.isEmpty { return people }
        }
        return await withPhotos(request.castNames)
    }

    // MARK: Serien

    private func lookupShow(imdb: String) async -> Int? {
        let show: TVmazeShow? = await get("lookup/shows", ["imdb": imdb])
        return show?.id
    }

    private func showCast(_ show: Int) async -> [XRayPerson] {
        let entries: [Lossy<TVmazeCredit>] = await get("shows/\(show)/cast") ?? []
        return entries.compactMap(\.value).map { $0.person(isGuest: false) }
    }

    private func guestCast(show: Int, season: Int?, episode: Int?) async -> [XRayPerson] {
        guard let season, let episode else { return [] }
        let found: TVmazeShow? = await get("shows/\(show)/episodebynumber", ["season": String(season), "number": String(episode)])
        guard let id = found?.id else { return [] }
        let entries: [Lossy<TVmazeCredit>] = await get("episodes/\(id)/guestcast") ?? []
        return entries.compactMap(\.value).map { $0.person(isGuest: true) }
    }

    /// Hauptbesetzung zuerst, dann die Gäste. Spielt jemand mehrere Rollen, wird daraus eine Zeile.
    private func merge(_ main: [XRayPerson], _ guests: [XRayPerson]) -> [XRayPerson] {
        var result = [XRayPerson]()
        var index = [String: Int]()
        for person in main + guests {
            if let at = index[person.name] {
                var existing = result[at]
                if let role = person.character, !(existing.character ?? "").contains(role) {
                    existing.character = [existing.character, role].compactMap { $0 }.joined(separator: " / ")
                }
                existing.photo = existing.photo ?? person.photo
                result[at] = existing
            } else {
                index[person.name] = result.count
                result.append(person)
            }
        }
        return result
    }

    // MARK: Filme

    /// Sucht zu jedem Namen ein Foto. Namen ohne Treffer bleiben ohne Foto in der Liste.
    private func withPhotos(_ names: [String]) async -> [XRayPerson] {
        var seen = Set<String>()
        let unique = names.filter { seen.insert($0).inserted }
        let photos = await withTaskGroup(of: (Int, URL?).self) { group in
            for (position, name) in unique.prefix(photoLimit).enumerated() {
                group.addTask { (position, await photo(of: name)) }
            }
            var found = [Int: URL]()
            for await (position, url) in group {
                if let url { found[position] = url }
            }
            return found
        }
        return unique.enumerated().map { XRayPerson(name: $0.element, photo: photos[$0.offset]) }
    }

    private func photo(of name: String) async -> URL? {
        let hits: [Lossy<TVmazePersonHit>] = await get("search/people", ["q": name]) ?? []
        let wanted = normalizedName(name)
        return hits.compactMap(\.value).first { normalizedName($0.person.name) == wanted && $0.person.image != nil }?.person.image
    }

    // MARK: Netz

    private func get<T: Decodable>(_ path: String, _ query: [String: String] = [:]) async -> T? {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { return nil }
        return try? await transport.getJSON(T.self, from: url)
    }
}

// MARK: Antworten von TVmaze

private struct TVmazeShow: Decodable {
    let id: Int
}

private struct TVmazeImage: Decodable {
    let medium: String?
    let original: String?

    var url: URL? { (medium ?? original).flatMap(URL.init(string:)) }
}

private struct TVmazePerson: Decodable {
    let name: String
    let image: URL?

    enum CodingKeys: String, CodingKey { case name, image }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        image = (try? c.decodeIfPresent(TVmazeImage.self, forKey: .image))?.url
    }
}

private struct TVmazeCharacter: Decodable {
    let name: String?
}

private struct TVmazeCredit: Decodable {
    let person: TVmazePerson
    let character: TVmazeCharacter?

    func person(isGuest: Bool) -> XRayPerson {
        XRayPerson(name: person.name, character: character?.name, photo: person.image, isGuest: isGuest)
    }
}

private struct TVmazePersonHit: Decodable {
    let person: TVmazePerson
}
