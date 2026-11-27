#if canImport(SwiftUI)
import SwiftUI
import AetherEngine
import FramesCore

/// Der Player. Bild und Ton kommen aus der Engine, die Bedienung ist die von Frames:
/// Skip mit den eingestellten Intervallen, Zeitleiste, Bildvorschau beim Spulen, Ton- und Untertitelwahl.
struct PlayerView: View {
    let route: PlayerRoute
    @Environment(AppModel.self) private var model
    @State private var session: PlayerSession?
    @State private var engineFailed = false
    /// Die Folge, die gerade läuft. Wechselt, wenn die nächste Folge startet oder eine aus der Liste gewählt wird.
    @State private var current: PlayerRoute?
    @State private var flow = EpisodeFlow()

    private var playing: PlayerRoute { current ?? route }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let session {
                PlayerStage(route: playing, session: session, flow: flow)
            } else if engineFailed {
                SignalNotice("Wiedergabe nicht möglich", detail: "Der Player ließ sich auf diesem Gerät nicht starten.")
            }
        }
        .navigationBarBackButtonHidden()
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        .persistentSystemOverlays(.hidden)
        #endif
        .task {
            guard session == nil else { return }
            guard let engine = PlayerEngine.shared else {
                engineFailed = true
                return
            }
            let newSession = PlayerSession(engine: engine)
            session = newSession
            flow.isPlaying = { [weak newSession] in newSession?.isPlaying ?? false }
            flow.onPlay = { next in Task { await switchEpisode(to: next) } }
            let resume = model.resumePosition(metaId: route.item.metaId, videoId: route.item.videoId)
            await newSession.start(route, settings: model.settings, resumeAt: resume)
        }
        .onAppear { model.isPlayerActive = true }
        .onDisappear {
            model.isPlayerActive = false
            flow.stop()
            guard let session else { return }
            let progress = session.progress(for: playing.item)
            session.stop()
            Task { await model.saveProgress(progress) }
        }
    }

    /// Spielt eine andere Folge im selben Player, ohne zurück zur Quellenliste.
    private func switchEpisode(to next: PlayerRoute) async {
        guard let session else { return }
        let progress = session.progress(for: playing.item)
        Task { await model.saveProgress(progress) }
        current = next
        let resume = model.resumePosition(metaId: next.item.metaId, videoId: next.item.videoId)
        await session.start(next, settings: model.settings, resumeAt: resume)
    }
}

private struct PlayerStage: View {
    let route: PlayerRoute
    let session: PlayerSession
    let flow: EpisodeFlow
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var controlsVisible = true
    @State private var panel: Panel?
    @State private var hideTask: Task<Void, Never>?
    @FocusState private var focus: FocusTarget?

    private enum Panel {
        case audio, subtitles, episodes
    }

    private enum FocusTarget: Hashable {
        case surface, tracks, episodes, segmentSkip, nextEpisode
    }

