import XCTest
@testable import FramesCore

/// Liest echte, gekürzte Antworten von Cinemeta und der Konto-API.
final class DecodingTests: XCTestCase {
    func testManifest() throws {
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: fixture("manifest"))
        XCTAssertEqual(manifest.id, "com.linvo.cinemeta")
        XCTAssertEqual(manifest.name, "Cinemeta")
        XCTAssertEqual(manifest.types, ["movie", "series"])
        XCTAssertEqual(manifest.resources.map(\.name), ["catalog", "meta", "addon_catalog"])
        XCTAssertEqual(manifest.idPrefixes, ["tt"])

        let popular = try XCTUnwrap(manifest.catalogs.first)
        XCTAssertEqual(popular.name, "Popular")
        XCTAssertTrue(popular.supportsSearch)
        XCTAssertTrue(popular.supportsPaging)
        XCTAssertFalse(popular.hasRequiredExtra)

        let byYear = try XCTUnwrap(manifest.catalogs.first { $0.id == "year" })
        XCTAssertTrue(byYear.hasRequiredExtra, "Der Jahreskatalog verlangt ein Genre und taugt nicht als Home-Reihe")
    }

    func testCatalogExtraInLegacyNotation() throws {
        let json = #"{"type":"movie","id":"old","extraSupported":["search","skip"],"extraRequired":["search"]}"#
        let catalog = try JSONDecoder().decode(ManifestCatalog.self, from: Data(json.utf8))
        XCTAssertTrue(catalog.isSearchOnly)
        XCTAssertTrue(catalog.supportsPaging)
    }

    func testAddonCollection() async throws {
        let http = MockTransport()
        http.on("addonCollectionGet", data: try fixture("addonCollection"))
        let addons = try await StremioAPI(http: http).addonCollection(authKey: "key")

        XCTAssertEqual(addons.count, 7)
        XCTAssertEqual(addons.first?.manifest.name, "Cinemeta")
        XCTAssertEqual(addons.first?.isOfficial, true)
        XCTAssertEqual(addons.first?.baseURL, "https://v3-cinemeta.strem.io")

        // Das lokale Addon der Desktop-App und das im alten Protokoll sind von hier nicht ansprechbar.
        XCTAssertEqual(addons.reachable.count, 5)
        XCTAssertFalse(addons.reachable.contains { $0.transportURL.host == "127.0.0.1" })

        // Ressourcen in Objektform tragen eigene Typen und Präfixe.
        let local = try XCTUnwrap(addons.last)
        XCTAssertEqual(local.manifest.resources.first?.idPrefixes, ["local:", "bt:"])
        XCTAssertTrue(local.supports(resource: "stream", type: "movie", id: "tt123"))
        XCTAssertFalse(local.supports(resource: "meta", type: "movie", id: "tt123"))

        XCTAssertFalse(addons.homeCatalogs().isEmpty)
        XCTAssertTrue(addons.homeCatalogs().allSatisfy { !$0.catalog.hasRequiredExtra })
        XCTAssertEqual(addons.providing("meta", type: "series", id: "tt0903747").first?.manifest.name, "Cinemeta")
    }

    func testCatalogPage() throws {
        let page = try JSONDecoder().decode(CatalogPage.self, from: fixture("catalog"))
        XCTAssertEqual(page.metas.count, 3)
        XCTAssertTrue(page.hasMore)
        let first = try XCTUnwrap(page.metas.first)
        XCTAssertEqual(first.id, "tt7526136")
        XCTAssertEqual(first.type, "movie")
        XCTAssertEqual(first.directors, ["David Ayer"])
        XCTAssertEqual(first.imdbRating, "7.2")
        XCTAssertNotNil(first.poster)
        XCTAssertNotNil(first.released)
    }

    func testSeriesMeta() throws {
        let meta = try JSONDecoder().decode(MetaEnvelope.self, from: fixture("meta")).meta
        XCTAssertEqual(meta.name, "Breaking Bad")
        XCTAssertTrue(meta.isSeries)
        XCTAssertEqual(meta.seasons, [1, 2])
        XCTAssertEqual(meta.directors, [], "director ist hier null")
        XCTAssertEqual(meta.runtime, "49 min")

        let episodes = meta.episodes(inSeason: 1)
        XCTAssertEqual(episodes.count, 3)
        XCTAssertEqual(episodes.map { $0.episode ?? 0 }, episodes.map { $0.episode ?? 0 }.sorted())
        let episode = try XCTUnwrap(episodes.first)
        XCTAssertEqual(meta.streamId(for: episode), episode.id)
        XCTAssertTrue(episode.id.hasPrefix("tt0903747:1:"))
        XCTAssertNotNil(episode.code)
        XCTAssertNotNil(episode.released)
    }

    func testOneBrokenEntryDoesNotLoseTheList() throws {
        let json = #"{"metas":[{"id":"tt1","type":"movie","name":"A","imdbRating":8.1,"runtime":101},{"name":"ohne id"},"quatsch",{"id":"tt2","type":"movie","name":"B","genre":"Drama","director":"X"}]}"#
        let page = try JSONDecoder().decode(CatalogPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.metas.map(\.id), ["tt1", "tt2"])
        XCTAssertEqual(page.metas[0].imdbRating, "8.1")
        XCTAssertEqual(page.metas[0].runtime, "101")
        XCTAssertEqual(page.metas[1].genres, ["Drama"])
        XCTAssertEqual(page.metas[1].directors, ["X"])
    }

    func testSpecialsComeLast() {
        let meta = Meta(id: "tt1", type: "series", name: "X", videos: [
            Video(id: "a", title: "Special", season: 0, episode: 1),
            Video(id: "b", title: "Pilot", season: 1, episode: 1),
            Video(id: "c", title: "Zwei", season: 2, episode: 1),
        ])
        XCTAssertEqual(meta.seasons, [1, 2, 0])
    }

    func testLibraryItems() async throws {
        let http = MockTransport()
        http.on("datastoreGet", json: #"""
        {"result":[
         {"_id":"tt1","name":"Angefangen","type":"movie","poster":"https://img.example/1","removed":false,"temp":false,
          "_mtime":"2026-11-01T10:00:00.000Z","state":{"lastWatched":"2026-11-10T20:00:00.000Z","timeOffset":1800000,"duration":7200000,"video_id":"tt1","timesWatched":0}},
         {"_id":"tt2","name":"Fertig","type":"movie","removed":false,"temp":false,"_mtime":"2026-11-05T10:00:00.000Z",
          "state":{"lastWatched":"2026-11-12T20:00:00.000Z","timeOffset":7100000,"duration":7200000,"timesWatched":1}},
         {"_id":"tt3","name":"Nur Stand","type":"series","removed":true,"temp":true,
          "state":{"lastWatched":"2026-11-13T20:00:00.000Z","timeOffset":600000,"duration":2400000,"video_id":"tt3:1:2"}},
         {"_id":"tt4","name":"Entfernt","type":"movie","removed":true,"temp":false,"state":{"timeOffset":600000,"duration":2400000}},
         {"kaputt":true}
        ]}
        """#)
        let items = try await StremioAPI(http: http).libraryItems(authKey: "key")
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items.library.map(\.id), ["tt2", "tt1"])
        XCTAssertEqual(items.continueWatching.map(\.id), ["tt3", "tt1"])
        XCTAssertEqual(items[0].progress ?? 0, 0.25, accuracy: 0.001)
        XCTAssertEqual(items[2].videoId, "tt3:1:2")
    }
}
