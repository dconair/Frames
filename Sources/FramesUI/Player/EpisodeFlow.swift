#if canImport(SwiftUI)
import SwiftUI
import FramesCore

/// Alles rund um Folgen im Player: Rückblick und Intro überspringen, die nächste Folge mit Countdown
/// wie bei Netflix, und die Folgenliste zum Durchblättern.
///
/// Die Zeitmarken kommen aus IntroDB und TheIntroDB (Serien mit IMDb-Nummer), aus AniSkip (Anime über Kitsu)
/// und sonst aus den Kapiteln der Datei, wenn die „Intro“, „Opening“ oder „Abspann“ heißen.
@MainActor
@Observable
final class EpisodeFlow {
    /// Sekunden, die der Countdown zur nächsten Folge läuft.
    static let countdown = 10
    /// Sekunden, bis Rückblick oder Intro im Modus „Automatisch“ übersprungen werden.
    static let skipCountdown = 5

    enum CardState: Equatable {
        /// Der Abspann läuft, die nächste Folge startet, wenn der Zähler null erreicht.
        case counting(remaining: Int)
        /// Ohne Autoplay: die Karte steht, bis man sie wählt.
        case waiting
        /// Die Quelle der Folge wird gesucht.
        case loading
        /// Kein Addon liefert eine abspielbare Quelle für die Folge.
        case noSource
    }

    private(set) var meta: Meta?
    private(set) var segments = MediaSegments()
    /// Rückblick oder Intro, in dem die Wiedergabe gerade steht.
    private(set) var activeSkip: MediaSegment?
    /// Im Modus „Automatisch“: wie weit sich die Taste schon gefüllt hat (0 bis 1). `nil` ohne Countdown.
    private(set) var skipProgress: Double?
    /// Sekunden bis zum automatischen Sprung.
    private(set) var skipRemaining: Int?
    /// Wie weit sich die Taste „Nächste Folge“ schon gefüllt hat.
    private(set) var cardProgress: Double = 0
    /// Die Folge nach der laufenden.
    private(set) var next: Video?
    /// Die Karte unten rechts. `nil`, solange der Abspann nicht läuft oder sie weggeklickt wurde.
    private(set) var card: CardState?
    /// Die Folge, um die es auf der Karte geht: die nächste oder die in der Liste gewählte.
    private(set) var cardVideo: Video?

    /// Startet eine Folge im laufenden Player. Setzt der Player.
    @ObservationIgnored var onPlay: ((PlayerRoute) -> Void)?
    /// Springt ans Ende eines Abschnitts, mit oder ohne Einblendung. Setzt der Player.
    @ObservationIgnored var onSkip: ((MediaSegment, _ announce: Bool) -> Void)?
    /// Wahr, solange die Wiedergabe läuft. Pausiert, steht der Countdown.
    @ObservationIgnored var isPlaying: () -> Bool = { true }

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var route: PlayerRoute?
    @ObservationIgnored private var fileSegments = MediaSegments()
    @ObservationIgnored private var remoteSegments = MediaSegments()
    /// Abschnitte, die schon automatisch übersprungen wurden. Wer zurückspult, bekommt dort die Taste.
    @ObservationIgnored private var autoSkipped: Set<Double> = []
    @ObservationIgnored private var creditsDismissed = false
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var skipTask: Task<Void, Never>?
    @ObservationIgnored private var prefetch: Task<PlayerRoute?, Never>?
    @ObservationIgnored private var prefetchedId: String?

    var isSeries: Bool { meta?.isSeries ?? false }
    var currentVideoId: String? { route?.item.videoId }

    // MARK: Laden

    /// Neue Folge: alles zurücksetzen, Zeitmarken und Folgenliste laden.
    func load(_ route: PlayerRoute, model: AppModel) async {
        let sameShow = self.route?.item.metaId == route.item.metaId
        self.route = route
        self.model = model
        reset()
        let item = route.item
        guard item.type == "series" || EpisodeRef(videoId: item.videoId) != nil else { return }
        let known = sameShow ? meta : nil
        // Direkt nach dem Start der App können die Addons noch unterwegs sein.
        for _ in 0..<20 where model.addons.isEmpty {
            try? await Task.sleep(for: .milliseconds(500))
        }
        guard self.route?.item.videoId == item.videoId else { return }
        let content = model.content
        let addons = model.addons
        async let loadedMeta: Meta? = known == nil
            ? try? await content.meta(type: item.type, id: item.metaId, addons: addons)
            : known
        async let loadedSegments = Self.segments(for: item.videoId)
        let (newMeta, newSegments) = await (loadedMeta, loadedSegments)
        guard self.route?.item.videoId == item.videoId else { return }
        meta = newMeta
        next = newMeta?.episode(after: item.videoId)
        remoteSegments = newSegments
        rebuildSegments()
    }

