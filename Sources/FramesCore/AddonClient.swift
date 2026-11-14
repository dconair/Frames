import Foundation

/// Spricht das Stremio-Addon-Protokoll: Manifest, Kataloge, Details, Streams, Untertitel.
public struct AddonClient: Sendable {
    private let http: any HTTPTransport

    public init(http: any HTTPTransport = URLSessionTransport()) {
        self.http = http
    }

    public func manifest(at transportURL: URL) async throws -> AddonManifest {
        try await http.getJSON(AddonManifest.self, from: transportURL)
    }

    public func catalog(_ ref: CatalogRef, extra: [(String, String)] = []) async throws -> CatalogPage {
        let url = try Self.resourceURL(addon: ref.addon, resource: "catalog", type: ref.catalog.type, id: ref.catalog.id, extra: extra)
        return try await http.getJSON(CatalogPage.self, from: url)
    }

    public func meta(addon: InstalledAddon, type: String, id: String) async throws -> Meta {
        let url = try Self.resourceURL(addon: addon, resource: "meta", type: type, id: id)
        return try await http.getJSON(MetaEnvelope.self, from: url).meta
    }

    public func streams(addon: InstalledAddon, type: String, id: String) async throws -> [Stream] {
        let url = try Self.resourceURL(addon: addon, resource: "stream", type: type, id: id)
        return try await http.getJSON(StreamsEnvelope.self, from: url).streams
    }

    public func subtitles(addon: InstalledAddon, type: String, id: String, extra: [(String, String)] = []) async throws -> [Subtitle] {
        let url = try Self.resourceURL(addon: addon, resource: "subtitles", type: type, id: id, extra: extra)
        return try await http.getJSON(SubtitlesEnvelope.self, from: url).subtitles
    }

    /// Baut `{basis}/{ressource}/{typ}/{id}[/{extra}].json`. Jeder Teil wird wie mit `encodeURIComponent` kodiert.
    static func resourceURL(
        addon: InstalledAddon, resource: String, type: String, id: String, extra: [(String, String)] = []
    ) throws -> URL {
        guard let base = addon.baseURL else { throw FramesError.invalidURL(addon.manifest.name) }
        var path = "\(base)/\(encode(resource))/\(encode(type))/\(encode(id))"
        if !extra.isEmpty {
            path += "/" + extra.map { "\(encode($0.0))=\(encode($0.1))" }.joined(separator: "&")
        }
        guard let url = URL(string: path + ".json") else { throw FramesError.invalidURL(addon.manifest.name) }
        return url
    }

    private static let unreserved: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-_.!~*'()")
        return set
    }()

    static func encode(_ component: String) -> String {
        // CharacterSet.alphanumerics enthält auch Buchstaben außerhalb von ASCII, die hier kodiert werden müssen.
        var result = ""
        for scalar in component.unicodeScalars {
            if scalar.isASCII, unreserved.contains(scalar) {
                result.unicodeScalars.append(scalar)
            } else {
                for byte in String(scalar).utf8 {
                    result += String(format: "%%%02X", byte)
                }
            }
        }
        return result
    }
}
