#if canImport(SwiftUI)
import SwiftUI
import Combine
import AetherEngine
import FramesCore

/// Die eine Player-Engine der App. Sie lebt so lange wie die App und lädt Titel nacheinander.
@MainActor
enum PlayerEngine {
    static let shared: AetherEngine? = {
        guard let engine = try? AetherEngine() else { return nil }
        // Frames spielt selbst keinen anderen Ton, also darf die Engine die Tonsitzung am Ende freigeben.
        engine.deactivatesAudioSessionOnStop = true
        return engine
    }()
}

/// Eine Ton- oder Untertitelspur zur Auswahl im Player.
struct PlayerTrack: Identifiable {
    let id: String
    let label: String
    let isActive: @MainActor () -> Bool
    let select: @MainActor () -> Void
}

/// Zustand einer laufenden Wiedergabe, aufbereitet für die Bedienoberfläche.
///
/// Die Engine liefert Bild, Ton, Spuren, Untertitel und Vorschaubilder. Hier entsteht daraus,
/// was die Oberfläche zeigt: Zeit, Zeitleiste, Spulen mit Vorschau, Skip mit den eingestellten Intervallen.
@MainActor
@Observable
final class PlayerSession {
    let engine: AetherEngine

    private(set) var isPlaying = false
    private(set) var isBusy = true
    private(set) var hasPicture = false
    private(set) var hasEnded = false
    private(set) var failure: String?
    private(set) var duration: Double = 0
    private(set) var time: Double = 0
    private(set) var buffered: Double = 0
    private(set) var formatLabel: String?
    private(set) var audioTracks: [PlayerTrack] = []
    private(set) var subtitleTracks: [PlayerTrack] = []
    /// Zählt hoch, wenn sich die gewählte Spur ändert, damit die Auswahl neu gezeichnet wird.
    private(set) var trackRevision = 0
    private(set) var subtitleText: String?
    /// Zielposition, solange gespult wird. `nil`, wenn die Zeitleiste der Wiedergabe folgt.
    private(set) var scrubTime: Double?
    private(set) var scrubImage: CGImage?
    private(set) var flash: String?

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var cues: [SubtitleCue] = []
    @ObservationIgnored private var commitTask: Task<Void, Never>?
    @ObservationIgnored private var thumbnailTask: Task<Void, Never>?
    @ObservationIgnored private var flashTask: Task<Void, Never>?

    init(engine: AetherEngine) {
        self.engine = engine
        observe()
    }

