#if canImport(SwiftUI)
import SwiftUI
import FramesCore

/// Einstieg der App: Anmeldung oder Hauptansicht, je nach Zustand.
public struct RootView: View {
    @State private var model: AppModel

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
                FramesWordmark(size: 64)
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
        }
        .animation(Signal.Motion.sheet, value: model.phase)
        .environment(model)
        .preferredColorScheme(.dark)
        .tint(Signal.Palette.lime)
        .task { await model.start() }
        .onChange(of: model.settings) { _, _ in model.saveSettings() }
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
                    content
                }
                .animation(Signal.Motion.sheet, value: model.isPlayerActive)
            } else {
                VStack(spacing: 0) {
                    content
                    if !model.isPlayerActive {
                        BottomBar(section: $section)
                    }
                }
            }
        }
    }

    private var content: some View {
        NavigationStack {
            Group {
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
        HStack(spacing: 0) {
            ForEach(AppSection.allCases) { item in
                Button {
                    section = item
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 18, weight: .medium))
                        Rectangle()
                            .fill(Signal.Palette.lime)
                            .frame(width: 18, height: 3)
                            .opacity(item == section ? 1 : 0)
                    }
                    .foregroundStyle(item == section ? Signal.Palette.lime : Signal.Palette.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
            }
        }
        .padding(.top, 6)
        .background(Signal.Palette.sidebar.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Signal.Palette.line).frame(height: 1) }
    }
}
#endif
