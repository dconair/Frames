import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum FramesError: Error, Equatable, LocalizedError {
    case network(String)
    case http(Int)
    case api(code: Int?, message: String)
    case decoding(String)
    case invalidURL(String)
    case notLoggedIn

    public var errorDescription: String? {
        switch self {
        case .network(let message): return "Keine Verbindung: \(message)"
        case .http(let status): return "Der Server antwortet mit Fehler \(status)."
        case .api(_, let message): return message
        case .decoding: return "Die Antwort des Servers ließ sich nicht lesen."
        case .invalidURL: return "Die Adresse ist ungültig."
        case .notLoggedIn: return "Du bist nicht angemeldet."
        }
    }
}

extension FramesError {
    /// Stremio sperrt die Anmeldung, bis das Passwort auf stremio.com neu gesetzt ist.
    public var requiresPasswordReset: Bool {
        guard case .api(_, let message) = self else { return false }
        return message.lowercased().contains("password needs to be reset")
    }
}

public struct HTTPResponse: Sendable {
    public let status: Int
    public let data: Data

    public init(status: Int, data: Data) {
        self.status = status
        self.data = data
    }
}

/// Dünne Schicht über dem Netzwerk, damit sich alles ohne echte Anfragen testen lässt.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public struct URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: FramesError.network(error.localizedDescription))
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                continuation.resume(returning: HTTPResponse(status: status, data: data ?? Data()))
            }
            task.resume()
        }
    }
}

extension HTTPTransport {
    func getJSON<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let response = try await send(request)
        guard (200..<300).contains(response.status) else { throw FramesError.http(response.status) }
        return try decodeJSON(type, from: response.data)
    }
}

func decodeJSON<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    do {
        return try JSONDecoder().decode(type, from: data)
    } catch {
        throw FramesError.decoding(String(describing: error))
    }
}
