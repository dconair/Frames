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
    /// Ohne `authKey` liefert Stremio die Grundausstattung, die jedes neue Konto bekommt.
    public func addonCollection(authKey: String?) async throws -> [InstalledAddon] {
        let result: AddonCollectionResult = try await call("addonCollectionGet", body: [
            "type": "AddonCollectionGet", "authKey": authKey ?? NSNull(), "update": true,
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

    /// Schreibt den Wiedergabestand ins Konto und gibt den Eintrag zurück, wie er jetzt gespeichert ist.
    /// Der vorhandene Eintrag wird dafür frisch geholt, damit nichts überschrieben wird, was sich
    /// inzwischen auf einem anderen Gerät geändert hat.
    @discardableResult
    public func saveProgress(_ progress: WatchProgress, authKey: String, now: Date = Date()) async throws -> LibraryItem? {
        let existing = try await rawResult("datastoreGet", body: [
            "authKey": authKey, "collection": "libraryItem", "ids": [progress.metaId], "all": false,
        ]) as? [[String: Any]]
        let item = LibraryProgress.apply(progress, to: existing?.first, now: now)
        _ = try await rawResult("datastorePut", body: [
            "authKey": authKey, "collection": "libraryItem", "changes": [item],
        ])
        let data = try JSONSerialization.data(withJSONObject: item)
        return try? JSONDecoder().decode(LibraryItem.self, from: data)
    }

    /// Installiert ein Addon im Stremio-Konto, so wie es die Stremio-App tut. Danach kennen es alle Geräte.
    ///
    /// Die Liste wird dafür frisch geholt und unverändert zurückgeschrieben, nur um das neue Addon ergänzt.
    /// Ein schon vorhandenes Addon mit derselben id wird an seinem Platz ersetzt, etwa nach einer neuen
    /// Webtor-Adresse. Gibt das Manifest des installierten Addons zurück.
    @discardableResult
    public func installAddon(at transportURL: URL, authKey: String) async throws -> AddonManifest {
        var request = URLRequest(url: transportURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let response = try await http.send(request)
        guard (200..<300).contains(response.status) else { throw FramesError.http(response.status) }
        let manifest = try decodeJSON(AddonManifest.self, from: response.data)
        guard let rawManifest = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
            throw FramesError.decoding("Manifest ist kein Objekt")
        }
        if manifest.needsConfiguration {
            throw FramesError.api(code: nil, message: "Diese Adresse ist noch nicht eingerichtet. "
                + "Richte das Addon auf seiner Seite ein und füge die persönliche Adresse ein, die du dort bekommst.")
        }

        let result = try await rawResult("addonCollectionGet", body: [
            "type": "AddonCollectionGet", "authKey": authKey, "update": true,
        ]) as? [String: Any]
        // Ohne lesbare Liste wird nichts geschrieben: sonst gingen die vorhandenen Addons verloren.
        guard var addons = result?["addons"] as? [[String: Any]], !addons.isEmpty else {
            throw FramesError.decoding("Addon-Liste des Kontos nicht lesbar")
        }
        let entry: [String: Any] = [
            "transportUrl": transportURL.absoluteString,
            "transportName": "",
            "manifest": rawManifest,
            "flags": ["official": false, "protected": false],
        ]
        if addons.contains(where: { $0["transportUrl"] as? String == transportURL.absoluteString }) {
            return manifest
        }
        if let index = addons.firstIndex(where: { ($0["manifest"] as? [String: Any])?["id"] as? String == manifest.id }) {
            addons[index] = entry
        } else {
            addons.append(entry)
        }
        _ = try await rawResult("addonCollectionSet", body: [
            "type": "AddonCollectionSet", "authKey": authKey, "addons": addons,
        ])
        return manifest
    }

    private func post(_ method: String, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(method))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let response = try await http.send(request)
        guard (200..<300).contains(response.status) else { throw FramesError.http(response.status) }
        return response.data
    }

    /// Wie `call`, aber ohne festen Typ. Für Einträge, die unverändert zurückgeschrieben werden.
    private func rawResult(_ method: String, body: [String: Any]) async throws -> Any {
        let data = try await post(method, body: body)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FramesError.decoding("Antwort ist kein Objekt")
        }
        if let error = object["error"] as? [String: Any] {
            throw FramesError.api(
                code: (error["code"] as? NSNumber)?.intValue,
                message: error["message"] as? String ?? "Unbekannter Fehler"
            )
        }
        guard let result = object["result"] else { throw FramesError.decoding("Antwort ohne result") }
        return result
    }

    private func call<T: Decodable>(_ method: String, body: [String: Any]) async throws -> T {
        let data = try await post(method, body: body)
        let envelope = try decodeJSON(Envelope<T>.self, from: data)
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
