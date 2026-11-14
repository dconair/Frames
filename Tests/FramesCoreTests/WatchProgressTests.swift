import XCTest
@testable import FramesCore

final class WatchProgressTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_672_000)

    private func progress(_ position: Double, of duration: Double = 3600, video: String = "tt1:1:2") -> WatchProgress {
        WatchProgress(metaId: "tt1", type: "series", name: "Serie", poster: "https://img.example/p", videoId: video, position: position, duration: duration)
    }

    func testExistingItemKeepsUnknownFields() {
        let existing: [String: Any] = [
            "_id": "tt1", "name": "Serie", "type": "series", "removed": false, "temp": false,
            "_ctime": "2026-01-01T00:00:00.000Z", "eigenesFeld": ["bleibt": true],
            "state": ["timeOffset": 1000, "duration": 2000, "video_id": "tt1:1:1", "timesWatched": 3, "watched": "abc", "noNotif": true],
        ]
        let item = LibraryProgress.apply(progress(600), to: existing, now: now)
        let state = item["state"] as? [String: Any]

        XCTAssertEqual(item["removed"] as? Bool, false, "Ein Bibliothekseintrag bleibt in der Bibliothek")
        XCTAssertEqual(item["_ctime"] as? String, "2026-01-01T00:00:00.000Z")
        XCTAssertNotNil(item["eigenesFeld"])
        XCTAssertEqual(state?["watched"] as? String, "abc")
        XCTAssertEqual(state?["noNotif"] as? Bool, true)
        XCTAssertEqual(state?["timeOffset"] as? Int, 600_000)
        XCTAssertEqual(state?["duration"] as? Int, 3_600_000)
        XCTAssertEqual(state?["video_id"] as? String, "tt1:1:2")
        XCTAssertEqual(state?["timesWatched"] as? Int, 3)
        XCTAssertEqual(item["_mtime"] as? String, LibraryProgress.dateString(now))
        XCTAssertEqual(state?["lastWatched"] as? String, LibraryProgress.dateString(now))
    }

    func testUnknownTitleGetsTemporaryItem() throws {
        let item = LibraryProgress.apply(progress(600), to: nil, now: now)
        XCTAssertEqual(item["_id"] as? String, "tt1")
        XCTAssertEqual(item["removed"] as? Bool, true)
        XCTAssertEqual(item["temp"] as? Bool, true)
        XCTAssertEqual(item["poster"] as? String, "https://img.example/p")

        // Der Eintrag muss sich so lesen lassen, wie Frames die Bibliothek liest.
        let decoded = try JSONDecoder().decode(LibraryItem.self, from: JSONSerialization.data(withJSONObject: item))
        XCTAssertFalse(decoded.isInLibrary)
        XCTAssertTrue(decoded.isContinueWatching)
        XCTAssertEqual(decoded.videoId, "tt1:1:2")
        XCTAssertEqual(decoded.progress ?? 0, 600.0 / 3600.0, accuracy: 0.001)
        XCTAssertEqual(decoded.modified, StremioDate.parse(LibraryProgress.dateString(now)))
    }

    func testFinishingResetsOffsetAndCountsOnce() {
        var item = LibraryProgress.apply(progress(3500), to: nil, now: now)
        var state = item["state"] as? [String: Any]
        XCTAssertEqual(state?["timeOffset"] as? Int, 0)
        XCTAssertEqual(state?["timesWatched"] as? Int, 1)
        XCTAssertEqual(state?["flaggedWatched"] as? Int, 1)

        // Ein zweites Speichern am Ende derselben Folge zählt nicht noch einmal.
        item = LibraryProgress.apply(progress(3590), to: item, now: now)
        state = item["state"] as? [String: Any]
        XCTAssertEqual(state?["timesWatched"] as? Int, 1)

        // Die nächste Folge zu Ende zu sehen zählt wieder.
        item = LibraryProgress.apply(progress(3590, video: "tt1:1:3"), to: item, now: now)
        state = item["state"] as? [String: Any]
        XCTAssertEqual(state?["timesWatched"] as? Int, 2)
    }

    func testWorthSaving() {
        XCTAssertFalse(progress(5).isWorthSaving)
        XCTAssertTrue(progress(20).isWorthSaving)
        XCTAssertFalse(progress(20, of: 0).isWorthSaving)
        XCTAssertFalse(progress(.nan).isWorthSaving)
    }

    func testResumePosition() {
        let items = [
            LibraryItem(id: "tt1", name: "A", type: "series", timeOffset: 600_000, duration: 3_600_000, videoId: "tt1:1:2"),
            LibraryItem(id: "tt2", name: "B", type: "movie", timeOffset: 3_550_000, duration: 3_600_000, videoId: "tt2"),
            LibraryItem(id: "tt3", name: "C", type: "movie", timeOffset: 5_000, duration: 3_600_000, videoId: "tt3"),
        ]
        XCTAssertEqual(items.resumePosition(metaId: "tt1", videoId: "tt1:1:2"), 600)
        XCTAssertNil(items.resumePosition(metaId: "tt1", videoId: "tt1:1:3"), "Andere Folge beginnt von vorn")
        XCTAssertNil(items.resumePosition(metaId: "tt2", videoId: "tt2"), "Fast zu Ende beginnt von vorn")
        XCTAssertNil(items.resumePosition(metaId: "tt3", videoId: "tt3"))
        XCTAssertNil(items.resumePosition(metaId: "tt9", videoId: "tt9"))
    }

    func testSaveProgressReadsThenWrites() async throws {
        let http = MockTransport()
        http.on("datastoreGet", json: #"{"result":[{"_id":"tt1","name":"Serie","type":"series","removed":false,"temp":false,"fremd":7,"state":{"timeOffset":0,"duration":0,"timesWatched":0}}]}"#)
        http.on("datastorePut", json: #"{"result":{"success":true}}"#)
        let saved = try await StremioAPI(http: http).saveProgress(progress(600), authKey: "key", now: now)

        XCTAssertEqual(saved?.timeOffset, 600_000)
        XCTAssertEqual(saved?.isInLibrary, true)
        XCTAssertEqual(http.requests.map { $0.url?.lastPathComponent }, ["datastoreGet", "datastorePut"])

        let get = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(http.requests[0].httpBody)) as? [String: Any])
        XCTAssertEqual(get["ids"] as? [String], ["tt1"])
        let put = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(http.requests[1].httpBody)) as? [String: Any])
        XCTAssertEqual(put["collection"] as? String, "libraryItem")
        XCTAssertEqual(put["authKey"] as? String, "key")
        let change = try XCTUnwrap((put["changes"] as? [[String: Any]])?.first)
        XCTAssertEqual(change["fremd"] as? Int, 7)
        XCTAssertEqual((change["state"] as? [String: Any])?["video_id"] as? String, "tt1:1:2")
    }

    func testSaveProgressSurfacesServerError() async {
        let http = MockTransport()
        http.on("datastoreGet", json: #"{"error":{"code":1,"message":"Session does not exist"}}"#)
        do {
            try await StremioAPI(http: http).saveProgress(progress(600), authKey: "alt", now: now)
            XCTFail()
        } catch {
            XCTAssertEqual(error as? FramesError, .api(code: 1, message: "Session does not exist"))
        }
        XCTAssertEqual(http.requests.count, 1, "Ohne gelesenen Eintrag wird nichts geschrieben")
    }
}
