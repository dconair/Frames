#if canImport(SwiftUI)
import SwiftUI
import FramesCore

// MARK: Überspringen

/// „Intro überspringen“ unten rechts, solange Rückblick oder Intro laufen. Auch ohne eingeblendete Bedienung.
/// Im Modus „Automatisch“ füllt sich die Taste von links nach rechts, dann wird von selbst gesprungen.
struct SkipSegmentButton: View {
    let segment: MediaSegment
    /// Fortschritt des Countdowns, `nil` ohne Countdown.
    var progress: Double?
    let action: () -> Void

    var body: some View {
        Group {
            if let progress {
                Button(action: action) { label }
                    .buttonStyle(CountdownButtonStyle(progress: progress))
            } else {
                Button(action: action) { label }
                    .buttonStyle(SignalButtonStyle(.primary))
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 18, y: 8)
        .shadow(color: Signal.Palette.lime.opacity(0.35), radius: 16)
        .accessibilityIdentifier("segment-skip")
    }

    private var label: some View {
        HStack(spacing: Signal.pt(12)) {
            Text(segment.kind.skipLabel)
            Text("»")
        }
    }
}

// MARK: Nächste Folge

/// Karte im Abspann: Vorschaubild, Code und Titel der Folge, darunter die Taste mit dem Countdown.
struct NextEpisodeCard: View {
    let flow: EpisodeFlow
    let onPlay: () -> Void
    let onDismiss: () -> Void

    private var width: CGFloat { max(280, Signal.pt(560)) }

    var body: some View {
        if let state = flow.card, let video = flow.cardVideo {
            VStack(alignment: .leading, spacing: Signal.pt(14)) {
                HStack(alignment: .top, spacing: Signal.pt(16)) {
                    thumbnail(video)
                    VStack(alignment: .leading, spacing: Signal.pt(6)) {
                        SignalEyebrow(video.id == flow.next?.id ? "Nächste Folge" : "Folge")
                        if let code = video.code {
                            Text(code)
                                .font(.signalMono(16, .bold))
                                .foregroundStyle(Signal.Palette.lime)
                        }
                        Text(video.title)
                            .font(.signal(24, .semibold))
                            .foregroundStyle(Signal.Palette.text)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                actions(state)
            }
            .padding(Signal.pt(20))
            .frame(width: width, alignment: .leading)
            .background(Signal.Palette.sidebar, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Signal.Palette.border, lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                Rectangle().fill(Signal.Palette.lime).frame(width: 3).padding(.vertical, Signal.pt(16))
            }
            .shadow(color: .black.opacity(0.6), radius: 30, y: 14)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("next-episode")
            #if os(tvOS) || os(macOS)
            .focusSection()
            #endif
        }
    }

    @ViewBuilder
    private func actions(_ state: EpisodeFlow.CardState) -> some View {
        switch state {
        case .counting(let remaining):
            HStack(spacing: Signal.pt(12)) {
                Button(action: onPlay) {
                    Text("▶  NÄCHSTE FOLGE  \(remaining)")
                        .monospacedDigit()
                }
                .buttonStyle(CountdownButtonStyle(progress: flow.cardProgress))
                .accessibilityIdentifier("next-episode-play")
                Button("ABSPANN ANSEHEN", action: onDismiss)
                    .buttonStyle(SignalButtonStyle())
            }
        case .waiting:
            HStack(spacing: Signal.pt(12)) {
                Button("▶  NÄCHSTE FOLGE", action: onPlay)
                    .buttonStyle(SignalButtonStyle(.primary))
                    .accessibilityIdentifier("next-episode-play")
                Button("SCHLIESSEN", action: onDismiss)
                    .buttonStyle(SignalButtonStyle())
            }
        case .loading:
            HStack(spacing: Signal.pt(12)) {
                ProgressView().tint(Signal.Palette.lime)
                Text("QUELLE WIRD GESUCHT")
                    .font(.signalMono(16))
                    .foregroundStyle(Signal.Palette.textMuted)
            }
            .frame(minHeight: max(40, Signal.pt(60)))
        case .noSource:
            VStack(alignment: .leading, spacing: Signal.pt(10)) {
                Text("KEINE DIREKTE QUELLE FÜR DIESE FOLGE")
                    .font(.signalMono(15))
                    .foregroundStyle(Signal.Palette.danger)
                Button("SCHLIESSEN", action: onDismiss)
                    .buttonStyle(SignalButtonStyle())
            }
        }
    }

    private func thumbnail(_ video: Video) -> some View {
        AsyncImage(url: video.thumbnail) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Signal.Palette.background)
            }
        }
        .frame(width: Signal.pt(190), height: Signal.pt(107))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Primärtaste, die sich während des Countdowns von links nach rechts füllt.
struct CountdownButtonStyle: ButtonStyle {
    let progress: Double

