import XCTest
@testable import FramesCore

final class TopShelfTests: XCTestCase {
    private func item(_ id: String, progress: Double, watched: TimeInterval, video: String? = nil) -> LibraryItem {
        LibraryItem(
            id: id, name: id, type: "movie", lastWatched: Date(timeIntervalSince1970: watched),
            timeOffset: progress * 1000, duration: 1000, videoId: video
        )
    }

    func testOnlyUnfinishedItemsNewestFirst() {
        let library = [
            item("alt", progress: 0.4, watched: 100),
            item("fertig", progress: 0.99, watched: 300),
            item("neu", progress: 0.2, watched: 200),
            item("unberuehrt", progress: 0, watched: 400),
        ]
        XCTAssertEqual(TopShelfSnapshot.entries(from: library).map(\.id), ["neu", "alt"])
    }

    func testLimitsEntries() {
        let library = (0..<20).map { item("t\($0)", progress: 0.5, watched: Double($0)) }
        XCTAssertEqual(TopShelfSnapshot.entries(from: library).count, TopShelfSnapshot.maxEntries)
    }

    func testEpisodeLabel() {
        XCTAssertEqual(TopShelfSnapshot.episodeLabel(videoId: "tt123:2:4", metaId: "tt123"), "S02 E04")
        XCTAssertNil(TopShelfSnapshot.episodeLabel(videoId: "tt123", metaId: "tt123"))
        XCTAssertNil(TopShelfSnapshot.episodeLabel(videoId: nil, metaId: "tt123"))
    }

    func testBackgroundComesFromLookup() {
        let url = URL(string: "https://example.com/b.jpg")!
        let entries = TopShelfSnapshot.entries(from: [item("a", progress: 0.5, watched: 1)], backgrounds: ["a": url])
        XCTAssertEqual(entries.first?.background, url)
    }

    func testRoundTripAndLink() throws {
        let entry = TopShelfSnapshot.Entry(type: "series", id: "tt123", name: "Serie", subtitle: "S01 E02", progress: 0.5)
        let snapshot = TopShelfSnapshot(entries: [entry], updated: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(try TopShelfSnapshot.decode(snapshot.encoded()), snapshot)
        XCTAssertEqual(entry.link?.absoluteString, "frames://detail?type=series&id=tt123")
    }
}