    var body: some View {
        ZStack {
            AetherPlayerSurface(engine: session.engine)
                .ignoresSafeArea()

            subtitles

            if let failure = session.failure {
                SignalNotice("Wiedergabe nicht möglich", detail: failure)
            } else if session.isBusy || !session.hasPicture {
                ProgressView()
                    .tint(Signal.Palette.lime)
                    .scaleEffect(1.6)
            }

            surface

            if controlsVisible {
                controls.transition(.opacity)
            }

            episodeOverlay

            if panel == .episodes {
                EpisodesPanel(flow: flow, onSelect: { video in
                    closePanel()
                    flow.play(video: video, settings: model.settings)
                }, onClose: closePanel)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if let panel {
                trackPanel(panel)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if TestHooks.video != nil || TestHooks.sampleStreams != nil {
                // Daran lesen die Simulator-Tests ab, ob Bild und Zeit wirklich laufen.
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier("player-status")
                    .accessibilityLabel(
                        "bild=\(session.hasPicture) spielt=\(session.isPlaying) zeit=\(Int(session.time)) "
                            + "dauer=\(Int(session.duration)) fehler=\(session.failure ?? "-") "
                            + "folge=\(route.item.videoId) taste=\(flow.activeSkip?.kind.rawValue ?? "-") "
                            + "karte=\(flow.card.map { String(describing: $0) } ?? "-") folgen=\(flow.meta?.videos.count ?? 0)"
                    )
            }
        }
        .animation(Signal.Motion.sheet, value: controlsVisible)
        .animation(Signal.Motion.sheet, value: panel)
        .onAppear {
            focus = .surface
            scheduleHide()
        }
        // Zeitmarken und Folgenliste für jede Folge neu, auch wenn die nächste im selben Player startet.
        .task(id: route.item.videoId) { await flow.load(route, model: model) }
        .onChange(of: session.time) { _, time in
            let jump = flow.update(
                time: time, duration: session.duration, isScrubbing: session.scrubTime != nil, settings: model.settings
            )
            if let jump {
                session.jump(to: jump.end(duration: session.duration), flash: jump.kind.skippedLabel)
            }
        }
        .onChange(of: session.chapters) { _, chapters in flow.useChapters(chapters) }
        .onChange(of: session.hasEnded) { _, ended in
            if ended { flow.playbackEnded(settings: model.settings) }
        }
        #if os(tvOS)
        // Erscheint „Intro überspringen“ oder die Karte zur nächsten Folge, liegt der Fokus darauf wie bei Netflix.
        .onChange(of: flow.activeSkip) { _, segment in
            // Die Taste bekommt den Fokus auch bei eingeblendeter Bedienung, sonst pausiert „Auswählen“ nur.
            if segment != nil, panel == nil, focus != .nextEpisode {
                focusSoon(.segmentSkip)
            } else if segment == nil, focus == .segmentSkip {
                focus = .surface
            }
        }
        .onChange(of: flow.card) { old, card in
            if card != nil, old == nil, panel == nil {
                focusSoon(.nextEpisode)
            } else if card == nil, focus == .nextEpisode {
                focus = .surface
            }
        }
        #endif
        .onChange(of: session.isPlaying) { _, isPlaying in
            if isPlaying {
                scheduleHide()
            } else {
                showControls()
                Task { await model.saveProgress(session.progress(for: route.item)) }
            }
        }
        // Zwischenstand sichern, falls die App während der Wiedergabe beendet wird.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, session.isPlaying else { continue }
                await model.saveProgress(session.progress(for: route.item))
            }
        }
        #if os(tvOS) || os(macOS)
        .onExitCommand {
            if panel != nil {
                panel = nil
                focus = .surface
            } else if flow.card != nil, flow.card != .loading {
                flow.dismissCard()
                focus = .surface
            } else if controlsVisible, session.isPlaying {
                controlsVisible = false
                focus = .surface
            } else {
                dismiss()
            }
        }
        #endif
    }

    // MARK: Bildfläche

    /// Fängt Eingaben ab, die keinem Bedienelement gelten. Auf dem Fernseher sitzt hier der Fokus:
    /// links und rechts springen, die Mitte pausiert, hoch und runter holen die Bedienung.
    private var surface: some View {
        Button {
            #if os(tvOS)
            session.togglePlay()
            showControls()
            #else
            if controlsVisible {
                controlsVisible = false
            } else {
                showControls()
            }
            #endif
        } label: {
            Color.clear.contentShape(Rectangle())
        }
        .buttonStyle(BareButtonStyle())
        .focused($focus, equals: .surface)
        .disabled(panel != nil)
        .ignoresSafeArea()
        .accessibilityLabel("Wiedergabe")
        #if os(tvOS)
        .onMoveCommand { direction in
            switch direction {
            case .left: skip(.backward)
            case .right: skip(.forward)
            case .down:
                // Die Fläche füllt den ganzen Bildschirm, darunter liegt für die Fokus-Steuerung nichts.
                // Deshalb führt „runter“ ausdrücklich zu den Tasten unten, bei Serien zuerst zu den Folgen.
                showControls()
                focusSoon(flow.isSeries ? .episodes : .tracks)
            default: showControls()
            }
        }
        .onPlayPauseCommand {
            session.togglePlay()
            showControls()
        }
        #endif
    }

