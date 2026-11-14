import XCTest
@testable import FramesCore

final class StreamInfoTests: XCTestCase {
    func testTypicalDebridRelease() {
        let info = StreamInfo(text: "[RD+] Quelle\n4k DV | HDR10+\nFilm.2026.2160p.UHD.BluRay.REMUX.DV.HDR10Plus.HEVC.TrueHD.7.1.Atmos-GRP.mkv\n💾 58.2 GB")
        XCTAssertEqual(info.resolution, .uhd)
        XCTAssertEqual(info.dynamicRange, .dolbyVision)
        XCTAssertEqual(info.audio, .atmos)
        XCTAssertEqual(info.channels, "7.1")
        XCTAssertEqual(info.codec, .hevc)
        XCTAssertEqual(info.isCached, true)
        XCTAssertEqual(info.sizeLabel, "58,2 GB")
        XCTAssertEqual(info.audioLabel, "ATMOS 7.1")
    }

    func testWebRelease() {
        let info = StreamInfo(text: "Serie.S01E02.1080p.WEB-DL.DDP5.1.H.264-GRP\n1.9 GB")
        XCTAssertEqual(info.resolution, .fullHD)
        XCTAssertNil(info.dynamicRange)
        XCTAssertEqual(info.audio, .dolbyDigitalPlus)
        XCTAssertEqual(info.channels, "5.1")
        XCTAssertEqual(info.codec, .h264)
        XCTAssertNil(info.isCached)
    }

    func testVariants() {
        XCTAssertEqual(StreamInfo(text: "Film 720p x265 AAC 2.0 850 MB").resolution, .hd)
        XCTAssertEqual(StreamInfo(text: "Film 720p x265 AAC 2.0 850 MB").audio, .aac)
        XCTAssertEqual(StreamInfo(text: "Film 720p x265 AAC 2.0 850 MB").channels, "2.0")
        XCTAssertEqual(StreamInfo(text: "Film 720p x265 AAC 2.0 850 MB").sizeLabel, "850 MB")
        XCTAssertEqual(StreamInfo(text: "Film.1080p.HDR.DTS-HD.MA.5.1").audio, .dtsHD)
        XCTAssertEqual(StreamInfo(text: "Film.1080p.HDR.DTS-HD.MA.5.1").dynamicRange, .hdr10)
        XCTAssertEqual(StreamInfo(text: "Film.1080p.BluRay.DTS.x264").audio, .dts)
        XCTAssertEqual(StreamInfo(text: "Film.1080p.DD5.1").audio, .dolbyDigital)
        XCTAssertEqual(StreamInfo(text: "Film.1080p.AC3").audio, .dolbyDigital)
        XCTAssertEqual(StreamInfo(text: "Film 2160p AV1 HDR10+").dynamicRange, .hdr10Plus)
        XCTAssertEqual(StreamInfo(text: "Film 2160p AV1 HDR10+").codec, .av1)
        XCTAssertEqual(StreamInfo(text: "[RD download] Film 1080p").isCached, false)
    }

    func testNoFalsePositives() {
        // „Add“, „Madden“ oder eine Größe wie 5.1 GB dürfen keine Technik-Angaben auslösen.
        let info = StreamInfo(text: "The Addams Family Hidden Edition 5.1 GB")
        XCTAssertNil(info.audio)
        XCTAssertNil(info.channels)
        XCTAssertNil(info.dynamicRange)
        XCTAssertNil(info.resolution)
        XCTAssertEqual(info.sizeLabel, "5,1 GB")
        XCTAssertNil(StreamInfo(text: "Advent 1080p").dynamicRange, "„dv“ nur als eigenes Wort")
    }

    func testKinds() {
        XCTAssertEqual(Stream(url: URL(string: "https://x.example/a.mkv")).playableURL?.host, "x.example")
        XCTAssertNil(Stream(infoHash: "abc").playableURL)
        XCTAssertEqual(Stream(url: URL(string: "magnet:?xt=urn:btih:abc")).kind, .torrent)
        XCTAssertEqual(Stream(ytId: "abc").kind, .youtube("abc"))
        XCTAssertEqual(Stream().kind, .unknown)
    }

    private func sourced(_ text: String, _ index: Int) -> SourcedStream {
        SourcedStream(stream: Stream(url: URL(string: "https://x.example/\(index)"), name: text), addonName: "A", index: index)
    }

    func testRankingPrefersCachedThenQuality() {
        let streams = [
            sourced("1080p WEB DDP5.1", 0),
            sourced("[RD download] 2160p DV Atmos", 1),
            sourced("2160p HDR", 2),
            sourced("2160p DV TrueHD 7.1", 3),
            sourced("720p", 4),
        ]
        XCTAssertEqual(StreamRanker.ranked(streams).map(\.index), [3, 2, 0, 4, 1])
    }

    func testRankingRespectsResolutionCapAndDolbyVisionSwitch() {
        let streams = [sourced("2160p DV", 0), sourced("1080p HDR", 1), sourced("1080p", 2), sourced("2160p HDR", 3)]

        var capped = PlaybackSettings()
        capped.maxResolution = .fullHD
        // Über der Obergrenze zählt weiter die Bildqualität: Dolby Vision vor HDR.
        XCTAssertEqual(StreamRanker.ranked(streams, preferences: capped).map(\.index), [1, 2, 0, 3])

        var noDolbyVision = PlaybackSettings()
        noDolbyVision.preferDolbyVision = false
        XCTAssertEqual(StreamRanker.ranked(streams, preferences: noDolbyVision).first?.index, 3)
    }

    func testRankingKeepsAddonOrderOnTies() {
        let streams = [sourced("1080p", 0), sourced("1080p", 1), sourced("1080p", 2)]
        XCTAssertEqual(StreamRanker.ranked(streams).map(\.index), [0, 1, 2])
    }
}
