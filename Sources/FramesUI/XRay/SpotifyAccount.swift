#if canImport(SwiftUI)
import SwiftUI
import Security
import FramesCore
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(AuthenticationServices) && !os(tvOS)
import AuthenticationServices
#endif

/// Das verbundene Spotify-Konto. Die Client-ID steht in den UserDefaults, der Zugang im Schlüsselbund.
///
/// Ohne Verbindung öffnet ein Song einfach die Spotify-Suche. Verbunden landet er mit einem Tipp in „Lieblingssongs“.
/// Auf dem Apple TV gibt es keinen Browser für die Anmeldung, dort zeigt das X-Ray einen QR-Code fürs Handy.
@MainActor
@Observable
final class SpotifyAccount {
    static let shared = SpotifyAccount()

    enum SaveState: Equatable {
        case saving
        case saved
        case notFound
        case failed(String)
    }

    private static let clientIdKey = "frames.spotify.clientId"
    private let keychain = KeychainSlot(service: "app.frames.spotify", account: "token")

    var clientId: String {
        didSet { UserDefaults.standard.set(clientId, forKey: Self.clientIdKey) }
    }

    private(set) var token: SpotifyToken?
    private(set) var isConnecting = false
    /// Zustand je Song aus dem X-Ray, nach `XRayTrack.id`.
    private(set) var states: [String: SaveState] = [:]

    var isConnected: Bool { token != nil }
    var hasValidClientId: Bool { SpotifyClient.isValidClientId(clientId) }

    /// Kann dieses Gerät sich selbst bei Spotify anmelden?
    static var supportsLogin: Bool {
        #if os(tvOS)
        return false
        #else
        return true
        #endif
    }

    private init() {
        clientId = UserDefaults.standard.string(forKey: Self.clientIdKey) ?? ""
        token = keychain.load().flatMap { try? JSONDecoder().decode(SpotifyToken.self, from: $0) }
    }

    private var client: SpotifyClient { SpotifyClient(clientId: clientId) }

    func disconnect() {
        store(nil)
        states = [:]
    }

    #if !os(tvOS)
    /// Meldet bei Spotify an. Gibt eine Meldung zurück, wenn es nicht geklappt hat.
    func connect(using session: WebAuthenticationSession) async -> String? {
        guard hasValidClientId else { return "Die Client-ID hat 32 Zeichen, nur Ziffern und a bis f." }
        isConnecting = true
        defer { isConnecting = false }
        let verifier = Self.randomString(length: 64)
        let state = Self.randomString(length: 16)
        let relay = LoopbackRelay(port: SpotifyClient.port, scheme: "frames")
        do {
            try relay.start()
        } catch {
            return "Frames konnte die Anmeldung nicht vorbereiten. Läuft sie schon in einem anderen Fenster?"
        }
        defer { relay.stop() }
        do {
            let url = client.authorizeURL(codeChallenge: Self.challenge(for: verifier), state: state)
            let callback = try await session.authenticate(using: url, callbackURLScheme: "frames", preferredBrowserSession: .ephemeral)
            let target = callback.absoluteString.replacingOccurrences(of: "frames://", with: "/")
            switch SpotifyClient.callback(from: target, expectedState: state) {
            case .failure(let error):
                return error.errorDescription
            case .success(let code):
                store(try await client.exchange(code: code, verifier: verifier))
                return nil
            }
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return nil
        } catch FramesError.notLoggedIn {
            return "Spotify hat die Anmeldung abgelehnt. Steht die Redirect-URI genau so in deiner Spotify-App?"
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? "Die Anmeldung bei Spotify hat nicht geklappt."
        }
    }
    #endif

    /// Sucht den Song bei Spotify und legt ihn in „Lieblingssongs“.
    func save(_ track: XRayTrack) async {
        guard states[track.id] != .saving else { return }
        states[track.id] = .saving
        do {
            var current = try await freshToken()
            var found: SpotifyTrack?
            do {
                found = try await client.findTrack(title: track.title, artist: track.artist, token: current)
            } catch FramesError.notLoggedIn {
                // Der Zugang ist abgelaufen, bevor die Uhr es wusste. Einmal erneuern und nochmal.
                current = try await client.refresh(current)
                store(current)
                found = try await client.findTrack(title: track.title, artist: track.artist, token: current)
            }
            guard let found else {
                states[track.id] = .notFound
                return
            }
            try await client.save(uris: [found.uri], token: current)
            states[track.id] = .saved
        } catch FramesError.notLoggedIn {
            disconnect()
            states[track.id] = .failed("Spotify-Verbindung abgelaufen. Bitte in den Einstellungen neu verbinden.")
        } catch {
            states[track.id] = .failed((error as? LocalizedError)?.errorDescription ?? "Speichern fehlgeschlagen.")
        }
    }

    private func freshToken() async throws -> SpotifyToken {
        guard let token else { throw FramesError.notLoggedIn }
        guard token.isExpired else { return token }
        let renewed = try await client.refresh(token)
        store(renewed)
        return renewed
    }

    private func store(_ token: SpotifyToken?) {
        self.token = token
        keychain.save(token.flatMap { try? JSONEncoder().encode($0) })
    }

    // MARK: PKCE

    static func randomString(length: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
    }

    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Ein Eintrag im Schlüsselbund.
struct KeychainSlot: Sendable {
    let service: String
    let account: String

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    func load() -> Data? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    func save(_ data: Data?) {
        SecItemDelete(query as CFDictionary)
        guard let data else { return }
        var query = query
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }
}
#endif
