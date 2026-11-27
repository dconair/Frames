import XCTest
@testable import FramesCore

final class SegmentTests: XCTestCase {
    // Antworten der echten Dienste, gekürzt.
    private let introDB = #"""
    {"imdb_id":"tt0903747","media_type":"tv","is_movie":false,"season":1,"episode":2,
     "intro":{"start_sec":314.5,"end_sec":331,"start_ms":314500,"end_ms":331000,"confidence":1,"submission_count":5},
     "recap":null,
     "outro":{"start_sec":2843,"end_sec":2901,"start_ms":2843000,"end_ms":2901000},
     "post_credits":null,"no_intro":false,"no_recap":false,"no_outro":false}
    """#
    private let theIntroDB = #"""
    {"tmdb_id":66732,"type":"tv","season":4,"episode":1,
     "intro":[{"start_ms":530066,"end_ms":580416}],
     "recap":[{"start_ms":0,"end_ms":0}],
     "credits":[{"start_ms":530572,"end_ms":579474},{"start_ms":4392676,"end_ms":null}]}
    """#
    private let aniSkip = #"""
    {"found":true,"results":[
     {"interval":{"startTime":28.783,"endTime":118.783},"skipType":"op","skipId":"a","episodeLength":1500.04},
     {"interval":{"startTime":1387.996,"endTime":1500},"skipType":"ed","skipId":"b","episodeLength":1500.146},
     {"interval":{"startTime":132.773,"endTime":201.296},"skipType":"recap","skipId":"c","episodeLength":1444}],
     "message":"Successfully found skip times","statusCode":200}
    """#

    func testEpisodeRefs() {
        XCTAssertEqual(EpisodeRef(videoId: "tt0903747:1:2"), .imdb(id: "tt0903747", season: 1, episode: 2))
        XCTAssertEqual(EpisodeRef(videoId: "kitsu:1376:5"), .kitsu(id: 1376, episode: 5))
        XCTAssertNil(EpisodeRef(videoId: "tt0133093"))
        XCTAssertNil(EpisodeRef(videoId: "yt_id:UC123:abc"))
    }

    func testIntroDBAnswer() throws {
        let segments = try JSONDecoder().decode(SegmentService.IntroDBAnswer.self, from: Data(introDB.utf8)).segments
        XCTAssertEqual(segments.segments.map(\.kind), [.intro, .credits])
        XCTAssertEqual(segments.skippable(at: 320, duration: 2900)?.end, 331)
        XCTAssertNil(segments.skippable(at: 330, duration: 2900), "Eine Sekunde vor dem Ende lohnt kein Sprung.")
        XCTAssertNil(segments.skippable(at: 200, duration: 2900))
        XCTAssertEqual(segments.creditsStart(duration: 2905), 2843)
    }

    func testTheIntroDBAnswerDropsEmptyAndEarlyCredits() throws {
        let segments = try JSONDecoder().decode(SegmentService.TheIntroDBAnswer.self, from: Data(theIntroDB.utf8)).segments
        XCTAssertFalse(segments.segments.contains { $0.kind == .recap }, "Ein Rückblick von 0 bis 0 ist keiner.")
        XCTAssertEqual(segments.skippable(at: 540, duration: 4550)?.kind, .intro)
        // Der frühe „credits“-Abschnitt ist der Vorspann und darf den Countdown nicht auslösen.
        XCTAssertEqual(segments.creditsStart(duration: 4550), 4392.676)
        XCTAssertEqual(segments.segments.last?.end(duration: 4550), 4550)
    }

    func testAniSkipAnswer() throws {
        let segments = try JSONDecoder().decode(SegmentService.AniSkipAnswer.self, from: Data(aniSkip.utf8)).segments
        XCTAssertEqual(segments.segments.map(\.kind), [.intro, .recap, .credits])
        XCTAssertEqual(segments.skippable(at: 150, duration: 1500)?.kind, .recap)
        XCTAssertEqual(segments.creditsStart(duration: 1500), 1387.996)
    }

    func testMergePrefersFirstSourcePerKind() {
        let first = MediaSegments([MediaSegment(kind: .intro, start: 10, end: 40, source: .introDB)])
        let second = MediaSegments([
            MediaSegment(kind: .intro, start: 12, end: 41, source: .theIntroDB),
            MediaSegment(kind: .recap, start: 0, end: 9, source: .theIntroDB),
        ])
        let merged = MediaSegments.merged([first, second])
        XCTAssertEqual(merged.segments.map(\.kind), [.recap, .intro])
        XCTAssertEqual(merged.segments.first { $0.kind == .intro }?.source, .introDB)
        XCTAssertEqual(merged.sources, [.theIntroDB, .introDB])
    }

    func testServiceAsksBothDatabases() async {
        let transport = MockTransport()
        transport.on("api.introdb.app", json: introDB)
        transport.on("api.theintrodb.org", json: #"{"recap":[{"start_ms":0,"end_ms":45000}]}"#)
        let segments = await SegmentService(http: transport).segments(for: "tt0903747:1:2")
        XCTAssertEqual(segments.segments.map(\.kind), [.recap, .intro, .credits])
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertTrue(transport.requests.contains { $0.url?.absoluteString.contains("imdb_id=tt0903747&season=1&episode=2") == true })
    }

    func testServiceMapsKitsuToAniSkip() async {
        let transport = MockTransport()
        transport.on("arm.haglund.dev", json: #"{"kitsu":1376,"myanimelist":1535,"imdb":"tt0877057"}"#)
        transport.on("api.aniskip.com/v2/skip-times/1535/3", json: aniSkip)
        let segments = await SegmentService(http: transport).segments(for: "kitsu:1376:3")
        XCTAssertEqual(segments.sources, [.aniSkip])
    }

    func testServiceSurvivesFailures() async {
        let transport = MockTransport()
        transport.on("api.introdb.app", status: 500, json: "{}")
        let segments = await SegmentService(http: transport).segments(for: "tt0903747:1:2")
        XCTAssertTrue(segments.isEmpty)
    }

    func testChapterNames() {
        XCTAssertEqual(MediaSegments.kind(ofChapter: "Intro"), .intro)
        XCTAssertEqual(MediaSegments.kind(ofChapter: "Opening Credits"), .intro)
        XCTAssertEqual(MediaSegments.kind(ofChapter: "OP"), .intro)
        XCTAssertEqual(MediaSegments.kind(ofChapter: "Vorspann"), .intro)
        XCTAssertEqual(MediaSegments.kind(ofChapter: "Previously on"), .recap)
        XCTAssertEqual(MediaSegments.kind(ofChapter: "Rückblick"), .recap)
        XCTAssertEqual(MediaSegments.kind(ofChapter: "End Credits"), .credits)
        XCTAssertEqual(MediaSegments.kind(ofChapter: "ED"), .credits)
        XCTAssertEqual(MediaSegments.kind(ofChapter: "Abspann"), .credits)
        XCTAssertEqual(MediaSegments.kind(ofChapter: "Next Episode Preview"), .preview)
        XCTAssertNil(MediaSegments.kind(ofChapter: "Chapter 01"))
        XCTAssertNil(MediaSegments.kind(ofChapter: "Operation"))
        XCTAssertNil(MediaSegments.kind(ofChapter: "Edward"))

        let segments = MediaSegments.fromChapters([
            .init(name: "Chapter 1", start: 0, duration: 60),
            .init(name: "Opening", start: 60, duration: 90),
            .init(name: "Chapter 3", start: 150, duration: 1200),
            .init(name: "Ending", start: 1350, duration: 90),
        ])
        XCTAssertEqual(segments.skippable(at: 70, duration: 1440)?.end, 150)
        XCTAssertEqual(segments.creditsStart(duration: 1440), 1350)
    }

    // MARK: Nächste Folge

    private func series() -> Meta {
        let past = Date(timeIntervalSince1970: 0)
        let future = Date().addingTimeInterval(86_400 * 30)
        return Meta(id: "tt1", type: "series", name: "Serie", videos: [
            Video(id: "tt1:1:2", title: "Zwei", season: 1, episode: 2, released: past),
            Video(id: "tt1:1:1", title: "Eins", season: 1, episode: 1, released: past),
            Video(id: "tt1:2:1", title: "Staffel zwei", season: 2, episode: 1, released: past),
            Video(id: "tt1:2:2", title: "Kommt noch", season: 2, episode: 2, released: future),
            Video(id: "tt1:0:1", title: "Special", season: 0, episode: 1, released: past),
        ])
    }

    func testNextEpisode() {
        let meta = series()
        XCTAssertEqual(meta.episode(after: "tt1:1:1")?.id, "tt1:1:2")
        XCTAssertEqual(meta.episode(after: "tt1:1:2")?.id, "tt1:2:1", "Über die Staffelgrenze, an den Specials vorbei.")
        XCTAssertNil(meta.episode(after: "tt1:2:1"), "Die nächste Folge ist noch nicht erschienen.")
        XCTAssertNil(meta.episode(after: "tt1:0:1"))
        XCTAssertNil(meta.episode(after: "tt9:1:1"))
    }

    private func stream(_ addon: String, _ title: String, group: String? = nil, index: Int) -> SourcedStream {
        SourcedStream(
            stream: Stream(url: URL(string: "https://debrid.example/\(index).mkv"), name: "[RD+] \(addon)", title: title, bingeGroup: group),
            addonName: addon, index: index
        )
    }

    func testContinuationKeepsBingeGroup() {
        let streams = [
            stream("A", "Serie.S01E02.2160p.WEB-DL.DV.Atmos.mkv", group: "a|4k", index: 0),
            stream("B", "Serie.S01E02.1080p.WEB-DL.mkv", group: "b|1080p", index: 1),
            stream("A", "Serie.S01E02.1080p.WEB-DL.mkv", group: "a|1080p", index: 2),
        ]
        let origin = StreamOrigin(addonName: "A", bingeGroup: "a|1080p", resolution: .fullHD, service: .realDebrid)
        XCTAssertEqual(StreamRanker.continuation(streams, after: origin)?.index, 2)

        // Ohne passende Gruppe: dasselbe Addon in derselben Auflösung.
        let noGroup = StreamOrigin(addonName: "A", bingeGroup: "weg", resolution: .fullHD, service: .realDebrid)
        XCTAssertEqual(StreamRanker.continuation(streams, after: noGroup)?.index, 2)

        // Ganz ohne Vorlauf: die beste Quelle.
        XCTAssertEqual(StreamRanker.continuation(streams, after: nil)?.index, 0)
        XCTAssertNil(StreamRanker.continuation([], after: origin))
    }
}
