#if canImport(SwiftUI)
import SwiftUI
import FramesCore

struct MetaRoute: Hashable {
    var type: String
    var id: String
    var name: String

    init(type: String, id: String, name: String) {
        self.type = type
        self.id = id
        self.name = name
    }

    init(_ meta: Meta) {
        self.init(type: meta.type, id: meta.id, name: meta.name)
    }

    init(_ item: LibraryItem) {
        self.init(type: item.type, id: item.id, name: item.name)
    }
}

struct StreamsRoute: Hashable {
    var type: String
    var streamId: String
    var title: String
    var subtitle: String?
}

struct PlayerRoute: Hashable {
    var url: URL
    var headers: [String: String]
    var title: String
    var subtitle: String?
}

extension View {
    /// Meldet die Ziele an, die jeder Bereich der App öffnen kann.
    func framesDestinations() -> some View {
        self
            .navigationDestination(for: MetaRoute.self) { DetailView(route: $0) }
            .navigationDestination(for: StreamsRoute.self) { StreamsView(route: $0) }
            .navigationDestination(for: PlayerRoute.self) { PlayerView(route: $0) }
    }

    /// Gemeinsamer Rahmen der Seiten: dunkler Grund, keine Systemleiste.
    func signalPage() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Signal.Palette.background.ignoresSafeArea())
            #if os(iOS)
            .toolbarBackground(Signal.Palette.background, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }
}

/// Abstand der Seiteninhalte zum Rand, wie im Entwurf.
enum PageInsets {
    static var horizontal: CGFloat { max(16, Signal.pt(40)) }
    static var top: CGFloat { Signal.pt(56) }
}
#endif
