import XCTest
@testable import FramesCore

final class PlaybackSettingsTests: XCTestCase {
    func testSkipIntervalsAreIndependent() {
        var settings = PlaybackSettings()
        settings.skipForward = .twenty
        settings.skipBackward = .five
        XCTAssertEqual(settings.seekTarget(from: 100, duration: 3600, direction: .forward), 120)
        XCTAssertEqual(settings.seekTarget(from: 100, duration: 3600, direction: .backward), 95)
    }

    func testSeekIsClampedToStartAndEnd() {
        let settings = PlaybackSettings()
        XCTAssertEqual(settings.seekTarget(from: 4, duration: 3600, direction: .backward), 0)
        XCTAssertEqual(settings.seekTarget(from: 3595, duration: 3600, direction: .forward), 3600)
        XCTAssertEqual(settings.seekTarget(from: 50, duration: nil, direction: .forward), 60)
    }

    func testOfferedIntervals() {
        XCTAssertEqual(SkipInterval.allCases.map(\.rawValue), [5, 10, 20])
        XCTAssertEqual(SkipInterval.ten.label, "10 S")
    }

    func testSettingsSurviveStorage() throws {
        var settings = PlaybackSettings()
        settings.skipForward = .five
        settings.maxResolution = .fullHD
        settings.introSkip = .automatic
        settings.subtitleLanguage = "en"
        let restored = try JSONDecoder().decode(PlaybackSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored, settings)
    }

    func testOlderStoredSettingsGetDefaults() throws {
        let restored = try JSONDecoder().decode(PlaybackSettings.self, from: Data(#"{"skipForward":20,"unbekannt":1}"#.utf8))
        XCTAssertEqual(restored.skipForward, .twenty)
        XCTAssertEqual(restored.skipBackward, .ten)
        XCTAssertTrue(restored.scrubPreview)
    }

    func testTimeFormatting() {
        XCTAssertEqual(formatPlaybackTime(0), "0:00")
        XCTAssertEqual(formatPlaybackTime(702.9), "11:42")
        XCTAssertEqual(formatPlaybackTime(4023), "1:07:03")
        XCTAssertEqual(formatPlaybackTime(.nan), "0:00")
    }
}
