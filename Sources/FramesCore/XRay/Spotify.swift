import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Zugang zu Spotify, um Songs aus dem X-Ray in „Lieblingssongs“ zu legen.
///
/// Spotify gibt keinen allgemeinen Schlüssel für Apps wie Frames heraus. Jeder legt im Spotify-Dashboard
/// eine eigene App an und trägt deren Client-ID in Frames ein. Die Anmeldung läuft mit PKCE, ohne Geheimnis in der App.
/// Als Rücksprungadresse erlaubt Spotify nur HTTPS oder die eigene Maschine, deshalb nimmt Frames
/// den Code über eine kurz geöffnete Adresse auf 127.0.0.1 entgegen.
public struct SpotifyToken: Codable, Sendable, Hashable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date

    public init(accessToken: String, refreshToken: String?, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    public var isExpired: Bool { expiresAt.timeIntervalSinceNow < 60 }
}

public struct SpotifyTrack: Sendable, Hashable {
    public var uri: String
    public var name: String
    public var artist: String
    public var link: URL?
}

public struct SpotifyClient: Sendable {
    public static let port: UInt16 = 43821
    public static let redirectURI = "http://127.0.0.1:43821/spotify"
    public static let scopes = "user-library-modify user-library-read"

    public let clientId: String
    private let transport: HTTPTransport

    public init(clientId: String, transport: HTTPTransport = URLSessionTransport()) {
        self.clientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transport = transport
    }

    /// Spotify-Client-IDs sind 32 Zeichen aus Ziffern und a bis f.
    public static func isValidClientId(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count == 32 && trimmed.allSatisfy { $0.isHexDigit }
    }

    // MARK: Anmeldung

    public func authorizeURL(codeChallenge: String, state: String) -> URL {
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    /// Liest Code oder Fehler aus der Rücksprungadresse, etwa „/spotify?code=…&state=…“.
    public static func callback(from target: String, expectedState: String) -> Result<String, FramesError> {
        guard let components = URLComponents(string: target.hasPrefix("http") ? target : "http://127.0.0.1" + target) else {
            return .failure(.invalidURL(target))
        }
        let items = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }) { a, _ in a }
        if let error = items["error"] {
            return .failure(.api(code: nil, message: error == "access_denied" ? "Spotify-Anmeldung abgebrochen." : "Spotify meldet: \(error)"))
        }
        guard items["state"] == expectedState else {
            return .failure(.api(code: nil, message: "Die Antwort von Spotify passt nicht zu dieser Anmeldung."))
        }
        guard let code = items["code"], !code.isEmpty else {
            return .failure(.api(code: nil, message: "Spotify hat keinen Code geschickt."))
        }
        return .success(code)
    }

    public func exchange(code: String, verifier: String) async throws -> SpotifyToken {
        try await token([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": clientId,
            "code_verifier": verifier,
        ], previousRefresh: nil)
    }

    public func refresh(_ token: SpotifyToken) async throws -> SpotifyToken {
        guard let refreshToken = token.refreshToken else { throw FramesError.notLoggedIn }
        return try await self.token([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientId,
        ], previousRefresh: refreshToken)
    }

    private func token(_ form: [String: String], previousRefresh: String?) async throws -> SpotifyToken {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.formEncode(form).utf8)
        let response = try await transport.send(request)
        guard (200..<300).contains(response.status) else {
            if response.status == 400 { throw FramesError.notLoggedIn }
            throw FramesError.http(response.status)
        }
        let decoded = try decodeJSON(TokenResponse.self, from: response.data)
        return SpotifyToken(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token ?? previousRefresh,
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expires_in ?? 3600))
        )
    }

    // MARK: Songs

    /// Der beste Treffer für Titel und Künstler, oder nil.
    public func findTrack(title: String, artist: String, token: SpotifyToken) async throws -> SpotifyTrack? {
        var components = URLComponents(string: "https://api.spotify.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: Self.searchQuery(title: title, artist: artist)),
            URLQueryItem(name: "type", value: "track"),
            URLQueryItem(name: "limit", value: "5"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        let response = try await transport.send(request)
        try Self.check(response)
        let result = try decodeJSON(SearchResponse.self, from: response.data)
        let items = result.tracks?.items ?? []
        let wanted = normalizedName(Self.cleanTitle(title))
        let best = items.first { normalizedName($0.name).hasPrefix(wanted) } ?? items.first
        return best.map {
            SpotifyTrack(
                uri: $0.uri, name: $0.name, artist: $0.artists.map(\.name).joined(separator: ", "),
                link: $0.external_urls?.spotify.flatMap(URL.init(string:))
            )
        }
    }

    /// Legt die Songs in „Lieblingssongs“ des angemeldeten Kontos.
    public func save(uris: [String], token: SpotifyToken) async throws {
        var components = URLComponents(string: "https://api.spotify.com/v1/me/library")!
        components.queryItems = [URLQueryItem(name: "uris", value: uris.prefix(40).joined(separator: ","))]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        let response = try await transport.send(request)
        try Self.check(response)
    }

    // MARK: Ohne Anmeldung

    /// Öffnet die Suche in Spotify. Auf dem iPhone springt der Link direkt in die Spotify-App.
    public static func searchLink(title: String, artist: String) -> URL {
        let term = "\(title) \(artist)".trimmingCharacters(in: .whitespaces)
        let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) ?? ""
        return URL(string: "https://open.spotify.com/search/\(encoded)")!
    }

    static func searchQuery(title: String, artist: String) -> String {
        let clean = cleanTitle(title)
        let firstArtist = artist.components(separatedBy: CharacterSet(charactersIn: ",&")).first?
            .replacingOccurrences(of: " feat.", with: "")
            .trimmingCharacters(in: .whitespaces) ?? artist
        return firstArtist.isEmpty ? "track:\(clean)" : "track:\(clean) artist:\(firstArtist)"
    }

    /// Zusätze wie „(From "Oppenheimer")“ oder „- Remastered“ verwirren die Suche.
    static func cleanTitle(_ title: String) -> String {
        var clean = title
        for marker in [" (", " [", " - "] {
            if let range = clean.range(of: marker) { clean = String(clean[..<range.lowerBound]) }
        }
        return clean
    }

    static func formEncode(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
    }

    private static func check(_ response: HTTPResponse) throws {
        switch response.status {
        case 200..<300: return
        case 401: throw FramesError.notLoggedIn
        case 403:
            throw FramesError.api(code: 403, message: "Spotify lässt dieses Konto nicht zu. Ist es in deiner Spotify-App unter „User Management“ eingetragen?")
        default: throw FramesError.http(response.status)
        }
    }
}

// MARK: Antworten von Spotify

private struct TokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int?
}

private struct SearchResponse: Decodable {
    struct Page: Decodable { let items: [Item] }
    struct Item: Decodable {
        let uri: String
        let name: String
        let artists: [Artist]
        let external_urls: Links?
    }
    struct Artist: Decodable { let name: String }
    struct Links: Decodable { let spotify: String? }
    let tracks: Page?
}
