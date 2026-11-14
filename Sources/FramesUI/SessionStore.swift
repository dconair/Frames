#if canImport(SwiftUI)
import Foundation
import Security
import FramesCore

/// Bewahrt die Sitzung im Schlüsselbund auf und die Einstellungen in den UserDefaults.
/// Das Passwort wird nie gespeichert, nur der Sitzungsschlüssel, den Stremio nach der Anmeldung ausgibt.
public struct SessionStore: Sendable {
    private let service: String
    private let settingsKey = "frames.playbackSettings"

    public init(service: String = "app.frames.stremio-session") {
        self.service = service
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "stremio",
        ]
    }

    public func loadSession() -> AuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    public func saveSession(_ session: AuthSession?) {
        SecItemDelete(baseQuery as CFDictionary)
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    public func loadSettings() -> PlaybackSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(PlaybackSettings.self, from: data)
        else { return PlaybackSettings() }
        return settings
    }

    public func saveSettings(_ settings: PlaybackSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: settingsKey)
    }
}
#endif
