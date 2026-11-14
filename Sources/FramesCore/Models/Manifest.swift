import Foundation

/// Beschreibung eines Addons, wie sie unter `/manifest.json` steht.
public struct AddonManifest: Decodable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var version: String
    public var description: String?
    public var logo: String?
    public var types: [String]
    public var resources: [ManifestResource]
    public var idPrefixes: [String]?
    public var catalogs: [ManifestCatalog]
    public var isAdult: Bool
    public var isP2P: Bool
    public var needsConfiguration: Bool

    public init(
        id: String, name: String, version: String = "0.0.0", description: String? = nil, logo: String? = nil,
        types: [String] = [], resources: [ManifestResource] = [], idPrefixes: [String]? = nil,
        catalogs: [ManifestCatalog] = [], isAdult: Bool = false, isP2P: Bool = false, needsConfiguration: Bool = false
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.logo = logo
        self.types = types
        self.resources = resources
        self.idPrefixes = idPrefixes
        self.catalogs = catalogs
        self.isAdult = isAdult
        self.isP2P = isP2P
        self.needsConfiguration = needsConfiguration
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let id = c.string("id") else {
            throw DecodingError.keyNotFound(AnyKey("id"), .init(codingPath: c.codingPath, debugDescription: "Manifest ohne id"))
        }
        self.id = id
        name = c.string("name") ?? id
        version = c.string("version") ?? "0.0.0"
        description = c.string("description")
        logo = c.string("logo")
        types = c.strings("types")
        resources = c.list("resources")
        let prefixes = c.strings("idPrefixes")
        idPrefixes = prefixes.isEmpty ? nil : prefixes
        catalogs = c.list("catalogs")
        let hints = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("behaviorHints"))
        isAdult = hints?.bool("adult") ?? false
        isP2P = hints?.bool("p2p") ?? false
        needsConfiguration = hints?.bool("configurationRequired") ?? false
    }
}

/// Eine Ressource steht im Manifest entweder als bloßer Name oder als Objekt mit eigenen Typen und Präfixen.
public struct ManifestResource: Decodable, Sendable, Hashable {
    public var name: String
    public var types: [String]?
    public var idPrefixes: [String]?

    public init(name: String, types: [String]? = nil, idPrefixes: [String]? = nil) {
        self.name = name
        self.types = types
        self.idPrefixes = idPrefixes
    }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let name = try? single.decode(String.self) {
            self.init(name: name)
            return
        }
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let name = c.string("name") else {
            throw DecodingError.keyNotFound(AnyKey("name"), .init(codingPath: c.codingPath, debugDescription: "Ressource ohne Namen"))
        }
        let types = c.strings("types")
        let prefixes = c.strings("idPrefixes")
        self.init(name: name, types: types.isEmpty ? nil : types, idPrefixes: prefixes.isEmpty ? nil : prefixes)
    }
}

public struct ManifestCatalog: Decodable, Sendable, Hashable {
    public var type: String
    public var id: String
    public var name: String?
    public var extra: [CatalogExtra]

    public init(type: String, id: String, name: String? = nil, extra: [CatalogExtra] = []) {
        self.type = type
        self.id = id
        self.name = name
        self.extra = extra
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let type = c.string("type"), let id = c.string("id") else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Katalog ohne type oder id"))
        }
        self.type = type
        self.id = id
        name = c.string("name")
        var extra: [CatalogExtra] = c.list("extra")
        // Ältere Schreibweise: zwei Namenslisten statt der Objektliste.
        if extra.isEmpty {
            let required = Set(c.strings("extraRequired"))
            let supported = c.strings("extraSupported")
            let names = supported + required.filter { !supported.contains($0) }.sorted()
            extra = names.map { CatalogExtra(name: $0, isRequired: required.contains($0)) }
        }
        self.extra = extra
    }

    /// Kataloge mit Pflichtangaben (etwa ein Genre) lassen sich nicht ohne Auswahl als Reihe zeigen.
    public var hasRequiredExtra: Bool { extra.contains(where: \.isRequired) }
    public var supportsSearch: Bool { extra.contains { $0.name == "search" } }
    /// Reine Suchkataloge verlangen einen Suchbegriff.
    public var isSearchOnly: Bool { extra.contains { $0.name == "search" && $0.isRequired } }
    public var supportsPaging: Bool { extra.contains { $0.name == "skip" } }
}

public struct CatalogExtra: Decodable, Sendable, Hashable {
    public var name: String
    public var isRequired: Bool
    public var options: [String]

    public init(name: String, isRequired: Bool = false, options: [String] = []) {
        self.name = name
        self.isRequired = isRequired
        self.options = options
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let name = c.string("name") else {
            throw DecodingError.keyNotFound(AnyKey("name"), .init(codingPath: c.codingPath, debugDescription: "Extra ohne Namen"))
        }
        self.init(name: name, isRequired: c.bool("isRequired") ?? false, options: c.strings("options"))
    }
}
