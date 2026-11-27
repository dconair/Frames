#if canImport(SwiftUI)
import SwiftUI
import FramesCore

/// Einstieg der App: Anmeldung oder Hauptansicht, je nach Zustand.
public struct RootView: View {
    @State private var model: AppModel
    /// Die Start-Animation liegt über allem, bis sie durchgelaufen ist.
    @State private var showsLaunch = TestHooks.video == nil
    private let launchStyle = StartPreferences.styleForThisLaunch

    @MainActor
    public init() {
        _model = State(initialValue: AppModel())
    }

    @MainActor
    public init(model: AppModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        ZStack {
            Signal.Palette.background.ignoresSafeArea()
            switch model.phase {
            case .launching:
                Color.clear
            case .loggedOut:
                LoginView()
                    .transition(.opacity)
            case .ready:
                if let video = TestHooks.video {
                    NavigationStack {
                        PlayerView(route: PlayerRoute(url: video, headers: [:], item: PlaybackItem(
                            metaId: "frames-test", type: "movie", name: "Testvideo", poster: nil,
                            videoId: "frames-test", subtitle: nil
                        )))
                    }
                } else {
                    MainView()
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            if showsLaunch {
                LaunchAnimation(style: launchStyle)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(Signal.Motion.sheet, value: model.phase)
        .modifier(DeepLinkPresenter())
        .environment(model)
        .preferredColorScheme(.dark)
        .tint(Signal.Palette.lime)
        .task { await model.start() }
        .task { await StartPreferences.shared.applyDockIcon() }
        .task {
            try? await Task.sleep(for: .milliseconds(launchStyle.duration))
            withAnimation(.easeOut(duration: 0.4)) { showsLaunch = false }
        }
        .onChange(of: model.settings) { _, _ in model.saveSettings() }
        .onOpenURL { model.open($0) }
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case home, movies, series, library, search, addons, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .movies: return "Filme"
        case .series: return "Serien"
        case .library: return "Bibliothek"
        case .search: return "Suche"
        case .addons: return "Addons"
        case .settings: return "Einstellungen"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .movies: return "film"
        case .series: return "tv"
        case .library: return "square.stack"
        case .search: return "magnifyingglass"
        case .addons: return "puzzlepiece.extension"
        case .settings: return "gearshape"
        }
    }

    /// Die untere Gruppe der Seitenleiste, unter der Trennlinie.
    var isSystem: Bool { self == .addons || self == .settings }
}

/// Die vier Punkte der unteren Leiste auf dem iPhone. Filme und Serien liegen unter Home, Addons und Einstellungen unter Mehr.
enum CompactTab: String, CaseIterable, Identifiable {
    case home, search, library, more

    init(_ section: AppSection) {
        switch section {
        case .home, .movies, .series: self = .home
        case .search: self = .search
        case .library: self = .library
        case .addons, .settings: self = .more
        }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .search: return "Suche"
        case .library: return "Bibliothek"
        case .more: return "Mehr"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .search: return "magnifyingglass"
        case .library: return "square.stack"
        case .more: return "ellipsis"
        }
    }

    /// Der Bereich, den ein Tipp auf den Punkt öffnet.
    var root: AppSection {
        switch self {
        case .home: return .home
        case .search: return .search
        case .library: return .library
        case .more: return .settings
        }
    }

    /// Die Auswahl oben auf der Seite, wenn der Punkt mehrere Bereiche bündelt.
    var segments: [(AppSection, String)] {
        switch self {
        case .home: return [(.home, "ALLE"), (.movies, "FILME"), (.series, "SERIEN")]
        case .more: return [(.settings, "EINSTELLUNGEN"), (.addons, "ADDONS")]
        case .search, .library: return []
        }
    }
}

/// Seitenleiste links auf Fernseher, iPad und Mac. Auf schmalen Geräten eine Leiste unten.
struct MainView: View {
    @State private var section: AppSection = .home
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width >= 700 {
                HStack(spacing: 0) {
                    if !model.isPlayerActive {
                        Sidebar(section: $section)
                            .frame(width: Signal.pt(280) + 40)
                            .transition(.move(edge: .leading))
                    }
                    content(compact: false)
                }
                .animation(Signal.Motion.sheet, value: model.isPlayerActive)
            } else {
                VStack(spacing: 0) {
                    content(compact: true)
                    if !model.isPlayerActive {
                        BottomBar(section: $section)
                    }
                }
            }
        }
    }

