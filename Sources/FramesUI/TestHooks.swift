#if canImport(SwiftUI)
import Foundation
import FramesCore

/// Startschalter für die automatischen Tests im Simulator. In der ausgelieferten App ohne Wirkung.
enum TestHooks {
    #if DEBUG
    private static let process = ProcessInfo.processInfo

    /// Ohne Konto starten, mit der Grundausstattung an Addons, die Stremio jedem neuen Konto gibt.
    static var isGuest: Bool { process.arguments.contains("-frames-gast") }

    /// Zugangsdaten, mit denen sich die App beim Start selbst anmeldet.
    static var login: (email: String, password: String)? {
        guard let email = process.environment["FRAMES_TEST_EMAIL"], !email.isEmpty,
              let password = process.environment["FRAMES_TEST_PASSWORD"], !password.isEmpty else { return nil }
        return (email, password)
    }

    /// Ein Video, das statt der Hauptansicht sofort im Player läuft.
    static var video: URL? {
        process.environment["FRAMES_TEST_VIDEO"].flatMap(URL.init(string:))
    }

    /// Der Testfilm tritt als erste Folge einer bekannten Serie auf, mit festen Zeitmarken für Rückblick,
    /// Intro und Abspann. So lassen sich Überspringen, Countdown und Folgenliste ohne Konto zeigen.
    static var playsEpisodes: Bool { process.arguments.contains("-frames-folgen") }

    /// Zeitmarken passend zum etwa 52 Sekunden langen Testfilm.
    static var sampleSegments: MediaSegments? {
        guard playsEpisodes else { return nil }
        return MediaSegments([
            MediaSegment(kind: .recap, start: 1, end: 6, source: .test),
            MediaSegment(kind: .intro, start: 9, end: 17, source: .test),
            MediaSegment(kind: .credits, start: 34, end: nil, source: .test),
        ])
    }

    /// Jede Folge spielt im Test wieder den freien Testfilm.
    static var episodeStreams: [SourcedStream]? {
        guard playsEpisodes, let video else { return nil }
        return [SourcedStream(
            stream: FramesCore.Stream(url: video, name: "[RD+] Test 1080p", title: "Serie.S01E02.1080p.WEB-DL.mkv", bingeGroup: "test|1080p"),
            addonName: "Test", index: 0
        )]
    }

    /// Eine feste Quellenliste statt der Antworten der Addons, damit sich Sortierung und Filter ohne Konto zeigen lassen.
    /// Jede Zeile spielt dasselbe frei verfügbare Testvideo.
    static var sampleStreams: [SourcedStream]? {
        guard process.arguments.contains("-frames-beispielquellen") else { return nil }
        let video = URL(string: "https://test-videos.co.uk/vids/jellyfish/mkv/1080/Jellyfish_1080_10s_5MB.mkv")!
        let rows: [(addon: String, name: String, title: String, webtor: Bool)] = [
            ("AIOStreams", "[RD+] AIOStreams 4K", "Film.2160p.UHD.BluRay.REMUX.DV.HDR10.TrueHD.7.1.Atmos-FRAMES.mkv\n💾 58.2 GB", false),
            ("AIOStreams", "[RD+] AIOStreams 4K", "Film.2160p.WEB-DL.DV.HDR10Plus.DDP5.1.Atmos.German.DL-FRAMES.mkv\n💾 24.6 GB 🇩🇪 🇬🇧", false),
            ("AIOStreams", "[RD+] AIOStreams 4K", "Film.2160p.WEB-DL.HDR10.DDP5.1.HEVC-FRAMES.mkv\n💾 16.3 GB", false),
            ("Webtor.io", "[⚡WT]\nTorrentio 4K", "Film.2160p.UHD.BluRay.HDR10.DTS-HD.MA.7.1.German.DL-FRAMES.mkv\n💾 41.9 GB 🇩🇪 🇬🇧", true),
            ("AIOStreams", "[RD+] AIOStreams 1080p", "Film.1080p.BluRay.REMUX.AVC.DTS-HD.MA.5.1-FRAMES.mkv\n💾 29.4 GB", false),
            ("AIOStreams", "[RD+] AIOStreams 1080p", "Film.1080p.BluRay.German.DL.DTS.x264-FRAMES.mkv\n💾 12.8 GB 🇩🇪 🇬🇧", false),
            ("Webtor.io", "[⚡WT]\nTorrentio 1080p", "Film.1080p.WEB-DL.DDP5.1.H.264-FRAMES.mkv\n💾 6.4 GB", true),
            ("Webtor.io", "[WT]\nTorrentio 1080p", "Film.1080p.WEBRip.German.AC3.x265-FRAMES.mkv\n💾 3.1 GB 🇩🇪", true),
            ("AIOStreams", "[RD+] AIOStreams 720p", "Film.720p.WEB-DL.AAC.2.0.H.264-FRAMES.mkv\n💾 1.4 GB", false),
            ("Webtor.io", "[P2P]\nTorrentio 720p", "Film.720p.HDTV.German.AAC.x264-FRAMES.mkv\n💾 950 MB 🇩🇪", true),
        ]
        return rows.enumerated().map { index, row in
            SourcedStream(
                stream: FramesCore.Stream(url: video, name: row.name, title: row.title),
                addonName: row.addon, index: index, isWebtorAddon: row.webtor
            )
        }
    }
    #else
    static let isGuest = false
    static let sampleStreams: [SourcedStream]? = nil
    static let login: (email: String, password: String)? = nil
    static let video: URL? = nil
    static let playsEpisodes = false
    static let sampleSegments: MediaSegments? = nil
    static let episodeStreams: [SourcedStream]? = nil
    #endif
}
#endif