    private static func segments(for videoId: String) async -> MediaSegments {
        if let sample = TestHooks.sampleSegments { return sample }
        return await SegmentService().segments(for: videoId)
    }

    /// Kapitel der Datei, sobald die Engine sie kennt. Sie füllen nur, was die Datenbanken offenlassen.
    func useChapters(_ chapters: [MediaSegments.Chapter]) {
        fileSegments = MediaSegments.fromChapters(chapters)
        rebuildSegments()
    }

    private func rebuildSegments() {
        segments = MediaSegments.merged([remoteSegments, fileSegments])
    }

    private func reset() {
        countdownTask?.cancel()
        cancelSkipCountdown()
        prefetch?.cancel()
        prefetch = nil
        prefetchedId = nil
        segments = MediaSegments()
        remoteSegments = MediaSegments()
        fileSegments = MediaSegments()
        activeSkip = nil
        card = nil
        cardVideo = nil
        next = nil
        autoSkipped = []
        creditsDismissed = false
    }

    func stop() {
        countdownTask?.cancel()
        skipTask?.cancel()
        prefetch?.cancel()
    }

    // MARK: Während der Wiedergabe

    /// Bei jeder neuen Zeit: Taste für Rückblick oder Intro, im Modus „Automatisch“ mit Countdown, Karte im Abspann.
    func update(time: Double, duration: Double, isScrubbing: Bool, settings: PlaybackSettings) {
        let skippable = settings.introSkip == .off ? nil : segments.skippable(at: time, duration: duration)
        if skippable != activeSkip {
            cancelSkipCountdown()
            withAnimation(Signal.Motion.sheet) { activeSkip = skippable }
        }
        if let segment = skippable, settings.introSkip == .automatic {
            if isScrubbing {
                // Wer selbst spult, entscheidet: für diesen Abschnitt bleibt es bei der Taste.
                if skipTask != nil { autoSkipped.insert(segment.start) }
                cancelSkipCountdown()
            } else if skipTask == nil, !autoSkipped.contains(segment.start) {
                startSkipCountdown(for: segment)
            }
        }

        guard let next, duration > 0, card != .loading else { return }
        let creditsAt = segments.creditsStart(duration: duration) ?? Self.fallbackCredits(duration: duration)
        if time >= creditsAt, card == nil, !creditsDismissed, !isScrubbing {
            showCard(for: next, settings: settings)
        } else if time < creditsAt - 2, card != nil {
            // Zurückgespult: die Karte geht wieder weg.
            hideCard()
            creditsDismissed = false
        }
        // Eine Minute vor dem Abspann schon die Quelle suchen, damit es danach ohne Warten weitergeht.
        if time >= creditsAt - 60 { prefetchNext(settings: settings) }
    }

