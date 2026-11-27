import Foundation
import XCTest
@testable import FramesCore

final class XRayTests: XCTestCase {
    func testRequestReadsSeasonAndEpisode() {
        let request = XRayRequest(metaId: "tt0903747", type: "series", name: "Breaking Bad", videoId: "tt0903747:2:3")
        XCTAssertEqual(request.season, 2)
        XCTAssertEqual(request.episode, 3)
        XCTAssertEqual(request.imdbId, "tt0903747")
        XCTAssertTrue(request.isSeries)

        let movie = XRayRequest(metaId: "tt15398776", type: "movie", name: "Oppenheimer", videoId: "tt15398776")
        XCTAssertNil(movie.season)
        XCTAssertFalse(movie.isSeries)
        XCTAssertNil(XRayRequest(metaId: "kitsu:1", type: "series", name: "X").imdbId)
    }

    // MARK: Besetzung

    func testSeriesCastWithGuestsFromTVmaze() async {
        let mock = MockTransport()
        mock.on("lookup/shows", json: #"{"id": 169, "name": "Breaking Bad"}"#)
        mock.on("shows/169/cast", json: """
        [{"person": {"name": "Bryan Cranston", "image": {"medium": "https://img.example/bc.jpg"}}, "character": {"name": "Walter White"}},
         {"person": {"name": "Aaron Paul", "image": null}, "character": {"name": "Jesse Pinkman"}},
         {"broken": true}]
        """)
        mock.on("episodebynumber", json: #"{"id": 12201}"#)
        mock.on("episodes/12201/guestcast", json: """
        [{"person": {"name": "Raymond Cruz", "image": {"medium": "https://img.example/rc.jpg"}}, "character": {"name": "Tuco Salamanca"}},
         {"person": {"name": "Bryan Cranston"}, "character": {"name": "Heisenberg"}}]
        """)
        let service = CastService(transport: mock)
        let request = XRayRequest(metaId: "tt0903747", type: "series", name: "Breaking Bad", videoId: "tt0903747:2:3")
        let people = await service.cast(for: request)

        XCTAssertEqual(people.map(\.name), ["Bryan Cranston", "Aaron Paul", "Raymond Cruz"])
        XCTAssertEqual(people[0].character, "Walter White / Heisenberg")
        XCTAssertEqual(people[0].photo?.absoluteString, "https://img.example/bc.jpg")
        XCTAssertNil(people[1].photo)
        XCTAssertTrue(people[2].isGuest)
        XCTAssertTrue(mock.requests.contains { $0.url?.absoluteString.contains("imdb=tt0903747") == true })
        XCTAssertTrue(mock.requests.contains { $0.url?.absoluteString.contains("season=2") == true })
    }

    func testMovieCastGetsPhotosByName() async {
        let mock = MockTransport()
        mock.on("q=Cillian", json: """
        [{"person": {"name": "Gillian Murphy", "image": {"medium": "https://img.example/wrong.jpg"}}},
         {"person": {"name": "Cillian Murphy", "image": {"medium": "https://img.example/cm.jpg"}}}]
        """)
        mock.on("search/people", json: "[]")
        let service = CastService(transport: mock)
        let request = XRayRequest(
            metaId: "tt15398776", type: "movie", name: "Oppenheimer", castNames: ["Cillian Murphy", "Emily Blunt", "Cillian Murphy"]
        )
        let people = await service.cast(for: request)
        XCTAssertEqual(people.map(\.name), ["Cillian Murphy", "Emily Blunt"])
        XCTAssertEqual(people[0].photo?.absoluteString, "https://img.example/cm.jpg")
        XCTAssertNil(people[1].photo)
        XCTAssertFalse(mock.requests.contains { $0.url?.absoluteString.contains("lookup") == true })
    }

    func testUnknownSeriesFallsBackToAddonNames() async {
        let mock = MockTransport()
        mock.on("lookup/shows", status: 404, json: "{}")
        mock.on("search/people", json: "[]")
        let service = CastService(transport: mock)
        let request = XRayRequest(metaId: "tt0000001", type: "series", name: "X", videoId: "tt0000001:1:1", castNames: ["A", "B"])
        let people = await service.cast(for: request)
        XCTAssertEqual(people.map(\.name), ["A", "B"])
    }

    // MARK: Soundtrack

    func testPicksMatchingSoundtracksSongsFirst() {
        let groups = [
            MBGroup(id: "1", title: "Breaking Bad: Original Score From the Television Series", year: 2012),
            MBGroup(id: "2", title: "Faking Bad (The Unauthorised 'Breaking Bad' Parody Methsical)", year: 2019),
            MBGroup(id: "3", title: "Breaking Bad: Music From the Original Series", year: 2010),
            MBGroup(id: "4", title: "El Camino: A Breaking Bad Movie (Original Motion Picture Soundtrack)", year: 2020),
            MBGroup(id: "5", title: "Breaking Bad Parody Songs", year: 2014),
        ]
        let series = XRayRequest(metaId: "tt0903747", type: "series", name: "Breaking Bad")
        XCTAssertEqual(SoundtrackService.pick(groups, for: series).map(\.id), ["3", "1"])

        let remakes = [
            MBGroup(id: "old", title: "Dune: Original Motion Picture Soundtrack", year: 1984),
            MBGroup(id: "new", title: "Dune (Original Motion Picture Soundtrack)", year: 2021),
        ]
        let movie = XRayRequest(metaId: "tt1160419", type: "movie", name: "Dune", year: 2021)
        XCTAssertEqual(SoundtrackService.pick(remakes, for: movie).map(\.id), ["new"])
    }

    func testLoadsTracksOfSoundtrack() async {
        let mock = MockTransport()
        mock.on("release-group?", json: """
        {"release-groups": [{"id": "rg1", "title": "Oppenheimer: Original Motion Picture Soundtrack", "first-release-date": "2023-07-21"}]}
        """)
        mock.on("release?", json: """
        {"releases": [{"media": [{"tracks": [
          {"id": "t1", "title": "Fission", "length": 278600, "artist-credit": [{"name": "Ludwig Göransson", "joinphrase": ""}]},
          {"id": "t2", "title": "Duet", "artist-credit": [{"name": "A", "joinphrase": " & "}, {"name": "B"}]}
        ]}]}]}
        """)
        let service = SoundtrackService(transport: mock, pause: .zero)
        let result = await service.soundtracks(for: XRayRequest(metaId: "tt15398776", type: "movie", name: "Oppenheimer", year: 2023))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].tracks.map(\.title), ["Fission", "Duet"])
        XCTAssertEqual(result[0].tracks[0].artist, "Ludwig Göransson")
        XCTAssertEqual(result[0].tracks[0].durationLabel, "4:38")
        XCTAssertEqual(result[0].tracks[1].artist, "A & B")
        XCTAssertEqual(mock.requests.first?.value(forHTTPHeaderField: "User-Agent"), SoundtrackService.userAgent)
        XCTAssertTrue(mock.requests.first?.url?.absoluteString.contains("secondarytype") == true)
    }