    private var subtitles: some View {
        VStack {
            Spacer()
            if let text = session.subtitleText {
                Text(text)
                    .font(.signal(40, .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black, radius: 2, x: 0, y: 1)
                    .shadow(color: .black.opacity(0.9), radius: 8)
                    .padding(.horizontal, Signal.pt(160))
                    // Rückt nach oben, solange die Zeitleiste zu sehen ist.
                    .padding(.bottom, controlsVisible ? Signal.pt(230) : Signal.pt(70))
            }
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .animation(Signal.Motion.focus, value: controlsVisible)
    }

    // MARK: Bedienung

    private var controls: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: Signal.pt(24)) {
                #if !os(tvOS)
                Button("‹  ZURÜCK") { dismiss() }
                    .buttonStyle(SignalButtonStyle())
                #endif
                VStack(alignment: .leading, spacing: Signal.pt(6)) {
                    if let subtitle = route.item.subtitle {
                        SignalEyebrow(subtitle)
                    }
                    Text(route.item.name)
                        .font(.signal(44, .bold))
                        .tracking(-0.03 * Signal.text(44))
                        .foregroundStyle(Signal.Palette.text)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let format = session.formatLabel {
                    SignalBadge(format, kind: .picture)
                }
            }

            Spacer(minLength: 0)

            #if !os(tvOS)
            HStack(spacing: Signal.pt(28)) {
                Button("«  \(model.settings.skipBackward.label)") { skip(.backward) }
                    .buttonStyle(SignalButtonStyle())
                Button(session.isPlaying ? "PAUSE" : "▶  WEITER") {
                    session.togglePlay()
                    scheduleHide()
                }
                .buttonStyle(SignalButtonStyle(.primary))
                Button("\(model.settings.skipForward.label)  »") { skip(.forward) }
                    .buttonStyle(SignalButtonStyle())
            }
            Spacer(minLength: 0)
            #endif

            if let flash = session.flash {
                Text(flash)
                    .font(.signalMono(26, .bold))
                    .foregroundStyle(Signal.Palette.lime)
                    .shadow(color: .black.opacity(0.8), radius: 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .padding(.bottom, Signal.pt(16))
            }

            ScrubBar(session: session, previewEnabled: model.settings.scrubPreview) { scheduleHide() }
                .padding(.bottom, Signal.pt(22))

            HStack(spacing: Signal.pt(14)) {
                #if os(tvOS)
                Text("◀ \(model.settings.skipBackward.label)   ·   \(model.settings.skipForward.label) ▶")
                    .font(.signalMono(15))
                    .foregroundStyle(Signal.Palette.textMuted)
                #endif
                Spacer(minLength: 0)
                if flow.isSeries {
                    Button("FOLGEN") { open(.episodes) }
                        .buttonStyle(SignalButtonStyle())
                        .focused($focus, equals: .episodes)
                        .accessibilityIdentifier("episodes-button")
                }
                if flow.next != nil {
                    Button("NÄCHSTE FOLGE  »") { flow.playNext(settings: model.settings) }
                        .buttonStyle(SignalButtonStyle())
                }
                if session.audioTracks.count > 1 {
                    Button("TON") { open(.audio) }
                        .buttonStyle(SignalButtonStyle())
                }
                if !session.subtitleTracks.isEmpty {
                    Button("UNTERTITEL") { open(.subtitles) }
                        .buttonStyle(SignalButtonStyle())
                }
            }
            .focused($focus, equals: .tracks)
            #if os(tvOS)
            // Von den Tasten führt „hoch“ zurück ins Bild.
            .onMoveCommand { direction in
                if direction == .up { focus = .surface }
            }
            #endif
        }
        .padding(.horizontal, max(20, Signal.pt(80)))
        .padding(.vertical, max(16, Signal.pt(56)))
        .background {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.75), location: 0),
                    .init(color: .clear, location: 0.3),
                    .init(color: .clear, location: 0.55),
                    .init(color: .black.opacity(0.85), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    private func trackPanel(_ kind: Panel) -> some View {
        // Liest den Zähler, damit die Markierung der gewählten Spur nachzieht.
        let _ = session.trackRevision
        let tracks = kind == .audio ? session.audioTracks : session.subtitleTracks
        return HStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: Signal.pt(10)) {
                SignalEyebrow(kind == .audio ? "Player // Ton" : "Player // Untertitel")
                    .padding(.bottom, Signal.pt(10))
                ScrollView {
                    VStack(spacing: Signal.pt(10)) {
                        if kind == .subtitles {
                            trackRow("Aus", isActive: session.subtitlesAreOff) {
                                session.turnSubtitlesOff()
                            }
                        }
                        ForEach(tracks) { track in
                            trackRow(track.label, isActive: track.isActive()) {
                                track.select()
                            }
                        }
                    }
                    .padding(Signal.pt(10))
                }
                .scrollClipDisabled()
                Button("SCHLIESSEN") { closePanel() }
                    .buttonStyle(SignalButtonStyle())
            }
            .padding(Signal.pt(32))
            .frame(width: max(300, Signal.pt(620)))
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(Signal.Palette.sidebar.ignoresSafeArea())
            .overlay(alignment: .leading) {
                Rectangle().fill(Signal.Palette.lime).frame(width: 3).ignoresSafeArea()
            }
            #if os(tvOS) || os(macOS)
            .focusSection()
            #endif
        }
    }

