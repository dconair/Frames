import SwiftUI
import FramesUI

@main
struct FramesApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 800)
        #endif
    }
}