    func makeBody(configuration: Configuration) -> some View {
        Face(progress: progress, configuration: configuration)
    }

    private struct Face: View {
        let progress: Double
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused
        @State private var isHovered = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            configuration.label
                .font(.signalMono(18, .bold))
                .foregroundStyle(Signal.Palette.background)
                .padding(.horizontal, Signal.pt(26))
                .frame(minHeight: max(40, Signal.pt(60)))
                .background {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            shape.fill(Signal.Palette.lime.opacity(0.55))
                            Rectangle()
                                .fill(Signal.Palette.limeFill)
                                .frame(width: proxy.size.width * min(1, max(0, progress)))
                        }
                        .clipShape(shape)
                    }
                }
                .signalFocusRing(isFocused || isHovered, radius: 8, inset: 4)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(Signal.Motion.press, value: configuration.isPressed)
                #if os(macOS)
                .onHover { isHovered = $0 }
                #endif
        }
    }
}

// MARK: Folgenliste

/// Staffeln und Folgen zum Durchblättern, rechts im Player. Die laufende Folge ist markiert.
struct EpisodesPanel: View {
    let flow: EpisodeFlow
    let onSelect: (Video) -> Void
    let onClose: () -> Void
    @State private var season: Int?

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: Signal.pt(14)) {
                SignalEyebrow("Player // Folgen")
                if let meta = flow.meta {
                    Text(meta.name)
                        .font(.signal(32, .bold))
                        .foregroundStyle(Signal.Palette.text)
                        .lineLimit(1)
                    content(meta)
                } else {
                    SignalNotice("Folgen werden geladen", isLoading: true)
                    Spacer(minLength: 0)
                }
                Button("SCHLIESSEN", action: onClose)
                    .buttonStyle(SignalButtonStyle())
            }
            .padding(Signal.pt(32))
            .frame(maxWidth: max(320, Signal.pt(820)))
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

    @ViewBuilder
    private func content(_ meta: Meta) -> some View {
        let seasons = meta.seasons
        let playing = flow.currentVideoId.flatMap(meta.video(id:))
        let current = season ?? playing?.season ?? seasons.first ?? 1
        if seasons.count > 1 {
            ScrollView(.horizontal) {
                SignalSegments(
                    seasons.map { ($0, $0 == 0 ? "SPECIALS" : String(format: "S%02d", $0)) },
                    selection: Binding(get: { current }, set: { season = $0 })
                )
                .padding(Signal.pt(8))
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Signal.pt(10)) {
                    ForEach(meta.episodes(inSeason: current)) { episode in
                        let isPlaying = episode.id == flow.currentVideoId
                        Button { onSelect(episode) } label: {
                            PlayerEpisodeRow(episode: episode, isPlaying: isPlaying)
                        }
                        .buttonStyle(SignalCardButtonStyle(radius: 8, grows: false))
                        .disabled(isPlaying)
                        .id(episode.id)
                    }
                }
                .padding(Signal.pt(10))
            }
            // Die Liste schneidet unten ab, sonst läuft sie unter „Schließen“ durch.
            .onAppear {
                if let id = flow.currentVideoId { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }
}

private struct PlayerEpisodeRow: View {
    let episode: Video
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: Signal.pt(18)) {
            AsyncImage(url: episode.thumbnail) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(Signal.Palette.background)
                }
            }
            .frame(width: Signal.pt(200), height: Signal.pt(112))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                if isPlaying {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Signal.Palette.lime, lineWidth: 2)
                }
            }

            VStack(alignment: .leading, spacing: Signal.pt(5)) {
                HStack(spacing: Signal.pt(10)) {
                    if let code = episode.code {
                        Text(code)
                            .font(.signalMono(15))
                            .foregroundStyle(Signal.Palette.lime)
                    }
                    if isPlaying {
                        Text("LÄUFT")
                            .font(.signalMono(13, .bold))
                            .foregroundStyle(Signal.Palette.background)
                            .padding(.horizontal, Signal.pt(8))
                            .padding(.vertical, Signal.pt(2))
                            .background(Signal.Palette.limeFill, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
                Text(episode.title)
                    .font(.signal(24, .semibold))
                    .foregroundStyle(Signal.Palette.text)
                    .lineLimit(1)
                if let overview = episode.overview {
                    Text(overview)
                        .font(.signal(17))
                        .foregroundStyle(Signal.Palette.textMuted)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Signal.pt(12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .signalPanel(active: isPlaying)
    }
}
#endif
