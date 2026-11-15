#if canImport(SwiftUI)
import Foundation

/// Startschalter für die automatischen Tests im Simulator. In der ausgelieferten App ohne Wirkung.
enum TestHooks {
    #if DEBUG
    private static let process = ProcessInfo.processInfo

    /// Ohne Konto starten, mit der Grundausstattung an Addons, die Stremio jedem neuen Konto gibt.
    static var isGuest: Bool { process.arguments.contains("-frames-gast") }

    /// Zugangsdaten, mit denen sich die App beim Start selbst anmeldet.
    static var login: (email: String, password: String)? {
        guard let email = process.environment["FRAMES_TEST_EMAIL"], !email.isEmpty,
              let password = process.environment["FRAMES_TEST_PASSWORD"], !password.isEmpty else { return nil }
        return (email, password)
    }

    /// Ein Video, das statt der Hauptansicht sofort im Player läuft.
    static var video: URL? {
        process.environment["FRAMES_TEST_VIDEO"].flatMap(URL.init(string:))
    }
    #else
    static let isGuest = false
    static let login: (email: String, password: String)? = nil
    static let video: URL? = nil
    #endif
}
#endif
