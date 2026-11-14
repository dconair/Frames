import Foundation

/// Ein im Stremio-Konto installiertes Addon.
///
/// Achtung: `transportURL` enthält bei Debrid-Addons oft den persönlichen Schlüssel.
/// Die Adresse gehört deshalb nie in Logs, Fehlermeldungen oder Analysen.
public struct InstalledAddon: Decodable, Sendable, Hashable, Identifiable {
    public var transportURL: URL
    public var manifest: AddonManifest
    public var isOfficial: Bool
    public var isProtected: Bool

    public var id: String { transportURL.absoluteString }

    public init(transportURL: URL, manifest: AddonManifest, isOfficial: Bool = false, isProtected: Bool = false) {
        self.transportURL = transportURL
        self.manifest = manifest
        self.isOfficial = isOfficial
        self.isProtected = isProtected
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let url = c.string("transportUrl").flatMap(URL.init(string:)) else {
            throw DecodingError.keyNotFound(AnyKey("transportUrl"), .init(codingPath: c.codingPath, debugDescription: "Addon ohne Adresse"))
        }
        transportURL = url
        manifest = try c.decode(AddonManifest.self, forKey: AnyKey("manifest"))
        let flags = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("flags"))
        isOfficial = flags?.bool("official") ?? false
        isProtected = flags?.bool("protected") ?? false
    }

    /// Basisadresse ohne `/manifest.json`. `nil` bei Addons im alten Protokoll, die Frames nicht anspricht.
    public var baseURL: String? {
        let text = transportURL.absoluteString
        guard text.hasSuffix("/manifest.json") else { return nil }
        return String(text.dropLast("/manifest.json".count))
    }

    /// Addons, die auf dem Rechner mit der Stremio-Desktop-App laufen, sind von hier aus nicht erreichbar.
    public var isReachable: Bool {
        guard baseURL != nil, let host = transportURL.host?.lowercased() else { return false }
        return host != "127.0.0.1" && host != "localhost" && host != "::1"
    }

    /// Ob das Addon die Ressource (`meta`, `stream`, `subtitles`) für diesen Typ und diese id anbietet.
    public func supports(resource: String, type: String, id: String) -> Bool {
        guard let entry = manifest.resources.first(where: { $0.name == resource }) else { return false }
        let types = entry.types ?? manifest.types
        guard types.contains(type) else { return false }
        guard let prefixes = entry.idPrefixes ?? manifest.idPrefixes else { return true }
        return prefixes.contains { id.hasPrefix($0) }
    }

    /// Welche Arten von Inhalt das Addon liefert, für die Anzeige in der Addon-Liste.
    public var capabilities: [String] {
        var seen = Set<String>()
        return manifest.resources.map(\.name).filter { seen.insert($0).inserted }
    }
}

/// Verweis auf einen Katalog eines Addons, etwa „Popular – Filme“ aus Cinemeta.
public struct CatalogRef: Sendable, Hashable, Identifiable {
    public var addon: InstalledAddon
    public var catalog: ManifestCatalog

    public var id: String { "\(addon.id)|\(catalog.type)|\(catalog.id)" }
    public var title: String { catalog.name ?? addon.manifest.name }
    public var type: String { catalog.type }

    public init(addon: InstalledAddon, catalog: ManifestCatalog) {
        self.addon = addon
        self.catalog = catalog
    }
}

extension Array where Element == InstalledAddon {
    public var reachable: [InstalledAddon] { filter(\.isReachable) }

    /// Kataloge, die ohne weitere Angaben als Reihe auf dem Home-Screen stehen können.
    public func homeCatalogs(type: String? = nil) -> [CatalogRef] {
        reachable.flatMap { addon in
            addon.manifest.catalogs
                .filter { !$0.hasRequiredExtra && (type == nil || $0.type == type) }
                .map { CatalogRef(addon: addon, catalog: $0) }
        }
    }

    public func searchCatalogs() -> [CatalogRef] {
        reachable.flatMap { addon in
            addon.manifest.catalogs
                .filter { catalog in
                    catalog.supportsSearch && !catalog.extra.contains { $0.isRequired && $0.name != "search" }
                }
                .map { CatalogRef(addon: addon, catalog: $0) }
        }
    }

    public func providing(_ resource: String, type: String, id: String) -> [InstalledAddon] {
        reachable.filter { $0.supports(resource: resource, type: type, id: id) }
    }
}
