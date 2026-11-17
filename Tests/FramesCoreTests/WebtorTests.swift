import XCTest
@testable import FramesCore

final class WebtorTests: XCTestCase {
    private let link = URL(string: "https://webtor.io/token/abc/stremio/resolve/eyJhbGciOiJIUzI1NiJ9.x.y")!

    private func resolver(_ reply: RedirectReply?) -> StreamLinkResolver {
        StreamLinkResolver { _, _ in
            guard let reply else { throw FramesError.network("aus") }
            return reply
        }
    }

    func testRecognisesTheAddon() throws {
        let data = Data(#"{"transportUrl":"https://webtor.io/token/abc/stremio/manifest.json","manifest":{"id":"org.stremio.webtor.io","name":"Webtor.io","version":"0.1.0","types":["movie","series"],"catalogs":[{"type":"movie","id":"Webtor.io"}],"resources":["stream","catalog","meta"]}}"#.utf8)
        let installed = try JSONDecoder().decode(InstalledAddon.self, from: data)
        XCTAssertTrue(Webtor.isWebtor(installed))
        XCTAssertTrue(Webtor.isSignedIn(installed))
        XCTAssertTrue(installed.supports(resource: "stream", type: "series", id: "tt0903747:1:1"))
        XCTAssertEqual([installed].homeCatalogs().map(\.title), ["Webtor.io"])

        let bare = Data(#"{"transportUrl":"https://webtor.io/stremio/manifest.json","manifest":{"id":"org.stremio.webtor.io","name":"Webtor.io","types":["movie"],"resources":["stream"],"behaviorHints":{"configurable":true,"configurationRequired":true}}}"#.utf8)
        let unconfigured = try JSONDecoder().decode(InstalledAddon.self, from: bare)
        XCTAssertTrue(Webtor.isWebtor(unconfigured))
        XCTAssertFalse(Webtor.isSignedIn(unconfigured))

        XCTAssertFalse(Webtor.isWebtor(addon("Anderes", resources: [ManifestResource(name: "stream")])))
        let selfHosted = InstalledAddon(
            transportURL: URL(string: "https://mein.server/token/abc/stremio/manifest.json")!,
            manifest: AddonManifest(id: Webtor.manifestID, name: "Webtor.io")
        )
        XCTAssertTrue(Webtor.isWebtor(selfHosted))
    }

    func testOtherLinksPassThroughUntouched() async {
        let direct = URL(string: "https://cdn.example/film.mkv")!
        let outcome = await StreamLinkResolver { _, _ in
            XCTFail("Fremde Links werden nicht angefragt")
            return RedirectReply(status: 500)
        }.resolve(direct)
        XCTAssertEqual(outcome, .play(direct))
    }

    func testRedirectBecomesTheFileAddress() async {
        let file = URL(string: "https://node.webtor.io/abc/film.mkv?token=1")!
        let outcome = await resolver(RedirectReply(status: 302, location: file)).resolve(link)
        XCTAssertEqual(outcome, .play(file))
    }

    func testPaywallClipIsNotPlayed() async {
        let clip = URL(string: "https://webtor.io/pub/stremio/paywall-de.mp4?v=12345678")!
        guard case .blocked(let message) = await resolver(RedirectReply(status: 302, location: clip)).resolve(link) else {
            return XCTFail("Das Hinweisvideo darf nicht als Film laufen")
        }
        XCTAssertTrue(message.contains("bezahlten Webtor-Tarif"))
    }

    func testRefusalsBecomeMessagesWithoutTheAddress() async {
        for status in [401, 403, 404, 500, 503] {
            guard case .blocked(let message) = await resolver(RedirectReply(status: status)).resolve(link) else {
                XCTFail("Status \(status) sollte einen Hinweis geben")
                continue
            }
            XCTAssertFalse(message.contains("abc"), "Der Schlüssel gehört nicht in die Meldung")
            XCTAssertFalse(message.contains("http"))
        }
    }

    func testWhenInDoubtThePlayerTries() async {
        var outcome = await resolver(nil).resolve(link)
        XCTAssertEqual(outcome, .play(link))
        outcome = await resolver(RedirectReply(status: 200)).resolve(link)
        XCTAssertEqual(outcome, .play(link))
        outcome = await resolver(RedirectReply(status: 302)).resolve(link)
        XCTAssertEqual(outcome, .play(link))
    }

    func testAddressesAsPeoplePasteThem() {
        let expected = "https://webtor.io/token/abc/stremio/manifest.json"
        XCTAssertEqual(AddonAddress.normalize("  \(expected)\n")?.absoluteString, expected)
        XCTAssertEqual(AddonAddress.normalize("stremio://webtor.io/token/abc/stremio/manifest.json")?.absoluteString, expected)
        XCTAssertEqual(AddonAddress.normalize("webtor.io/token/abc/stremio")?.absoluteString, expected)
        XCTAssertEqual(AddonAddress.normalize("https://webtor.io/token/abc/stremio/configure")?.absoluteString, expected)
        XCTAssertEqual(AddonAddress.normalize("https://addon.example/a%7Cb=1/manifest.json")?.absoluteString, "https://addon.example/a%7Cb=1/manifest.json")
        XCTAssertNil(AddonAddress.normalize(""))
        XCTAssertNil(AddonAddress.normalize("http://addon.example/manifest.json"))
        XCTAssertNil(AddonAddress.normalize("kein addon"))
        XCTAssertNil(AddonAddress.normalize("localhost"))
    }

    // MARK: Addon ins Konto schreiben

    private let manifestJSON = #"{"id":"org.stremio.webtor.io","version":"0.1.0","name":"Webtor.io","description":"x","types":["movie","series"],"catalogs":[{"type":"movie","id":"Webtor.io"}],"resources":["stream","catalog","meta"],"logo":"https://webtor.io/logo.png","stremioAddonsConfig":{"issuer":"i","signature":"s"}}"#
    private let collectionJSON = #"{"result":{"addons":[{"transportUrl":"https://v3-cinemeta.strem.io/manifest.json","transportName":"","manifest":{"id":"com.linvo.cinemeta","name":"Cinemeta","version":"3.0.13","unbekannt":{"a":[1,2]}},"flags":{"official":true,"protected":true}},{"transportUrl":"https://debrid.example/geheim/manifest.json","transportName":"","manifest":{"id":"debrid","name":"Debrid","version":"1.0.0"},"flags":{"official":false,"protected":false}}],"lastModified":"2026-01-01T00:00:00.000Z"}}"#

    private func writtenAddons(_ http: MockTransport) throws -> [[String: Any]]? {
        guard let request = http.requests.first(where: { $0.url?.path.hasSuffix("addonCollectionSet") == true }) else { return nil }
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["type"] as? String, "AddonCollectionSet")
        XCTAssertEqual(body["authKey"] as? String, "key")
        return body["addons"] as? [[String: Any]]
    }

    func testInstallAppendsAndKeepsEverythingElseAsItWas() async throws {
        let http = MockTransport()
        let address = URL(string: "https://webtor.io/token/abc/stremio/manifest.json")!
        http.on("webtor.io/token/abc", json: manifestJSON)
        http.on("/api/addonCollectionGet", json: collectionJSON)
        http.on("/api/addonCollectionSet", json: #"{"result":{"success":true}}"#)

        let manifest = try await StremioAPI(http: http).installAddon(at: address, authKey: "key")
        XCTAssertEqual(manifest.name, "Webtor.io")

        let addons = try XCTUnwrap(writtenAddons(http))
        XCTAssertEqual(addons.map { $0["transportUrl"] as? String }, [
            "https://v3-cinemeta.strem.io/manifest.json", "https://debrid.example/geheim/manifest.json", address.absoluteString,
        ])
        // Felder, die Frames nicht kennt, überleben den Weg hin und zurück.
        let cinemeta = try XCTUnwrap(addons[0]["manifest"] as? [String: Any])
        XCTAssertNotNil(cinemeta["unbekannt"])
        XCTAssertEqual((addons[0]["flags"] as? [String: Any])?["protected"] as? Bool, true)
        let added = try XCTUnwrap(addons[2]["manifest"] as? [String: Any])
        XCTAssertEqual(added["id"] as? String, "org.stremio.webtor.io")
        XCTAssertNotNil(added["stremioAddonsConfig"])
        XCTAssertEqual((addons[2]["flags"] as? [String: Any])?["official"] as? Bool, false)
    }

    func testNewAddressReplacesTheOldOneInPlace() async throws {
        let http = MockTransport()
        http.on("webtor.io/token/neu", json: manifestJSON)
        http.on("/api/addonCollectionGet", json: #"{"result":{"addons":[{"transportUrl":"https://webtor.io/token/alt/stremio/manifest.json","manifest":{"id":"org.stremio.webtor.io","name":"Webtor.io"},"flags":{}},{"transportUrl":"https://debrid.example/manifest.json","manifest":{"id":"debrid","name":"Debrid"},"flags":{}}]}}"#)
        http.on("/api/addonCollectionSet", json: #"{"result":{"success":true}}"#)

        try await StremioAPI(http: http).installAddon(at: URL(string: "https://webtor.io/token/neu/stremio/manifest.json")!, authKey: "key")
        let addons = try XCTUnwrap(writtenAddons(http))
        XCTAssertEqual(addons.map { $0["transportUrl"] as? String }, [
            "https://webtor.io/token/neu/stremio/manifest.json", "https://debrid.example/manifest.json",
        ])
    }

    func testNothingIsWrittenWhenThereIsNothingToDoOrSomethingIsOff() async throws {
        // Schon installiert.
        var http = MockTransport()
        http.on("debrid.example", json: #"{"id":"debrid","name":"Debrid","version":"1.0.0","types":["movie"],"resources":["stream"]}"#)
        http.on("/api/addonCollectionGet", json: collectionJSON)
        try await StremioAPI(http: http).installAddon(at: URL(string: "https://debrid.example/geheim/manifest.json")!, authKey: "key")
        XCTAssertNil(try writtenAddons(http))

        // Noch nicht eingerichtet: die Adresse ohne Schlüssel.
        http = MockTransport()
        http.on("webtor.io/stremio", json: #"{"id":"org.stremio.webtor.io","name":"Webtor.io","types":["movie"],"resources":["stream"],"behaviorHints":{"configurationRequired":true}}"#)
        http.on("/api/addonCollectionGet", json: collectionJSON)
        do {
            try await StremioAPI(http: http).installAddon(at: URL(string: "https://webtor.io/stremio/manifest.json")!, authKey: "key")
            XCTFail("Ohne Einrichtung darf nichts installiert werden")
        } catch {}
        XCTAssertNil(try writtenAddons(http))

        // Die Liste des Kontos kommt nicht lesbar an: lieber abbrechen als die Addons überschreiben.
        for reply in [#"{"result":{"addons":[]}}"#, #"{"result":{}}"#, #"{"error":{"code":1,"message":"Session does not exist"}}"#] {
            http = MockTransport()
            http.on("webtor.io/token/abc", json: manifestJSON)
            http.on("/api/addonCollectionGet", json: reply)
            http.on("/api/addonCollectionSet", json: #"{"result":{"success":true}}"#)
            do {
                try await StremioAPI(http: http).installAddon(at: URL(string: "https://webtor.io/token/abc/stremio/manifest.json")!, authKey: "key")
                XCTFail("Hätte abbrechen müssen")
            } catch {}
            XCTAssertNil(try writtenAddons(http))
        }

        // Keine Addon-Adresse.
        http = MockTransport()
        http.on("example.org", json: "<html>")
        do {
            try await StremioAPI(http: http).installAddon(at: URL(string: "https://example.org/manifest.json")!, authKey: "key")
            XCTFail("Kein Manifest")
        } catch {}
        XCTAssertTrue(http.requests.allSatisfy { $0.url?.host == "example.org" })
    }
}