    private func content(compact: Bool) -> some View {
        let segments = compact ? CompactTab(section).segments : []
        return NavigationStack {
            VStack(spacing: 0) {
                if !segments.isEmpty {
                    SignalSegments(segments, selection: $section)
                        .padding(.horizontal, PageInsets.horizontal)
                        .padding(.top, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                switch section {
                case .home: HomeView(type: nil)
                case .movies: HomeView(type: "movie")
                case .series: HomeView(type: "series")
                case .library: LibraryView()
                case .search: SearchView()
                case .addons: AddonsView()
                case .settings: SettingsView()
                }
            }
            .background(Signal.Palette.background)
            .framesDestinations()
        }
        // Jeder Bereich bekommt seinen eigenen Verlauf.
        .id(section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Signal.Palette.background)
        #if os(tvOS) || os(macOS)
        .focusSection()
        #endif
    }
}

private struct Sidebar: View {
    @Binding var section: AppSection
    @FocusState private var focused: AppSection?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FramesWordmark(size: 32)
                .padding(.horizontal, Signal.pt(32))
                .padding(.top, Signal.pt(56))
                .padding(.bottom, Signal.pt(44))
            ForEach(AppSection.allCases.filter { !$0.isSystem }) { item in
                row(item)
            }
            Rectangle()
                .fill(Signal.Palette.line)
                .frame(height: 1)
                .padding(.horizontal, Signal.pt(32))
                .padding(.vertical, Signal.pt(20))
            ForEach(AppSection.allCases.filter(\.isSystem)) { item in
                row(item)
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Signal.Palette.sidebar.ignoresSafeArea())
        .overlay(alignment: .trailing) {
            Rectangle().fill(Signal.Palette.line).frame(width: 1).ignoresSafeArea()
        }
        #if os(tvOS) || os(macOS)
        .focusSection()
        #endif
        #if os(tvOS)
        // Wer in die Seitenleiste wechselt, landet auf dem Bereich, in dem er gerade ist, nicht auf „Home“.
        .defaultFocus($focused, section)
        #endif
    }

    private func row(_ item: AppSection) -> some View {
        Button {
            withAnimation(Signal.Motion.sheet) { section = item }
        } label: {
            Text(item.title)
        }
        .buttonStyle(SidebarItemStyle(isSelected: item == section))
        .focused($focused, equals: item)
    }
}

private struct SidebarItemStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Item(isSelected: isSelected, configuration: configuration)
    }

    private struct Item: View {
        let isSelected: Bool
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var isFocused
        @State private var isHovered = false

        var body: some View {
            let active = isFocused || isHovered
            configuration.label
                .font(.signal(23, isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected || active ? Color.white : Signal.Palette.textMuted)
                .padding(.horizontal, Signal.pt(28))
                .frame(maxWidth: .infinity, minHeight: max(36, Signal.pt(60)), alignment: .leading)
                .background(isSelected || active ? Signal.Palette.panelActive : Color.clear)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Signal.Palette.lime)
                        .frame(width: 4)
                        .opacity(isSelected ? 1 : 0)
                }
                .shadow(color: Signal.Palette.lime.opacity(active ? 0.3 : 0), radius: active ? 18 : 0)
                .contentShape(Rectangle())
                .animation(Signal.Motion.focus, value: active)
                .animation(Signal.Motion.focus, value: isSelected)
                .trackHover($isHovered)
        }
    }
}

private struct BottomBar: View {
    @Binding var section: AppSection

    var body: some View {
        let current = CompactTab(section)
        HStack(spacing: 0) {
            ForEach(CompactTab.allCases) { tab in
                Button {
                    if tab != current { section = tab.root }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 20, weight: .medium))
                            .frame(height: 24)
                        Text(tab.title)
                            .font(.signal(18, tab == current ? .semibold : .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(tab == current ? Signal.Palette.lime : Signal.Palette.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Signal.Palette.lime)
                            .frame(width: 28, height: 3)
                            .opacity(tab == current ? 1 : 0)
                            .offset(y: -7)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(.top, 7)
        .background(Signal.Palette.sidebar.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Signal.Palette.line).frame(height: 1) }
    }
}
#endif
