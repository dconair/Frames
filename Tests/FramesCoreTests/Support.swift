import Foundation
import XCTest
@testable import FramesCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

func fixture(_ name: String) throws -> Data {
    let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

/// Beantwortet Anfragen aus einer Tabelle und merkt sich, was gefragt wurde.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [(String, Int, Data)] = []
    private var recorded: [URLRequest] = []

    /// `match` ist ein Teil der Adresse. Der erste passende Eintrag gewinnt.
    func on(_ match: String, status: Int = 200, data: Data) {
        lock.lock(); defer { lock.unlock() }
        routes.append((match, status, data))
    }

    func on(_ match: String, status: Int = 200, json: String) {
        on(match, status: status, data: Data(json.utf8))
    }

    var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        lock.lock(); defer { lock.unlock() }
        recorded.append(request)
        let address = request.url?.absoluteString ?? ""
        guard let route = routes.first(where: { address.contains($0.0) }) else {
            throw FramesError.network("keine Antwort hinterlegt")
        }
        return HTTPResponse(status: route.1, data: route.2)
    }
}

func addon(
    _ name: String, base: String = "https://addon.example", resources: [ManifestResource],
    types: [String] = ["movie", "series"], idPrefixes: [String]? = ["tt"], catalogs: [ManifestCatalog] = []
) -> InstalledAddon {
    InstalledAddon(
        transportURL: URL(string: "\(base)/manifest.json")!,
        manifest: AddonManifest(id: "test.\(name)", name: name, types: types, resources: resources, idPrefixes: idPrefixes, catalogs: catalogs)
    )
}
