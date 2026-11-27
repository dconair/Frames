#if canImport(Network) && !os(tvOS)
import Foundation
import Network

/// Nimmt die Rückleitung von Spotify auf 127.0.0.1 an und schickt sie als `frames://…` weiter.
///
/// Spotify erlaubt als Rücksprung nur HTTPS oder eine Adresse auf dem eigenen Gerät. Das Anmeldefenster ruft
/// nach dem Login `http://127.0.0.1:43821/spotify?code=…` auf, hier kommt eine Weiterleitung auf
/// `frames://spotify?code=…` zurück, und die fängt das Anmeldefenster ab. Der Code verlässt das Gerät nicht.
final class LoopbackRelay: @unchecked Sendable {
    private let port: UInt16
    private let scheme: String
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "app.frames.loopback")

    init(port: UInt16, scheme: String) {
        self.port = port
        self.scheme = scheme
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [scheme] data, _, _, _ in
            let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            // Erste Zeile: „GET /spotify?code=…&state=… HTTP/1.1“
            let target = request.split(separator: "\r\n").first?.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let path = target.hasPrefix("/") ? String(target.dropFirst()) : target
            let location = "\(scheme)://\(path)"
            let body = "<html><body style=\"background:#0E1012;color:#E8EAED;font-family:-apple-system\">"
                + "<p>Zurück zu Frames …</p></body></html>"
            let response = "HTTP/1.1 302 Found\r\nLocation: \(location)\r\nContent-Type: text/html; charset=utf-8\r\n"
                + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
#endif
