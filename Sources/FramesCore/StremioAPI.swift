import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Anmeldung am Stremio-Konto. Der `authKey` ist das Einzige, was Frames danach aufbewahrt.
public struct AuthSession: Codable, Sendable, Hashable {
    public var authKey: String
    public var userId: String
    public var email: String

    public init(authKey: String, userId: String, email: String) {
        self.authKey = authKey
        self.userId = userId
        self.email = email
    }
}

/// Die Konto-API von Stremio: Anmeldung, installierte Addons, Bibliothek.
public struct StremioAPI: Sendable {
    public static let defaultBaseURL = URL(string: "https://api.strem.io/api/")!

    private let http: any HTTPTransport
    private let baseURL: URL

    public init(http: any HTTPTransport = URLSessionTransport(), baseURL: URL = StremioAPI.defaultBaseURL) {
        self.http = http
        self.baseURL = baseURL
    }

    public func login(email: String, password: String) async throws -> AuthSession {
        let result: LoginResult = try await call("login", body: [
            "type": "Login", "email": email, "password": password, "facebook": false,
        ])
        return AuthSession(authKey: result.authKey, userId: result.user.id, email: result.user.email ?? email)
    }

    public func logout(authKey: String) async throws {
        let _: Ignored = try await call("logout", body: ["type": "Logout", "authKey": authKey])
    }

    /// Die im Konto installierten Addons in der Reihenfolge des Nutzers.
    public func addonCollection(authKey: String) async throws -> [InstalledAddon] {
        let result: AddonCollectionResult = try await call("addonCollectionGet", body: [
            "type": "AddonCollectionGet", "authKey": authKey, "update": true,
        ])
        return result.addons
    }

    /// Alle Einträge der Bibliothek, auch entfernte. Die Auswahl trifft `LibraryItem.isInLibrary`.
    public func libraryItems(authKey: String) async throws -> [LibraryItem] {
        let result: [Lossy<LibraryItem>] = try await call("datastoreGet", body: [
            "authKey": authKey, "collection": "libraryItem", "ids": [String](), "all": true,
        ])
        return result.compactMap(\.value)
    }

    private func call<T: Decodable>(_ method: String, body: [String: Any]) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(method))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let response = try await http.send(request)
        guard (200..<300).contains(response.status) else { throw FramesError.http(response.status) }
        let envelope = try decodeJSON(Envelope<T>.self, from: response.data)
        if let error = envelope.error {
            throw FramesError.api(code: error.code, message: error.message)
        }
        guard let result = envelope.result else {
            throw FramesError.decoding("Antwort ohne result")
        }
        return result
    }
}

private struct Envelope<T: Decodable>: Decodable {
    let result: T?
    let error: APIError?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        error = c.value("error")
        if error == nil, c.contains(AnyKey("result")) {
            result = try c.decode(T.self, forKey: AnyKey("result"))
        } else {
            result = nil
        }
    }
}

private struct APIError: Decodable {
    let code: Int?
    let message: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        code = c.int("code")
        message = c.string("message") ?? "Unbekannter Fehler"
    }
}

private struct LoginResult: Decodable {
    struct User: Decodable {
        let id: String
        let email: String?
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            id = c.string("_id") ?? ""
            email = c.string("email")
        }
    }
    let authKey: String
    let user: User
}

private struct AddonCollectionResult: Decodable {
    let addons: [InstalledAddon]
    init(from decoder: Decoder) throws {
        addons = try decoder.container(keyedBy: AnyKey.self).list("addons")
    }
}

private struct Ignored: Decodable {
    init(from decoder: Decoder) throws {}
}
