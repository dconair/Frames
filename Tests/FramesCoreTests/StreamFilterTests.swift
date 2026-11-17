import XCTest
@testable import FramesCore

final class StreamFilterTests: XCTestCase {
    private func item(_ name: String, _ title: String, url: String = "https://cdn.example/file", index: Int, webtor: Bool = false) -> SourcedStream {
        SourcedStream(
            stream: Stream(url: URL(string: url)!, name: name, title: title),
            addonName: webtor ? "Webtor.io" : "Addon", index: index, isWebtorAddon: webtor
        )
    }

    private var sample: [SourcedStream] {
        [
            item("[RD+] Addon 4k", "Film.2160p.UHD.BluRay.REMUX.DV.TrueHD.7.1.Atmos-GRP\n💾 58.2 GB", index: 0),
            item("[RD+] Addon 4k", "Film.2160p.WEB-DL.HDR10.DDP5.1.Atmos.German.DL-GRP\n💾 18 GB 🇩🇪", index: 1),
            item("[RD+] Addon 1080p", "Film.1080p.BluRay.DTS-HD.MA.5.1.x264-GRP\n💾 14 GB", index: 2),
            item("[⚡WT]\nAddon 1080p", "Film.1080p.WEB-DL.DD5.1.H.264-GRP\n💾 4.1 GB", url: "https://webtor.io/token/abc/stremio/resolve/jwt", index: 3, webtor: true),
            item("[P2P]\nAddon 720p", "Film.720p.HDTV.AAC.German-GRP\n💾 900 MB", url: "https://webtor.io/token/abc/stremio/resolve/jwt2", index: 4, webtor: true),
        ]
    }

    func testServiceIsReadFromTheCommonSpellings() {
        XCTAssertEqual(sample.map(\.info.service), [.realDebrid, .realDebrid, .realDebrid, .webtor, .webtor])
        XCTAssertEqual(StreamInfo(stream: Stream(name: "Addon RD ⚡", title: "Film.1080p.WEB-DL")).service, .realDebrid)
        XCTAssertEqual(StreamInfo(stream: Stream(name: "[TB⚡] Addon", title: "Film")).service, .torBox)
        XCTAssertEqual(StreamInfo(stream: Stream(name: "[AD download] Addon", title: "Film")).service, .allDebrid)
        XCTAssertEqual(StreamInfo(stream: Stream(name: "Addon\nReal-Debrid", title: "Film")).service, .realDebrid)
        XCTAssertEqual(StreamInfo(stream: Stream(name: "[⚡RD]\nWebtor.io", title: "Film")).service, .realDebrid)
        // „DL“ in WEB-DL ist kein Debrid-Link, und ein Dateiname macht noch keinen Dienst.
        XCTAssertNil(StreamInfo(stream: Stream(name: "Addon 1080p", title: "Film.1080p.WEB-DL.German.DL.PM.torbox.mkv")).service)
        XCTAssertNil(StreamInfo(stream: Stream(name: "BIRD 4k", title: "Film")).service)
    }

    func testWebtorStatesBecomeCachedOrNot() {
        XCTAssertEqual(sample[3].info.isCached, true)
        XCTAssertEqual(sample[4].info.isCached, false)
        XCTAssertNil(item("[WT]\nAddon", "Film 1080p", index: 0, webtor: true).info.isCached)
        XCTAssertEqual(item("⭐ [WT]\nWebtor.io", "Film", index: 0, webtor: true).info.service, .webtor)
        XCTAssertEqual(item("Webtor.io\n1080p", "Film", index: 0, webtor: true).info.service, .webtor)
    }

    func testReleaseAndLanguage() {
        XCTAssertEqual(sample.map(\.info.release), [.remux, .web, .bluRay, .web, .tv])
        XCTAssertEqual(sample[1].info.languages, ["de", "en", "multi"])
        XCTAssertEqual(sample[4].info.languages, ["de"])
        XCTAssertEqual(sample[0].info.languages, [])
        XCTAssertEqual(StreamInfo(text: "Film 1080p 🇬🇧 / 🇩🇪").languages, ["de", "en", "multi"])
        XCTAssertEqual(StreamInfo(text: "Film.MULTi.1080p").languages, ["multi"])
        XCTAssertNil(StreamInfo(text: "Film.1080p.DTS.mkv").release)
    }

    func testBitrate() {
        let info = sample[0].info
        XCTAssertEqual(info.bitrate(runtimeMinutes: 136) ?? 0, 61.27, accuracy: 0.05)
        XCTAssertEqual(info.bitrateLabel(runtimeMinutes: 136), "61 MBIT/S")
        XCTAssertEqual(sample[4].info.bitrateLabel(runtimeMinutes: 45), "2,8 MBIT/S")
        XCTAssertNil(info.bitrateLabel(runtimeMinutes: nil))
        XCTAssertNil(StreamInfo(text: "Film 1080p").bitrateLabel(runtimeMinutes: 100))
    }