    // MARK: Spotify

    func testSpotifyAuthorizeURLUsesPKCE() throws {
        let client = SpotifyClient(clientId: " 0123456789abcdef0123456789abcdef ")
        let url = client.authorizeURL(codeChallenge: "challenge", state: "xyz")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["client_id"], "0123456789abcdef0123456789abcdef")
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertEqual(query["redirect_uri"], "http://127.0.0.1:43821/spotify")
        XCTAssertEqual(query["state"], "xyz")
        XCTAssertTrue(SpotifyClient.isValidClientId("0123456789abcdef0123456789abcdef"))
        XCTAssertFalse(SpotifyClient.isValidClientId("kein-schluessel"))
    }

    func testSpotifyCallbackChecksState() {
        XCTAssertEqual(SpotifyClient.callback(from: "/spotify?code=abc&state=s1", expectedState: "s1"), .success("abc"))
        if case .success = SpotifyClient.callback(from: "/spotify?code=abc&state=other", expectedState: "s1") {
            XCTFail("Fremder state darf nicht durchgehen.")
        }
        if case .success = SpotifyClient.callback(from: "/spotify?error=access_denied&state=s1", expectedState: "s1") {
            XCTFail("Abbruch darf nicht als Erfolg gelten.")
        }
    }

    func testSpotifyFindAndSave() async throws {
        let mock = MockTransport()
        mock.on("v1/search", json: """
        {"tracks": {"items": [
          {"uri": "spotify:track:other", "name": "Something Else", "artists": [{"name": "X"}]},
          {"uri": "spotify:track:abc", "name": "Fission", "artists": [{"name": "Ludwig Göransson"}],
           "external_urls": {"spotify": "https://open.spotify.com/track/abc"}}
        ]}}
        """)
        mock.on("me/library", json: "")
        let client = SpotifyClient(clientId: "0123456789abcdef0123456789abcdef", transport: mock)
        let token = SpotifyToken(accessToken: "tok", refreshToken: "ref", expiresAt: Date().addingTimeInterval(3600))
        let track = try await client.findTrack(title: "Fission (Remastered)", artist: "Ludwig Göransson", token: token)
        XCTAssertEqual(track?.uri, "spotify:track:abc")
        try await client.save(uris: ["spotify:track:abc"], token: token)

        let save = try XCTUnwrap(mock.requests.last)
        XCTAssertEqual(save.httpMethod, "PUT")
        XCTAssertEqual(save.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertTrue(save.url?.absoluteString.contains("uris=spotify:track:abc") == true)
        let search = try XCTUnwrap(mock.requests.first?.url?.absoluteString.removingPercentEncoding)
        XCTAssertTrue(search.contains("track:Fission artist:Ludwig Göransson"), search)
    }

    func testSpotifyExpiredSessionAndTokenExchange() async throws {
        let mock = MockTransport()
        mock.on("api/token", json: #"{"access_token": "new", "expires_in": 3600}"#)
        mock.on("me/library", status: 401, json: "{}")
        let client = SpotifyClient(clientId: "0123456789abcdef0123456789abcdef", transport: mock)
        let old = SpotifyToken(accessToken: "old", refreshToken: "keep", expiresAt: .distantPast)
        XCTAssertTrue(old.isExpired)
        let refreshed = try await client.refresh(old)
        XCTAssertEqual(refreshed.accessToken, "new")
        XCTAssertEqual(refreshed.refreshToken, "keep")
        let body = String(decoding: try XCTUnwrap(mock.requests.first?.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("grant_type=refresh_token"))
        do {
            try await client.save(uris: ["spotify:track:abc"], token: refreshed)
            XCTFail("401 muss als abgemeldet gelten.")
        } catch {
            XCTAssertEqual(error as? FramesError, .notLoggedIn)
        }
    }

    func testSpotifySearchLinkWithoutLogin() {
        let link = SpotifyClient.searchLink(title: "Baby Blue", artist: "Badfinger")
        XCTAssertEqual(link.absoluteString, "https://open.spotify.com/search/Baby%20Blue%20Badfinger")
    }
}
