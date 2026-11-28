#if canImport(SwiftUI)
import SwiftUI
import FramesCore

/// Ziel eines Links von außen: eine Detailseite.
struct DeepLinkTarget: Identifiable, Hashable {
    var route: MetaRoute
    var id: MetaRoute { route }

    /// Versteht `frames://detail?type=movie&id=tt123`. Der Name kommt aus der Bibliothek, wenn der Titel dort liegt.
    init?(url: URL, library: [LibraryItem]) {
        guard url.scheme == TopShelfSnapshot.scheme, url.host == "detail",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let type = items.first(where: { $0.name == "type" })?.value,
              let id = items.first(where: { $0.name == "id" })?.value,
              !type.isEmpty, !id.isEmpty else { return nil }
        let name = library.first { $0.id == id }?.name ?? id
        route = MetaRoute(type: type, id: id, name: name)
    }
}

/// Zeigt die Detailseite eines Links über der ganzen App.
struct DeepLinkPresenter: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        @Bindable var model = model
        #if os(macOS)
        content.sheet(item: $model.deepLink) { target in destination(target) }
        #else
        content.fullScreenCover(item: $model.deepLink) { target in destination(target) }
        #endif
    }

    private func destination(_ target: DeepLinkTarget) -> some View {
        NavigationStack {
            DetailView(route: target.route)
                .framesDestinations()
                #if !os(tvOS)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Schließen") { model.deepLink = nil }
                    }
                }
                #endif
        }
        .background(Signal.Palette.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(Signal.Palette.lime)
        .environment(model)
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 640)
        #endif
    }
}
#endif
