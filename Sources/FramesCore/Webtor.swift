import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Webtor holt Torrents auf seinen eigenen Servern und liefert Frames einen gewöhnlichen Link.
/// Auf dem Gerät läuft dabei kein Torrent, es passt also zur Regel von Frames.
///
/// Das Addon ist persönlich: die Adresse aus dem Webtor-Profil trägt den Schlüssel des Kontos und ist
/// damit die ganze Anmeldung. Sie gehört wie die Adressen der Debrid-Addons nie in Logs.
public enum Webtor {
    public static let manifestID = "org.stremio.webtor.io"

    public static func isWebtor(_ addon: InstalledAddon) -> Bool {
        if addon.manifest.id == manifestID { return true }
        let host = addon.transportURL.host?.lowercased() ?? ""
        return host == "webtor.io" || host.hasSuffix(".webtor.io")
    }

    /// Ohne Schlüssel in der Adresse liefert das Addon nichts. So sieht die Adresse aus dem Addon-Verzeichnis aus.
    public static func isSignedIn(_ addon: InstalledAddon) -> Bool {
        !addon.manifest.needsConfiguration && addon.transportURL.path.contains("/token/")
    }

    /// Webtor gibt für jeden Stream einen Link auf sich selbst aus, der erst beim Abspielen zur Datei weiterleitet.
    public static func isResolveLink(_ url: URL) -> Bool {
        url.path.contains("/stremio/resolve/")
    }

    /// Statt des Films leitet Webtor ohne bezahlten Tarif auf ein kurzes Hinweisvideo um.
    public static func isPaywallClip(_ url: URL) -> Bool {
        url.path.contains("/pub/stremio/paywall")
    }
}

/// Antwort auf eine Anfrage, bei der Weiterleitungen nicht verfolgt werden.
public struct RedirectReply: Sendable, Equatable {
    public var status: Int
    public var location: URL?

    public init(status: Int, location: URL? = nil) {
        self.status = status
        self.location = location
    }
}

/// Klärt vor dem Start des Players, wohin ein Webtor-Link führt.
///
/// So bekommt der Player gleich die Adresse der Datei, und was Webtor ablehnt, erscheint als verständlicher
/// Hinweis statt als Fehler des Players oder als Hinweisvideo. Alle anderen Links gehen unverändert durch.
public struct StreamLinkResolver: Sendable {
    public enum Outcome: Sendable, Equatable {
        case play(URL)
        case blocked(String)
    }

    public typealias Probe = @Sendable (URL, [String: String]) async throws -> RedirectReply

    private let probe: Probe

    public init(probe: @escaping Probe = StreamLinkResolver.liveProbe) {
        self.probe = probe
    }

    public func resolve(_ url: URL, headers: [String: String] = [:]) async -> Outcome {
        guard Webtor.isResolveLink(url) else { return .play(url) }
        // Gelingt die Nachfrage nicht, soll es der Player selbst versuchen.
        guard let reply = try? await probe(url, headers) else { return .play(url) }
        switch reply.status {
        case 300..<400:
            guard let target = reply.location else { return .play(url) }
            if Webtor.isPaywallClip(target) {
                return .blocked("Diese Quelle müsste Webtor selbst ausliefern, und das geht nur mit einem bezahlten Webtor-Tarif. "
                    + "Quellen, die schon bei deinem Debrid-Dienst liegen, laufen ohne.")
            }
            return .play(target)
        case 401:
            return .blocked("Webtor nimmt den Link nicht mehr an. Lade die Quellen neu. "
                + "Hilft das nicht, erzeuge im Webtor-Profil eine neue Addon-Adresse und füge sie unter Addons ein.")
        case 403:
            return .blocked("Webtor gibt diesen Torrent für dein Konto nicht frei.")
        case 404:
            return .blocked("Webtor findet zu dieser Quelle keine abspielbare Datei. Nimm eine andere Quelle.")
        case 500..<600:
            return .blocked("Webtor konnte den Stream gerade nicht bereitstellen. Versuch es gleich noch einmal oder nimm eine andere Quelle.")
        default:
            return .play(url)
        }
    }

    /// Fragt mit HEAD an und folgt der Weiterleitung nicht. Webtor beantwortet HEAD wie GET.
    public static let liveProbe: Probe = { url, headers in
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 45
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { _, response, error in
                guard let reply = response as? HTTPURLResponse else {
                    continuation.resume(throwing: FramesError.network(error?.localizedDescription ?? "keine Antwort"))
                    return
                }
                let location = reply.value(forHTTPHeaderField: "Location").flatMap { URL(string: $0, relativeTo: url)?.absoluteURL }
                continuation.resume(returning: RedirectReply(status: reply.statusCode, location: location))
            }
            task.resume()
        }
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// Liest eine Addon-Adresse, wie sie jemand einfügt: mit `stremio://`, mit Leerzeichen, mit oder ohne `/manifest.json`.
public enum AddonAddress {
    public static func normalize(_ text: String) -> URL? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(" ") else { return nil }
        if value.lowercased().hasPrefix("stremio://") {
            value = "https://" + value.dropFirst("stremio://".count)
        } else if !value.contains("://") {
            value = "https://" + value
        }
        guard var parts = URLComponents(string: value), let host = parts.host, host.contains(".") else { return nil }
        guard parts.scheme?.lowercased() == "https" else { return nil }
        if !parts.path.hasSuffix("/manifest.json") {
            // Webtor zeigt im Profil auch die Einrichtungsseite. Die Adresse davor ist dieselbe.
            var path = parts.path
            for suffix in ["/configure", "/"] where path.hasSuffix(suffix) { path.removeLast(suffix.count) }
            parts.path = path + "/manifest.json"
        }
        return parts.url
    }
}