    /// Die Taste füllt sich in fünf Sekunden, dann wird gesprungen. Pausiert, steht der Countdown.
    private func startSkipCountdown(for segment: MediaSegment) {
        let total = Self.skipCountdown
        skipRemaining = total
        skipProgress = 0
        withAnimation(.linear(duration: 1)) { skipProgress = 1 / Double(total) }
        skipTask = Task { [weak self] in
            var remaining = total
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                guard self.isPlaying() else { continue }
                remaining -= 1
                if remaining <= 0 {
                    self.skip(segment, announce: true)
                    return
                }
                self.skipRemaining = remaining
                withAnimation(.linear(duration: 1)) {
                    self.skipProgress = Double(total - remaining + 1) / Double(total)
                }
            }
        }
    }

    private func cancelSkipCountdown() {
        skipTask?.cancel()
        skipTask = nil
        skipProgress = nil
        skipRemaining = nil
    }

    /// Springt über Rückblick oder Intro, per Taste oder nach dem Countdown.
    func skip(_ segment: MediaSegment, announce: Bool = false) {
        autoSkipped.insert(segment.start)
        cancelSkipCountdown()
        onSkip?(segment, announce)
    }

    /// Ohne Marken erscheint die Karte 25 Sekunden vor Schluss, aber nur bei Folgenlänge.
    private static func fallbackCredits(duration: Double) -> Double {
        duration >= 600 ? duration - 25 : .greatestFiniteMagnitude
    }

    /// Die Folge ist zu Ende. Mit Autoplay geht es sofort weiter, sonst bleibt die Karte stehen.
    func playbackEnded(settings: PlaybackSettings) {
        guard let next, card != .loading else { return }
        if settings.autoplayNextEpisode {
            play(video: next, settings: settings)
        } else {
            cardVideo = next
            withAnimation(Signal.Motion.sheet) { card = .waiting }
        }
    }

    private func showCard(for video: Video, settings: PlaybackSettings) {
        cardVideo = video
        guard settings.autoplayNextEpisode else {
            withAnimation(Signal.Motion.sheet) { card = .waiting }
            return
        }
        withAnimation(Signal.Motion.sheet) { card = .counting(remaining: Self.countdown) }
        cardProgress = 0
        withAnimation(.linear(duration: 1)) { cardProgress = 1 / Double(Self.countdown) }
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled, case .counting(let remaining) = self.card else { return }
                guard self.isPlaying() else { continue }
                if remaining <= 1 {
                    self.play(video: video, settings: settings)
                    return
                }
                withAnimation(.linear(duration: 1)) {
                    self.card = .counting(remaining: remaining - 1)
                    self.cardProgress = Double(Self.countdown - remaining + 2) / Double(Self.countdown)
                }
            }
        }
    }

    private func hideCard() {
        countdownTask?.cancel()
        withAnimation(Signal.Motion.sheet) { card = nil }
    }

    /// „Abspann ansehen“: die Karte verschwindet für diese Folge.
    func dismissCard() {
        creditsDismissed = true
        hideCard()
    }

    // MARK: Folge starten

    func playNext(settings: PlaybackSettings) {
        guard let next else { return }
        play(video: next, settings: settings)
    }

    /// Eine Folge aus der Liste oder die nächste: passende Quelle suchen, dann im selben Player abspielen.
    func play(video: Video, settings: PlaybackSettings) {
        countdownTask?.cancel()
        cardVideo = video
        withAnimation(Signal.Motion.sheet) { card = .loading }
        let lookup = (video.id == prefetchedId ? prefetch : nil) ?? makeLookup(for: video, settings: settings)
        Task { [weak self] in
            let found = await lookup?.value
            guard let self, self.cardVideo?.id == video.id else { return }
            if let found {
                self.onPlay?(found)
            } else {
                withAnimation(Signal.Motion.sheet) { self.card = .noSource }
            }
        }
    }

    private func prefetchNext(settings: PlaybackSettings) {
        guard let next, prefetchedId != next.id else { return }
        prefetchedId = next.id
        prefetch = makeLookup(for: next, settings: settings)
    }

    /// Fragt die Addons nach Quellen für die Folge und nimmt die, die zur laufenden Quelle passt.
    private func makeLookup(for video: Video, settings: PlaybackSettings) -> Task<PlayerRoute?, Never>? {
        guard let route, let meta, let model else { return nil }
        // Vom laufenden Eintrag ausgehen, damit alles Übrige (Poster, Laufzeit) erhalten bleibt.
        var item = route.item
        item.videoId = meta.streamId(for: video)
        item.subtitle = [video.code, video.title].compactMap { $0 }.joined(separator: " · ")
        let origin = route.origin
        let content = model.content
        let addons = model.addons
        return Task {
            let streams: [SourcedStream]
            if let sample = TestHooks.episodeStreams {
                streams = sample
            } else {
                streams = await content.streams(type: item.type, id: item.videoId, addons: addons)
            }
            guard let pick = StreamRanker.continuation(streams, after: origin, preferences: settings),
                  let url = pick.stream.playableURL else { return nil }
            return PlayerRoute(url: url, headers: pick.stream.requestHeaders, item: item, origin: StreamOrigin(pick))
        }
    }
}
#endif