    private func trackRow(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Signal.pt(14)) {
                Circle()
                    .fill(isActive ? Signal.Palette.lime : Color.clear)
                    .overlay { Circle().stroke(isActive ? Signal.Palette.lime : Signal.Palette.border, lineWidth: 1) }
                    .frame(width: 10, height: 10)
                Text(label)
                    .font(.signal(24, isActive ? .semibold : .medium))
                    .foregroundStyle(Signal.Palette.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Signal.pt(20))
            .frame(maxWidth: .infinity, minHeight: max(44, Signal.pt(64)), alignment: .leading)
            .signalPanel(active: isActive)
        }
        .buttonStyle(SignalCardButtonStyle(radius: 8, grows: false))
    }

    // MARK: Abläufe

    private func skip(_ direction: SkipDirection) {
        session.skip(direction, settings: model.settings)
        showControls()
    }

    private func open(_ kind: Panel) {
        hideTask?.cancel()
        panel = kind
    }

    /// Setzt den Fokus, sobald das Ziel gezeichnet ist. Direkt beim Einblenden greift er auf dem Fernseher noch nicht.
    private func focusSoon(_ target: FocusTarget) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            focus = target
        }
    }

    private func closePanel() {
        panel = nil
        focus = .surface
        scheduleHide()
    }

    // MARK: Folgen

    /// Unten rechts: „Intro überspringen“ und im Abspann die Karte zur nächsten Folge.
    /// Beides steht auch ohne eingeblendete Bedienung und rückt nach oben, solange die Zeitleiste zu sehen ist.
    private var episodeOverlay: some View {
        VStack(alignment: .trailing, spacing: Signal.pt(16)) {
            Spacer(minLength: 0)
            if !controlsVisible, let flash = session.flash {
                Text(flash)
                    .font(.signalMono(22, .bold))
                    .foregroundStyle(Signal.Palette.lime)
                    .shadow(color: .black.opacity(0.8), radius: 8)
                    .transition(.opacity)
            }
            if flow.card != nil {
                NextEpisodeCard(flow: flow, onPlay: {
                    flow.playNext(settings: model.settings)
                }, onDismiss: {
                    flow.dismissCard()
                    focus = .surface
                })
                .focused($focus, equals: .nextEpisode)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if let segment = flow.activeSkip, panel == nil {
                SkipSegmentButton(segment: segment) {
                    session.jump(to: segment.end(duration: session.duration))
                    focus = .surface
                }
                .focused($focus, equals: .segmentSkip)
                #if os(tvOS)
                .onMoveCommand { direction in
                    switch direction {
                    case .left: skip(.backward)
                    case .right: skip(.forward)
                    case .down:
                        // Wie auf der Bildfläche: runter führt zu den Tasten unten.
                        showControls()
                        focusSoon(flow.isSeries ? .episodes : .tracks)
                    default:
                        focus = .surface
                        showControls()
                    }
                }
                #endif
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.horizontal, max(20, Signal.pt(80)))
        .padding(.bottom, controlsVisible ? Signal.pt(250) : max(24, Signal.pt(80)))
        .animation(Signal.Motion.sheet, value: controlsVisible)
        .animation(Signal.Motion.sheet, value: flow.activeSkip)
        .animation(Signal.Motion.sheet, value: flow.card)
    }

    private func showControls() {
        controlsVisible = true
        scheduleHide()
    }

    /// Blendet die Bedienung nach ein paar Sekunden aus, solange der Film läuft und nichts offen ist.
    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, session.isPlaying, panel == nil, session.scrubTime == nil else { return }
            controlsVisible = false
            // Taste und Karte bleiben stehen, wenn die Bedienung verschwindet, ihr Fokus also auch.
            if focus != .segmentSkip, focus != .nextEpisode { focus = .surface }
        }
    }
}

