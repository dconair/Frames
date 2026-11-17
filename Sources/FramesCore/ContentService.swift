import Foundation

/// Fragt mehrere Addons gleichzeitig ab und führt die Antworten zusammen.
public struct ContentService: Sendable {
    private let client: AddonClient

    public init(client: AddonClient = AddonClient()) {
        self.client = client
    }

    public func catalog(_ ref: CatalogRef, skip: Int = 0) async throws -> CatalogPage {
        try await client.catalog(ref, extra: skip > 0 ? [("skip", String(skip))] : [])
    }

    /// Details vom ersten Addon, das den Titel kennt, in der Reihenfolge des Nutzers.
    public func meta(type: String, id: String, addons: [InstalledAddon]) async throws -> Meta {
        var lastError: Error = FramesError.api(code: nil, message: "Kein Addon liefert Details zu diesem Titel.")
        for addon in addons.providing("meta", type: type, id: id) {
            do {
                return try await client.meta(addon: addon, type: type, id: id)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Streams aller passenden Addons. Fällt ein Addon aus, liefern die übrigen trotzdem.
    public func streams(type: String, id: String, addons: [InstalledAddon]) async -> [SourcedStream] {
        let providers = addons.providing("stream", type: type, id: id)
        let results = await withTaskGroup(of: (Int, [Stream]).self) { group in
            for (position, addon) in providers.enumerated() {
                group.addTask {
                    let streams = (try? await client.streams(addon: addon, type: type, id: id)) ?? []
                    return (position, streams)
                }
            }
            var collected = [(Int, [Stream])]()
            for await result in group { collected.append(result) }
            return collected.sorted { $0.0 < $1.0 }
        }
        var index = 0
        var all = [SourcedStream]()
        for (position, streams) in results {
            for stream in streams {
                let addon = providers[position]
                all.append(SourcedStream(
                    stream: stream, addonName: addon.manifest.name, index: index, isWebtorAddon: Webtor.isWebtor(addon)
                ))
                index += 1
            }
        }
        return all
    }

    /// Suche über alle Kataloge, die das unterstützen. Ergebnis je Katalog, leere fallen weg.
    public func search(_ query: String, addons: [InstalledAddon]) async -> [(CatalogRef, [Meta])] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        let catalogs = addons.searchCatalogs()
        let results = await withTaskGroup(of: (Int, [Meta]).self) { group in
            for (position, ref) in catalogs.enumerated() {
                group.addTask {
                    let page = try? await client.catalog(ref, extra: [("search", term)])
                    return (position, page?.metas ?? [])
                }
            }
            var collected = [(Int, [Meta])]()
            for await result in group { collected.append(result) }
            return collected.sorted { $0.0 < $1.0 }
        }
        return results.filter { !$0.1.isEmpty }.map { (catalogs[$0.0], $0.1) }
    }
}
