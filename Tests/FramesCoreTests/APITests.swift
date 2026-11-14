import XCTest
@testable import FramesCore

final class APITests: XCTestCase {
    func testLoginSendsCredentialsAndReturnsSession() async throws {
        let http = MockTransport()
        http.on("/api/login", json: #"{"result":{"authKey":"abc123","user":{"_id":"u1","email":"du@beispiel.de"}}}"#)
        let session = try await StremioAPI(http: http).login(email: "du@beispiel.de", password: "geheim")

        XCTAssertEqual(session, AuthSession(authKey: "abc123", userId: "u1", email: "du@beispiel.de"))
        let request = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.strem.io/api/login")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["type"] as? String, "Login")
        XCTAssertEqual(body["email"] as? String, "du@beispiel.de")
        XCTAssertEqual(body["password"] as? String, "geheim")
    }

    func testWrongPasswordSurfacesServerMessage() async {
        let http = MockTransport()
        http.on("/api/login", json: #"{"error":{"code":3,"message":"Wrong passphrase","wrongPass":true}}"#)
        do {
            _ = try await StremioAPI(http: http).login(email: "a@b.c", password: "x")
            XCTFail("Anmeldung hätte scheitern müssen")
        } catch {
            XCTAssertEqual(error as? FramesError, .api(code: 3, message: "Wrong passphrase"))
        }
    }

    func testServerErrorStatus() async {
        let http = MockTransport()
        http.on("/api/login", status: 502, json: "Bad Gateway")
        do {
            _ = try await StremioAPI(http: http).login(email: "a@b.c", password: "x")
            XCTFail()
        } catch {
            XCTAssertEqual(error as? FramesError, .http(502))
        }
    }

    func testResourceURLs() throws {
        // Debrid-Addons tragen ihre Einstellungen als Pfadteil in der Adresse.
        let debrid = addon("Debrid", base: "https://debrid.example/realdebrid=KEY%7Csort=quality", resources: [.init(name: "stream")])
        XCTAssertEqual(
            try AddonClient.resourceURL(addon: debrid, resource: "stream", type: "series", id: "tt0903747:1:7").absoluteString,
            "https://debrid.example/realdebrid=KEY%7Csort=quality/stream/series/tt0903747%3A1%3A7.json"
        )
        let cinemeta = addon("Cinemeta", base: "https://v3-cinemeta.strem.io", resources: [.init(name: "catalog")])
        XCTAssertEqual(
            try AddonClient.resourceURL(addon: cinemeta, resource: "catalog", type: "movie", id: "top", extra: [("search", "Zwölf Uhr & mehr"), ("skip", "50")]).absoluteString,
            "https://v3-cinemeta.strem.io/catalog/movie/top/search=Zw%C3%B6lf%20Uhr%20%26%20mehr&skip=50.json"
        )
    }

    func testLegacyAddonHasNoResourceURL() {
        let legacy = InstalledAddon(
            transportURL: URL(string: "https://opensubtitles.strem.io/stremio/v1")!,
            manifest: AddonManifest(id: "old", name: "Alt", types: ["movie"], resources: [.init(name: "subtitles")])
        )
        XCTAssertNil(legacy.baseURL)
        XCTAssertFalse(legacy.isReachable)
        XCTAssertThrowsError(try AddonClient.resourceURL(addon: legacy, resource: "subtitles", type: "movie", id: "tt1"))
    }

    func testStreamsMergeAcrossAddonsAndSurviveFailures() async {
        let http = MockTransport()
        http.on("a.example/stream/movie/tt1.json", json: #"""
        {"streams":[
          {"name":"[RD+] A\n2160p","description":"Film.2160p.DV.Atmos.mkv\n58.2 GB","url":"https://dl.example/a.mkv","behaviorHints":{"bingeGroup":"a|2160p","filename":"Film.2160p.DV.Atmos.mkv","videoSize":62491000000}},
          {"name":"A 1080p","infoHash":"0123456789abcdef0123456789abcdef01234567","fileIdx":0}
        ]}
        """#)
        http.on("b.example/stream", status: 500, json: "kaputt")
        http.on("c.example/stream/movie/tt1.json", json: #"{"streams":[{"title":"C 720p","url":"https://dl.example/c.mp4"}]}"#)
        let addons = [
            addon("A", base: "https://a.example", resources: [.init(name: "stream")]),
            addon("B", base: "https://b.example", resources: [.init(name: "stream")]),
            addon("C", base: "https://c.example", resources: [.init(name: "stream")]),
            addon("Nur Serien", base: "https://d.example", resources: [.init(name: "stream")], types: ["series"]),
            addon("Lokal", base: "http://127.0.0.1:11470/local-addon", resources: [.init(name: "stream")]),
        ]
        let streams = await ContentService(client: AddonClient(http: http)).streams(type: "movie", id: "tt1", addons: addons)

        XCTAssertEqual(streams.map(\.addonName), ["A", "A", "C"])
        XCTAssertEqual(streams[0].info.sizeBytes, 62_491_000_000, "Die Angabe des Addons schlägt die aus dem Text")
        XCTAssertEqual(streams[1].stream.kind, .torrent)
        XCTAssertFalse(http.requests.contains { $0.url?.host == "d.example" || $0.url?.host == "127.0.0.1" })

        // Nur direkte Links bleiben übrig, der beste zuerst.
        let ranked = StreamRanker.ranked(streams)
        XCTAssertEqual(ranked.map { $0.stream.playableURL?.lastPathComponent }, ["a.mkv", "c.mp4"])
    }

    func testMetaFallsBackToNextAddon() async throws {
        let http = MockTransport()
        http.on("first.example/meta", status: 404, json: "{}")
        http.on("second.example/meta/movie/tt1.json", json: #"{"meta":{"id":"tt1","type":"movie","name":"Gefunden"}}"#)
        let addons = [
            addon("Eins", base: "https://first.example", resources: [.init(name: "meta")]),
            addon("Zwei", base: "https://second.example", resources: [.init(name: "meta")]),
        ]
        let meta = try await ContentService(client: AddonClient(http: http)).meta(type: "movie", id: "tt1", addons: addons)
        XCTAssertEqual(meta.name, "Gefunden")
    }

    func testSearchSkipsEmptyCatalogs() async {
        let http = MockTransport()
        http.on("a.example/catalog/movie/top/search=dune.json", json: #"{"metas":[{"id":"tt1","type":"movie","name":"Dune"}]}"#)
        http.on("a.example/catalog/series/top/search=dune.json", json: #"{"metas":[]}"#)
        let search = CatalogExtra(name: "search")
        let addons = [addon("A", base: "https://a.example", resources: [.init(name: "catalog")], catalogs: [
            ManifestCatalog(type: "movie", id: "top", name: "Filme", extra: [search]),
            ManifestCatalog(type: "series", id: "top", name: "Serien", extra: [search]),
            ManifestCatalog(type: "movie", id: "neu", name: "Ohne Suche"),
        ])]
        let results = await ContentService(client: AddonClient(http: http)).search("  dune ", addons: addons)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.0.title, "Filme")
        XCTAssertEqual(results.first?.1.first?.name, "Dune")
        XCTAssertEqual(http.requests.count, 2)
    }
}
