import Foundation

/// Abschnitte einer Folge, die man überspringen kann: Rückblick, Intro, Abspann, Vorschau.
public enum SegmentKind: String, Sendable, Hashable, CaseIterable {
    case recap, intro, credits, preview

    /// Beschriftung der Taste im Player.
    public var skipLabel: String {
        switch self {
        case .recap: return "RÜCKBLICK ÜBERSPRINGEN"
        case .intro: return "INTRO ÜBERSPRINGEN"
        case .credits: return "ABSPANN ÜBERSPRINGEN"
        case .preview: return "VORSCHAU ÜBERSPRINGEN"
        }
    }

    /// Kurze Meldung nach dem automatischen Sprung.
    public var skippedLabel: String {
        switch self {
        case .recap: return "RÜCKBLICK ÜBERSPRUNGEN"
        case .intro: return "INTRO ÜBERSPRUNGEN"
        case .credits: return "ABSPANN ÜBERSPRUNGEN"
        case .preview: return "VORSCHAU ÜBERSPRUNGEN"
        }
    }
}

/// Woher die Zeitmarken einer Folge stammen.
public enum SegmentSource: String, Sendable, Hashable {
    case introDB = "IntroDB"
    case theIntroDB = "TheIntroDB"
    case aniSkip = "AniSkip"
    case chapters = "Kapitel"
    case test = "Test"
}

/// Ein Abschnitt in Sekunden auf der Zeitachse des Players. Ohne Ende reicht er bis zum Schluss.
public struct MediaSegment: Sendable, Hashable {
    public var kind: SegmentKind
    public var start: Double
    public var end: Double?
    public var source: SegmentSource

    public init(kind: SegmentKind, start: Double, end: Double?, source: SegmentSource) {
        self.kind = kind
        self.start = start
        self.end = end
        self.source = source
    }

    /// Ende, wobei ein offenes Ende die Dauer der Datei nimmt.
    public func end(duration: Double) -> Double {
        end ?? (duration > 0 ? duration : .greatestFiniteMagnitude)
    }

    public func contains(_ time: Double, duration: Double) -> Bool {
        time >= start && time < end(duration: duration)
    }

    /// Unbrauchbare Angaben (Ende vor Anfang, null Sekunden lang) fallen weg.
    var isUsable: Bool {
        guard start.isFinite, start >= 0 else { return false }
        if let end { return end.isFinite && end - start >= 1 }
        return true
    }
}

/// Alle bekannten Abschnitte einer Folge.
public struct MediaSegments: Sendable, Hashable {
    public var segments: [MediaSegment]

    public init(_ segments: [MediaSegment] = []) {
        self.segments = segments.filter(\.isUsable).sorted { $0.start < $1.start }
    }

    public var isEmpty: Bool { segments.isEmpty }

    /// Quellen, die zu dieser Folge beigetragen haben, in der Reihenfolge ihres Vorrangs.
    public var sources: [SegmentSource] {
        var seen: [SegmentSource] = []
        for segment in segments where !seen.contains(segment.source) { seen.append(segment.source) }
        return seen
    }

    /// Rückblick oder Intro an dieser Stelle, sofern danach noch genug übrig ist, dass sich ein Sprung lohnt.
    public func skippable(at time: Double, duration: Double) -> MediaSegment? {
        segments.first { segment in
            (segment.kind == .intro || segment.kind == .recap)
                && segment.contains(time, duration: duration)
                && segment.end(duration: duration) - time > 1.5
        }
    }

    /// Ab hier läuft der Abspann. Ein Abschnitt in der ersten Hälfte gilt nicht: manche Quellen nennen
    /// den Vorspann mit Namen auch „credits“.
    public func creditsStart(duration: Double) -> Double? {
        let candidates = segments.filter { $0.kind == .credits || $0.kind == .preview }
        let late = candidates.filter { duration <= 0 || $0.start >= duration * 0.5 }
        return late.map(\.start).min()
    }

    /// Führt mehrere Quellen zusammen. Je Art zählt die erste Quelle, die sie kennt.
    public static func merged(_ sets: [MediaSegments]) -> MediaSegments {
        var result: [MediaSegment] = []
        for kind in SegmentKind.allCases {
            if let set = sets.first(where: { $0.segments.contains { $0.kind == kind } }) {
                result += set.segments.filter { $0.kind == kind }
            }
        }
        return MediaSegments(result)
    }
}

// MARK: Kapitel

extension MediaSegments {
    /// Ein Kapitel, wie es die Datei mitbringt.
    public struct Chapter: Sendable, Hashable {
        public var name: String
        public var start: Double
        public var duration: Double

        public init(name: String, start: Double, duration: Double) {
            self.name = name
            self.start = start
            self.duration = duration
        }
    }

    /// Liest Abschnitte aus Kapitelnamen wie „Intro“, „Opening“, „Recap“, „Abspann“ oder „ED“.
    /// Nummerierte Kapitel („Chapter 01“) tragen nichts bei.
    public static func fromChapters(_ chapters: [Chapter]) -> MediaSegments {
        MediaSegments(chapters.compactMap { chapter in
            guard let kind = kind(ofChapter: chapter.name), chapter.duration > 0 else { return nil }
            return MediaSegment(kind: kind, start: chapter.start, end: chapter.start + chapter.duration, source: .chapters)
        })
    }

    static func kind(ofChapter name: String) -> SegmentKind? {
        let words = name.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .split { !$0.isLetter }
            .map(String.init)
        guard !words.isEmpty else { return nil }
        let text = words.joined(separator: " ")
        func has(_ phrases: [String]) -> Bool {
            phrases.contains { phrase in
                phrase.contains(" ") ? text.contains(phrase) : words.contains(phrase)
            }
        }
        if has(["recap", "previously", "ruckblick", "rueckblick", "bisher", "zuvor"]) { return .recap }
        if has(["preview", "vorschau", "next episode", "naechste folge", "nachste folge", "next time"]) { return .preview }
        // Vor dem Abspann prüfen, damit „Opening Credits“ als Intro gilt.
        if has(["intro", "opening", "op", "vorspann", "titelsequenz"]) { return .intro }
        if has(["credits", "credit", "ending", "ed", "outro", "abspann", "nachspann"]) { return .credits }
        return nil
    }
}
