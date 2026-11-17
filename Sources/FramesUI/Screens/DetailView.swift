#if canImport(SwiftUI)
import SwiftUI
import FramesCore

/// Detailseite eines Titels: Hintergrund, Angaben, bei Serien Staffeln und Folgen.
struct DetailView: View {
    let route: MetaRoute
    @Environment(AppModel.self) private var model
    @State private var meta: Meta?
    @State private var failure: String?
    @State private var season: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Signal.pt(32)) {
                header
                if let meta {
                    if meta.isSeries {
                        episodes(of: meta)
                    }
                    credits(of: meta)
                } else if let failure {
                    SignalNotice("Details nicht verfügbar", detail: failure)
                } else {
                    SignalNotice("Wird geladen", isLoading: true)
                }
            }
            .padding(.horizontal, PageInsets.horizontal)
            .padding(.top, PageInsets.top)
            .padding(.bottom, Signal.pt(80))
        }
        .scrollIndicators(.hidden)
        .background(alignment: .top) { backdrop }
        .signalPage()
        .task(id: route) {
            guard meta == nil else { return }
            do {
                let loaded = try await model.content.meta(type: route.type, id: route.id, addons: model.addons)
                withAnimation(Signal.Motion.sheet) {
                    meta = loaded
                    season = loaded.seasons.first
                }
            } catch {
                failure = (error as? LocalizedError)?.errorDescription ?? "Kein Addon liefert Details zu diesem Titel."
            }
        }
    }

    private var backdrop: some View {
        AsyncImage(url: meta?.background) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Signal.pt(760))
        .clipped()
        .opacity(0.45)
        .overlay {
            LinearGradient(
                colors: [Signal.Palette.background.opacity(0.2), Signal.Palette.background],
                startPoint: .top, endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Signal.pt(20)) {
            SignalEyebrow(eyebrow)
            Text(meta?.name ?? route.name)
                .font(.signal(96, .bold))
                .tracking(-0.05 * Signal.text(96))
                .foregroundStyle(Signal.Palette.text)
                .lineLimit(2)
                .minimumScaleFactor(0.5)

            if let meta {
                let facts = [meta.releaseInfo, meta.runtime, meta.imdbRating.map { "IMDB \($0)" }].compactMap { $0 }
                if !facts.isEmpty {
                    Text(facts.joined(separator: "  ·  ").uppercased())
                        .font(.signalMono(19))
                        .foregroundStyle(Signal.Palette.textMuted)
                }
                if !meta.genres.isEmpty {
                    HStack(spacing: Signal.pt(8)) {
                        ForEach(meta.genres.prefix(4), id: \.self) { SignalBadge($0) }
                    }
                }
                if let description = meta.description {
                    Text(description)
                        .font(.signal(24))
                        .lineSpacing(Signal.pt(8))
                        .foregroundStyle(Signal.Palette.textSoft)
                        .frame(maxWidth: Signal.pt(1000), alignment: .leading)
                        .lineLimit(6)
                }
                if !meta.isSeries {
                    NavigationLink(value: StreamsRoute(item: PlaybackItem(
                        metaId: meta.id, type: meta.type, name: meta.name, poster: meta.poster?.absoluteString,
                        videoId: meta.streamId(), subtitle: meta.releaseInfo, runtimeMinutes: meta.runtimeMinutes
                    ))) {
                        Text("▶  ABSPIELEN")
                    }
                    .buttonStyle(SignalButtonStyle(.primary))
                    .padding(.top, Signal.pt(8))
                }
            }
        }
        .padding(.top, Signal.pt(120))
    }

    private var eyebrow: String {
        let kind: String
        switch route.type {
        case "movie": kind = "Film"
        case "series": kind = "Serie"
        default: kind = route.type
        }
        if let meta, meta.isSeries {
            let count = meta.seasons.filter { $0 > 0 }.count
            return "\(kind) // \(count) \(count == 1 ? "Staffel" : "Staffeln")"
        }
        return kind
    }

    @ViewBuilder
    private func episodes(of meta: Meta) -> some View {
        let seasons = meta.seasons
        let current = season ?? seasons.first ?? 1
        VStack(alignment: .leading, spacing: Signal.pt(20)) {
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
            LazyVStack(spacing: Signal.pt(10)) {
                ForEach(meta.episodes(inSeason: current)) { episode in
                    NavigationLink(value: StreamsRoute(item: PlaybackItem(
                        metaId: meta.id, type: meta.type, name: meta.name, poster: meta.poster?.absoluteString,
                        videoId: meta.streamId(for: episode),
                        subtitle: [episode.code, episode.title].compactMap { $0 }.joined(separator: " · "),
                        runtimeMinutes: meta.runtimeMinutes
                    ))) {
                        EpisodeRow(episode: episode)
                    }
                    .buttonStyle(SignalCardButtonStyle(radius: 8, grows: false))
                }
            }
        }
    }

    @ViewBuilder
    private func credits(of meta: Meta) -> some View {
        let rows = [("Regie", meta.directors), ("Besetzung", meta.cast)].filter { !$0.1.isEmpty }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows, id: \.0) { row in
                    HStack(alignment: .top, spacing: Signal.pt(24)) {
                        Text(row.0.uppercased())
                            .foregroundStyle(Signal.Palette.textMuted)
                            .frame(width: Signal.pt(200), alignment: .leading)
                        Text(row.1.prefix(5).joined(separator: ", "))
                            .foregroundStyle(Signal.Palette.text)
                        Spacer(minLength: 0)
                    }
                    .font(.signalMono(17))
                    .padding(.vertical, Signal.pt(12))
                    .overlay(alignment: .top) { Rectangle().fill(Signal.Palette.line).frame(height: 1) }
                }
            }
            .frame(maxWidth: Signal.pt(1000), alignment: .leading)
        }
    }
}

private struct EpisodeRow: View {
    let episode: Video

    var body: some View {
        HStack(spacing: Signal.pt(20)) {
            AsyncImage(url: episode.thumbnail) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(Signal.Palette.background)
                }
            }
            .frame(width: Signal.pt(180), height: Signal.pt(101))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            VStack(alignment: .leading, spacing: Signal.pt(5)) {
                if let code = episode.code {
                    Text(code)
                        .font(.signalMono(15))
                        .foregroundStyle(Signal.Palette.lime)
                }
                Text(episode.title)
                    .font(.signal(26, .semibold))
                    .foregroundStyle(Signal.Palette.text)
                    .lineLimit(1)
                if let overview = episode.overview {
                    Text(overview)
                        .font(.signal(18))
                        .foregroundStyle(Signal.Palette.textMuted)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Signal.pt(14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .signalPanel()
    }
}
#endif
