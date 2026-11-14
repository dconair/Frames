#if canImport(SwiftUI)
import SwiftUI
import FramesCore

// MARK: Kachel

/// Poster mit Titel darunter. Gleitet der Fokus darauf, wächst sie und leuchtet.
struct PosterCard: View {
    let title: String
    let poster: URL?
    var shape: PosterShape = .poster
    var progress: Double?
    var width: CGFloat = Signal.pt(240)

    var body: some View {
        VStack(alignment: .leading, spacing: Signal.pt(12)) {
            ZStack(alignment: .bottom) {
                Rectangle().fill(Signal.Palette.panel)
                AsyncImage(url: poster) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Text(title)
                            .font(.signal(20, .semibold))
                            .foregroundStyle(Signal.Palette.textMuted)
                            .multilineTextAlignment(.center)
                            .padding(Signal.pt(14))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                if let progress {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.black.opacity(0.6))
                            Rectangle().fill(Signal.Palette.limeFill).frame(width: proxy.size.width * progress)
                        }
                    }
                    .frame(height: max(3, Signal.pt(6)))
                }
            }
            .frame(width: width, height: width / shape.aspectRatio)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Signal.Palette.line, lineWidth: 1) }

            Text(title)
                .font(.signal(20, .medium))
                .foregroundStyle(Signal.Palette.textSoft)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
    }
}

/// Waagerechte Reihe mit Überschrift und Zähler, wie auf dem Home-Entwurf.
struct MediaRow<Item: Identifiable, Card: View>: View {
    let title: String
    let items: [Item]
    @ViewBuilder let card: (Item) -> Card

    var body: some View {
        VStack(alignment: .leading, spacing: Signal.pt(8)) {
            HStack(spacing: Signal.pt(20)) {
                Text(title.uppercased())
                    .font(.signalMono(17, .bold))
                    .tracking(1.2)
                    .foregroundStyle(Signal.Palette.text)
                Rectangle().fill(Signal.Palette.line).frame(height: 1)
                Text(String(format: "%02d", items.count))
                    .font(.signalMono(17))
                    .foregroundStyle(Signal.Palette.textMuted)
            }
            .padding(.horizontal, PageInsets.horizontal)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Signal.pt(24)) {
                    ForEach(items) { item in
                        card(item)
                    }
                }
                .padding(.horizontal, PageInsets.horizontal)
                // Platz für die wachsende Kachel und ihren Lichtschein.
                .padding(.vertical, Signal.pt(28))
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }
}

// MARK: Home, Filme, Serien

struct HomeView: View {
    /// `nil` zeigt alles, sonst nur Kataloge dieses Typs.
    let type: String?
    @Environment(AppModel.self) private var model

    private var heading: (String, String) {
        switch type {
        case "movie": return ("Kataloge // Filme", "Filme")
        case "series": return ("Kataloge // Serien", "Serien")
        default: return ("Aus deinen Addons", "Home")
        }
    }

    var body: some View {
        let catalogs = model.addons.homeCatalogs(type: type)
        let resume = type == nil ? model.library.continueWatching : []
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Signal.pt(28)) {
                SignalPageHeader(eyebrow: heading.0, title: heading.1)
                    .padding(.horizontal, PageInsets.horizontal)
                    .padding(.top, PageInsets.top)

                if !resume.isEmpty {
                    MediaRow(title: "Weiter ansehen", items: resume) { item in
                        NavigationLink(value: MetaRoute(item)) {
                            PosterCard(title: item.name, poster: item.poster, shape: item.posterShape, progress: item.progress)
                        }
                        .buttonStyle(SignalCardButtonStyle())
                    }
                }

                if catalogs.isEmpty {
                    if model.isBusy {
                        SignalNotice("Addons werden geladen", isLoading: true)
                    } else {
                        SignalNotice(
                            "Keine Kataloge",
                            detail: model.errorMessage ?? "In deinem Stremio-Konto ist kein Addon mit Katalogen installiert."
                        )
                    }
                }

                ForEach(catalogs) { ref in
                    CatalogRow(ref: ref, showsType: type == nil)
                }
            }
            .padding(.bottom, Signal.pt(80))
        }
        .scrollIndicators(.hidden)
        .signalPage()
    }
}

/// Lädt seinen Katalog erst, wenn die Reihe in Sicht kommt. Leere Kataloge verschwinden.
private struct CatalogRow: View {
    let ref: CatalogRef
    let showsType: Bool
    @Environment(AppModel.self) private var model
    @State private var metas: [Meta]?

