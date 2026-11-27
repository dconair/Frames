#if canImport(SwiftUI)
import SwiftUI
import FramesCore

// SwiftUI kennt selbst einen Typ dieses Namens. In der App ist immer der Bibliothekseintrag gemeint.
public typealias LibraryItem = FramesCore.LibraryItem

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

/// Was abgespielt wird: der Titel und bei Serien die Folge. Reist von der Detailseite bis in den Player,
/// damit der Wiedergabestand dem richtigen Eintrag im Konto zugeordnet wird.
struct PlaybackItem: Hashable {
    var metaId: String
    var type: String
    var name: String
    var poster: String?
    /// Bei Serien die id der Folge, bei Filmen die des Titels.
    var videoId: String
    /// Zweite Zeile, etwa „S03 E01 · Titel der Folge“ oder das Jahr.
    var subtitle: String?
    /// Laufzeit in Minuten, wenn das Addon sie nennt. Daraus schätzt die Quellenliste die Bitrate.
    var runtimeMinutes: Int? = nil
    /// Erscheinungsjahr und Besetzung laut Addon. Damit findet das X-Ray im Player Soundtrack und Fotos.
    var year: Int? = nil
    var cast: [String] = []
}

struct StreamsRoute: Hashable {
    var item: PlaybackItem
}

struct PlayerRoute: Hashable {
    var url: URL
    var headers: [String: String]
    var item: PlaybackItem
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
