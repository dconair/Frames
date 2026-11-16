import Foundation

/// Sprungweite der Skip-Tasten. Vor und zurück sind getrennt einstellbar.
public enum SkipInterval: Int, Codable, Sendable, CaseIterable, Identifiable {
    case five = 5, ten = 10, twenty = 20

    public var id: Int { rawValue }
    public var seconds: Double { Double(rawValue) }
    public var label: String { "\(rawValue) S" }
}

public enum IntroSkipMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case showButton, automatic, off

    public var id: String { rawValue }
}

/// Alles, was unter Einstellungen › Wiedergabe steht.
public struct PlaybackSettings: Codable, Sendable, Hashable {
    public var skipForward: SkipInterval = .ten
    public var skipBackward: SkipInterval = .ten
    public var scrubPreview: Bool = true
    public var introSkip: IntroSkipMode = .showButton
    public var autoplayNextEpisode: Bool = true
    public var maxResolution: StreamInfo.Resolution = .uhd
    public var preferDolbyVision: Bool = true
    public var audioLanguage: String = "de"
    public var subtitleLanguage: String?
    /// Sortierung und Filter der Quellenliste. Sie gelten weiter, bis man sie ändert.
    public var streamSort: StreamSort = .recommended
    public var streamFilter = StreamFilter()

    public init() {}

    // Fehlende Felder aus älteren Versionen bekommen ihre Vorgabe, statt die gespeicherten Einstellungen zu verwerfen.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let defaults = PlaybackSettings()
        skipForward = c.value("skipForward") ?? defaults.skipForward
        skipBackward = c.value("skipBackward") ?? defaults.skipBackward
        scrubPreview = c.bool("scrubPreview") ?? defaults.scrubPreview
        introSkip = c.value("introSkip") ?? defaults.introSkip
        autoplayNextEpisode = c.bool("autoplayNextEpisode") ?? defaults.autoplayNextEpisode
        maxResolution = c.value("maxResolution") ?? defaults.maxResolution
        preferDolbyVision = c.bool("preferDolbyVision") ?? defaults.preferDolbyVision
        audioLanguage = c.string("audioLanguage") ?? defaults.audioLanguage
        subtitleLanguage = c.string("subtitleLanguage")
        streamSort = c.value("streamSort") ?? defaults.streamSort
        streamFilter = c.value("streamFilter") ?? defaults.streamFilter
    }
}

public enum SkipDirection: Sendable {
    case forward, backward
}

extension PlaybackSettings {
    /// Zielposition nach einem Druck auf eine Skip-Taste, begrenzt auf Anfang und Ende.
    public func seekTarget(from position: Double, duration: Double?, direction: SkipDirection) -> Double {
        let target: Double
        switch direction {
        case .forward: target = position + skipForward.seconds
        case .backward: target = position - skipBackward.seconds
        }
        let upper = duration.map { max(0, $0) } ?? .greatestFiniteMagnitude
        return min(max(0, target), upper)
    }
}

/// Zeitanzeige im Player: „11:42“ oder „1:07:03“.
public func formatPlaybackTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds.rounded(.down))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let rest = total % 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, rest)
        : String(format: "%d:%02d", minutes, rest)
}