/// Taste ohne eigene Darstellung, für die unsichtbare Fläche über dem Bild.
private struct BareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

// MARK: Zeitleiste

/// Zeitleiste mit Puffer, Position und der Vorschau beim Spulen: Bild und Zeitmarke über dem Ziel.
private struct ScrubBar: View {
    let session: PlayerSession
    let previewEnabled: Bool
    let onInteraction: () -> Void

    private var barHeight: CGFloat { max(6, Signal.pt(10)) }
    private var handleSize: CGFloat { max(14, Signal.pt(22)) }
    private var previewWidth: CGFloat { max(150, Signal.pt(300)) }

    var body: some View {
        let duration = session.duration
        let shown = session.scrubTime ?? session.time
        let fraction = duration > 0 ? min(1, max(0, shown / duration)) : 0
        let bufferedFraction = duration > 0 ? min(1, max(0, session.buffered / duration)) : 0

        VStack(spacing: Signal.pt(14)) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Signal.Palette.line)
                    Capsule().fill(Signal.Palette.lime.opacity(0.35)).frame(width: width * bufferedFraction)
                    Capsule().fill(Signal.Palette.limeFill).frame(width: width * fraction)
                }
                .frame(height: barHeight)
                .overlay(alignment: .leading) {
                    Circle()
                        .fill(Signal.Palette.lime)
                        .frame(width: handleSize, height: handleSize)
                        .shadow(color: Signal.Palette.lime.opacity(0.6), radius: 12)
                        .offset(x: width * fraction - handleSize / 2)
                }
                .overlay(alignment: .bottomLeading) {
                    if session.scrubTime != nil {
                        preview(time: shown)
                            .offset(
                                x: min(max(0, width * fraction - previewWidth / 2), max(0, width - previewWidth)),
                                y: -(barHeight + Signal.pt(24))
                            )
                            .transition(.opacity)
                    }
                }
                .animation(Signal.Motion.focus, value: session.scrubTime != nil)
                .contentShape(Rectangle().inset(by: -18))
                .scrubGesture(width: width, duration: duration, session: session, previewEnabled: previewEnabled, onInteraction: onInteraction)
            }
            .frame(height: barHeight)

            HStack {
                Text(formatPlaybackTime(shown))
                Spacer()
                Text(duration > 0 ? "−" + formatPlaybackTime(max(0, duration - shown)) : "")
            }
            .font(.signalMono(19))
            .foregroundStyle(Signal.Palette.text)
        }
    }

    private func preview(time: Double) -> some View {
        VStack(alignment: .leading, spacing: Signal.pt(6)) {
            Text(formatPlaybackTime(time))
                .font(.signalMono(20, .bold))
                .foregroundStyle(Signal.Palette.background)
                .padding(.horizontal, Signal.pt(10))
                .padding(.vertical, Signal.pt(4))
                .background(Signal.Palette.limeFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            if previewEnabled, let image = session.scrubImage {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: previewWidth, height: previewWidth * 9 / 16)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Signal.Palette.lime, lineWidth: 2)
                    }
                    .shadow(color: .black.opacity(0.7), radius: 24, y: 12)
                    .shadow(color: Signal.Palette.lime.opacity(0.3), radius: 20)
                    .transition(.opacity)
            }
        }
        .frame(width: previewWidth, alignment: .leading)
        .animation(Signal.Motion.focus, value: session.scrubImage != nil)
    }
}

extension View {
    /// Ziehen auf der Zeitleiste spult. Auf dem Fernseher übernehmen das die Richtungstasten.
    @ViewBuilder
    fileprivate func scrubGesture(
        width: CGFloat, duration: Double, session: PlayerSession, previewEnabled: Bool, onInteraction: @escaping () -> Void
    ) -> some View {
        #if os(tvOS)
        self
        #else
        self.gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard duration > 0, width > 0 else { return }
                    session.scrub(to: Double(value.location.x / width) * duration, preview: previewEnabled)
                    onInteraction()
                }
                .onEnded { _ in
                    session.commitScrub()
                    onInteraction()
                }
        )
        #endif
    }
}
#endif