    func testRuntimeSpellings() {
        XCTAssertEqual(Meta.minutes(from: "148 min"), 148)
        XCTAssertEqual(Meta.minutes(from: "2h 28min"), 148)
        XCTAssertEqual(Meta.minutes(from: "2 h"), 120)
        XCTAssertEqual(Meta.minutes(from: "2:28"), 148)
        XCTAssertEqual(Meta.minutes(from: "45"), 45)
        XCTAssertNil(Meta.minutes(from: "unbekannt"))
        XCTAssertNil(Meta.minutes(from: nil))
    }

    func testFilterGroupsCombine() {
        var filter = StreamFilter()
        XCTAssertEqual(filter.apply(to: sample).count, 5)

        filter.resolutions = [.uhd, .fullHD]
        XCTAssertEqual(filter.apply(to: sample).map(\.index), [0, 1, 2, 3])
        filter.pictures = [.sdr]
        XCTAssertEqual(filter.apply(to: sample).map(\.index), [2, 3])
        filter.services = [.webtor]
        XCTAssertEqual(filter.apply(to: sample).map(\.index), [3])
        XCTAssertEqual(filter.activeCount, 4)

        var sound = StreamFilter()
        sound.sounds = [.atmos, .lossless]
        XCTAssertEqual(sound.apply(to: sample).map(\.index), [0, 1, 2])

        var language = StreamFilter()
        language.languages = ["de"]
        XCTAssertEqual(language.apply(to: sample).map(\.index), [1, 4])

        var release = StreamFilter()
        release.releases = [.remux]
        XCTAssertEqual(release.apply(to: sample).map(\.index), [0])
    }

    func testFacetsListOnlyWhatExistsPlusTheSelection() {
        var facets = StreamFacets(sample)
        XCTAssertEqual(facets.resolutions, [.uhd, .fullHD, .hd])
        XCTAssertEqual(facets.pictures, [.dolbyVision, .hdr, .sdr])
        XCTAssertEqual(facets.sounds, [.atmos, .lossless, .surround, .stereo])
        XCTAssertEqual(facets.services, [.realDebrid, .webtor])
        XCTAssertEqual(facets.releases, [.remux, .bluRay, .web, .tv])
        XCTAssertEqual(facets.languages, ["de", "en", "multi"])

        var selected = StreamFilter()
        selected.resolutions = [.sd]
        selected.services = [.torBox]
        facets = StreamFacets(sample, selected: selected)
        XCTAssertEqual(facets.resolutions, [.uhd, .fullHD, .hd, .sd])
        XCTAssertEqual(facets.services, [.realDebrid, .torBox, .webtor])
    }

    func testSortOrders() {
        XCTAssertEqual(StreamRanker.ranked(sample).map(\.index), [0, 1, 2, 3, 4])
        XCTAssertEqual(StreamRanker.ranked(sample, sort: .bitrate).map(\.index), [0, 1, 2, 3, 4])
        // Die kleinste zuerst, aber was erst geladen werden muss, bleibt hinten.
        XCTAssertEqual(StreamRanker.ranked(sample, sort: .smallest).map(\.index), [3, 2, 1, 0, 4])
        XCTAssertEqual(StreamRanker.ranked(sample, sort: .audio).map(\.index), [0, 1, 2, 3, 4])
        XCTAssertEqual(StreamRanker.ranked(sample, sort: .release).map(\.index), [0, 2, 1, 3, 4])

        var settings = PlaybackSettings()
        settings.maxResolution = .fullHD
        XCTAssertEqual(StreamRanker.ranked(sample, preferences: settings, sort: .bitrate).map(\.index), [0, 1, 2, 3, 4])
        XCTAssertEqual(StreamRanker.ranked(sample, preferences: settings).map(\.index), [2, 3, 0, 1, 4])
    }

    func testSettingsKeepSortAndFilter() throws {
        var settings = PlaybackSettings()
        settings.streamSort = .bitrate
        settings.streamFilter.resolutions = [.uhd]
        settings.streamFilter.services = [.webtor, .realDebrid]
        settings.streamFilter.languages = ["de"]
        let restored = try JSONDecoder().decode(PlaybackSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored, settings)

        // Ältere Einstellungen ohne diese Felder und unbekannte Werte bleiben lesbar.
        let old = try JSONDecoder().decode(PlaybackSettings.self, from: Data(#"{"skipForward":20}"#.utf8))
        XCTAssertEqual(old.streamSort, .recommended)
        XCTAssertTrue(old.streamFilter.isEmpty)
        let odd = try JSONDecoder().decode(PlaybackSettings.self, from: Data(#"{"streamSort":"neu","streamFilter":{"services":["webtor","neu"]}}"#.utf8))
        XCTAssertEqual(odd.streamSort, .recommended)
        XCTAssertEqual(odd.streamFilter.services, [.webtor])
    }
}