    private func observe() {
        engine.$state
            .sink { [weak self] state in self?.apply(state) }
            .store(in: &cancellables)
        engine.$duration
            .sink { [weak self] value in self?.duration = value.isFinite ? max(0, value) : 0 }
            .store(in: &cancellables)
        engine.$videoFormat
            .sink { [weak self] format in self?.formatLabel = Self.label(for: format) }
            .store(in: &cancellables)
        engine.$hasFirstFrameReadyForDisplay
            .sink { [weak self] ready in self?.hasPicture = ready }
            .store(in: &cancellables)
        engine.clock.$currentTime
            .sink { [weak self] value in
                guard let self, value.isFinite else { return }
                self.time = max(0, value)
            }
            .store(in: &cancellables)
        engine.clock.$bufferedPosition
            .sink { [weak self] value in self?.buffered = value.isFinite ? max(0, value) : 0 }
            .store(in: &cancellables)
        engine.clock.$sourceTime
            .sink { [weak self] value in self?.updateSubtitle(at: value) }
            .store(in: &cancellables)
        engine.$subtitleCues
            .sink { [weak self] cues in
                guard let self else { return }
                self.cues = cues
                self.updateSubtitle(at: self.engine.clock.sourceTime)
            }
            .store(in: &cancellables)
        // Veröffentlichte Werte melden sich, bevor sie gesetzt sind. Deshalb erst im nächsten Durchlauf lesen.
        engine.$audioTracks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildTracks() }
            .store(in: &cancellables)
        engine.$subtitleTracks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildTracks() }
            .store(in: &cancellables)
        engine.$activeAudioTrackIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.trackRevision += 1 }
            .store(in: &cancellables)
        engine.$activeSubtitleTrackIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.trackRevision += 1 }
            .store(in: &cancellables)
        engine.$isSubtitleActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.trackRevision += 1 }
            .store(in: &cancellables)
    }

    // MARK: Laden und Beenden

    func start(_ route: PlayerRoute, settings: PlaybackSettings, resumeAt: Double?) async {
        failure = nil
        hasEnded = false
        var options = LoadOptions()
        options.httpHeaders = route.headers
        options.preferredAudioLanguages = [settings.audioLanguage, "en"]
        if let language = settings.subtitleLanguage {
            options.preferredSubtitleLanguages = [language]
        }
        do {
            if let resumeAt {
                try await engine.load(url: route.url, startPosition: resumeAt, options: options)
            } else {
                try await engine.load(url: route.url, options: options)
            }
        } catch is CancellationError {
            // Ein neuerer Ladevorgang hat diesen abgelöst.
        } catch {
            failure = error.localizedDescription
        }
    }

    func stop() {
        commitTask?.cancel()
        thumbnailTask?.cancel()
        flashTask?.cancel()
        cancellables.removeAll()
        engine.stop()
    }

    /// Stand der Wiedergabe für das Stremio-Konto.
    func progress(for item: PlaybackItem) -> WatchProgress {
        WatchProgress(
            metaId: item.metaId, type: item.type, name: item.name, poster: item.poster,
            videoId: item.videoId, position: hasEnded ? duration : time, duration: duration
        )
    }

    // MARK: Bedienung

    func togglePlay() {
        engine.togglePlayPause()
    }

    /// Ein Druck auf eine Skip-Taste. Mehrere schnell hintereinander summieren sich, die Zeitleiste
    /// zeigt das Ziel samt Vorschaubild, und gesprungen wird einmal am Ende.
    func skip(_ direction: SkipDirection, settings: PlaybackSettings) {
        let base = scrubTime ?? time
        let target = settings.seekTarget(from: base, duration: duration > 0 ? duration : nil, direction: direction)
        let interval = direction == .forward ? settings.skipForward : settings.skipBackward
        showFlash("\(direction == .forward ? "+" : "−")\(interval.label)")
        scrub(to: target, preview: settings.scrubPreview)
        commitTask?.cancel()
        commitTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.commitScrub()
        }
    }

    /// Spulen mit dem Finger oder der Maus: die Zeitleiste folgt, gesprungen wird beim Loslassen.
    func scrub(to target: Double, preview: Bool) {
        let upper = duration > 0 ? duration : target
        let clamped = min(max(0, target), upper)
        scrubTime = clamped
        thumbnailTask?.cancel()
        guard preview, engine.supportsCacheBackedStills else {
            scrubImage = nil
            return
        }
        thumbnailTask = Task { [weak self] in
            guard let self else { return }
            let image = await self.engine.scrubThumbnail(atSeconds: clamped)
            guard !Task.isCancelled, self.scrubTime != nil else { return }
            // Kein Bild für diese Stelle heißt: das letzte stehen lassen, die Zeitmarke stimmt trotzdem.
            if let image { self.scrubImage = image }
        }
    }

    func commitScrub() {
        commitTask?.cancel()
        guard let target = scrubTime else { return }
        time = target
        Task { [weak self] in
            guard let self else { return }
            await self.engine.seek(to: target)
            // Nur aufräumen, wenn inzwischen nicht schon weitergespult wurde.
            if self.scrubTime == target {
                self.scrubTime = nil
                self.scrubImage = nil
                self.thumbnailTask?.cancel()
            }
        }
    }

    private func showFlash(_ text: String) {
        flashTask?.cancel()
        withAnimation(Signal.Motion.press) { flash = text }
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            withAnimation(Signal.Motion.sheet) { self?.flash = nil }
        }
    }

    var subtitlesAreOff: Bool {
        !engine.isSubtitleActive
    }

    func turnSubtitlesOff() {
        engine.clearSubtitle()
    }

    // MARK: Aufbereitung

    private func apply(_ state: PlaybackState) {
        switch state {
        case .playing:
            isPlaying = true
            isBusy = false
            hasEnded = false
        case .paused, .idle:
            isPlaying = false
            isBusy = false
        case .loading, .seeking:
            isBusy = true
        case .ended:
            isPlaying = false
            isBusy = false
            hasEnded = true
        case .error(let message):
            isPlaying = false
            isBusy = false
            failure = message
        default:
            break
        }
    }

    private static func label(for format: VideoFormat) -> String? {
        switch format {
        case .dolbyVision: return "DOLBY VISION"
        case .hdr10Plus: return "HDR10+"
        case .hdr10: return "HDR10"
        case .hlg: return "HLG"
        default: return nil
        }
    }

    private func rebuildTracks() {
        let engine = engine
        audioTracks = engine.audioTracks.enumerated().map { position, track in
            PlayerTrack(
                id: "audio-\(position)",
                label: Self.label(name: track.name, language: track.language, fallback: "Spur \(position + 1)"),
                isActive: { engine.activeAudioTrackIndex == track.id },
                select: { engine.selectAudioTrack(index: track.id) }
            )
        }
        subtitleTracks = engine.subtitleTracks.enumerated().map { position, track in
            PlayerTrack(
                id: "subtitle-\(position)",
                label: Self.label(name: track.name, language: track.language, fallback: "Untertitel \(position + 1)"),
                isActive: { engine.isSubtitleActive && engine.activeSubtitleTrackIndex == track.id },
                select: { engine.selectSubtitleTrack(index: track.id) }
            )
        }
        trackRevision += 1
    }

    private static func label(name: String?, language: String?, fallback: String) -> String {
        let parts = [language?.uppercased(), name].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? fallback : parts.joined(separator: " · ")
    }

    private func updateSubtitle(at sourceTime: Double) {
        guard !cues.isEmpty else {
            if subtitleText != nil { subtitleText = nil }
            return
        }
        var lines: [String] = []
        for cue in cues {
            let start: Double? = cue.startTime
            let end: Double? = cue.endTime
            let text: String? = cue.text
            guard let start, let end, let text, !text.isEmpty else { continue }
            if start <= sourceTime, sourceTime <= end { lines.append(text) }
        }
        let joined = lines.isEmpty ? nil : lines.joined(separator: "\n")
        if joined != subtitleText { subtitleText = joined }
    }
}
#endif