    private var title: String {
        guard showsType else { return ref.title }
        let kind: String
        switch ref.type {
        case "movie": kind = "Filme"
        case "series": kind = "Serien"
        default: kind = ref.type
        }
        return "\(ref.title) // \(kind)"
    }

    var body: some View {
        Group {
            if let metas {
                if !metas.isEmpty {
                    MediaRow(title: title, items: metas) { meta in
                        NavigationLink(value: MetaRoute(meta)) {
                            PosterCard(title: meta.name, poster: meta.poster, shape: meta.posterShape)
                        }
                        .buttonStyle(SignalCardButtonStyle())
                    }
                    .transition(.opacity)
                }
            } else {
                // Platzhalter in Reihenhöhe, damit die Seite beim Laden nicht springt.
                Color.clear.frame(height: Signal.pt(240) * 1.5 + Signal.pt(120))
            }
        }
        .animation(Signal.Motion.sheet, value: metas?.count)
        .task(id: ref.id) {
            guard metas == nil else { return }
            let page = try? await model.content.catalog(ref)
            metas = page?.metas ?? []
        }
    }
}

// MARK: Bibliothek

struct LibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let items = model.library.library
        ScrollView {
            VStack(alignment: .leading, spacing: Signal.pt(32)) {
                SignalPageHeader(eyebrow: "Synchron mit deinem Stremio-Konto", title: "Bibliothek")
                if items.isEmpty {
                    SignalNotice("Noch nichts gespeichert", detail: "Titel, die du in Stremio zur Bibliothek hinzufügst, erscheinen hier.")
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: Signal.pt(240)), spacing: Signal.pt(24), alignment: .top)],
                        alignment: .leading,
                        spacing: Signal.pt(36)
                    ) {
                        ForEach(items) { item in
                            NavigationLink(value: MetaRoute(item)) {
                                PosterCard(title: item.name, poster: item.poster, shape: item.posterShape, progress: item.progress)
                            }
                            .buttonStyle(SignalCardButtonStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, PageInsets.horizontal)
            .padding(.top, PageInsets.top)
            .padding(.bottom, Signal.pt(80))
        }
        .scrollIndicators(.hidden)
        .signalPage()
    }
}

// MARK: Suche

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var results: [SearchGroup] = []
    @State private var isSearching = false
    @State private var searched = false

    struct SearchGroup: Identifiable {
        let ref: CatalogRef
        let metas: [Meta]
        var id: String { ref.id }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Signal.pt(28)) {
                VStack(alignment: .leading, spacing: Signal.pt(28)) {
                    SignalPageHeader(eyebrow: "In allen Addons", title: "Suche")
                    TextField("Titel suchen", text: $query)
                        .font(.signal(28, .medium))
                        .foregroundStyle(Signal.Palette.text)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        #if os(macOS)
                        .textFieldStyle(.plain)
                        #endif
                        #if !os(tvOS)
                        .padding(.horizontal, Signal.pt(26))
                        .frame(minHeight: max(44, Signal.pt(72)))
                        .signalPanel()
                        #endif
                }
                .padding(.horizontal, PageInsets.horizontal)
                .padding(.top, PageInsets.top)

                if isSearching {
                    SignalNotice("Suche läuft", isLoading: true)
                } else if results.isEmpty, searched {
                    SignalNotice("Nichts gefunden", detail: "Kein Addon kennt einen Titel mit diesem Namen.")
                }

                ForEach(results) { group in
                    MediaRow(title: "\(group.ref.title) // \(group.ref.addon.manifest.name)", items: group.metas) { meta in
                        NavigationLink(value: MetaRoute(meta)) {
                            PosterCard(title: meta.name, poster: meta.poster, shape: meta.posterShape)
                        }
                        .buttonStyle(SignalCardButtonStyle())
                    }
                }
            }
            .padding(.bottom, Signal.pt(80))
        }
        .scrollIndicators(.hidden)
        .signalPage()
        // Sucht kurz nach der letzten Eingabe. Jede neue Eingabe bricht die laufende Suche ab.
        .task(id: query) {
            let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard term.count >= 2 else {
                results = []
                searched = false
                isSearching = false
                return
            }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            isSearching = true
            let found = await model.content.search(term, addons: model.addons)
            guard !Task.isCancelled else { return }
            withAnimation(Signal.Motion.sheet) {
                results = found.map { SearchGroup(ref: $0.0, metas: $0.1) }
                searched = true
                isSearching = false
            }
        }
    }
}
#endif
