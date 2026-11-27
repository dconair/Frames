#if canImport(SwiftUI)
import SwiftUI
import FramesCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Welche Start-Animation läuft und welches App-Symbol die App trägt. Beides wählt man unter Einstellungen › Start.
/// Die Wahl bleibt über Neustarts erhalten.
@Observable
public final class StartPreferences: @unchecked Sendable {
    public static let shared = StartPreferences()

    private static let choiceKey = "frames.start.animation"
    private static let lastKey = "frames.start.last"
    private static let iconKey = "frames.start.icon"

    private var storedChoice: LaunchChoice
    private var storedIcon: AppIconChoice

    public var launchChoice: LaunchChoice {
        get { storedChoice }
        set {
            storedChoice = newValue
            UserDefaults.standard.set(newValue.storage, forKey: Self.choiceKey)
        }
    }

    public var icon: AppIconChoice { storedIcon }

    private init() {
        let defaults = UserDefaults.standard
        storedChoice = LaunchChoice(storage: defaults.string(forKey: Self.choiceKey))
        storedIcon = AppIconChoice(storage: defaults.string(forKey: Self.iconKey))
    }

    /// Die Animation dieses Starts. Wird einmal je Prozessstart gewählt und merkt sich die Wahl,
    /// damit „wechselnd“ beim nächsten Start eine andere nimmt.
    public static let styleForThisLaunch: LaunchStyle = {
        if let forced = TestHooks.launchStyle { return forced }
        let defaults = UserDefaults.standard
        let last = defaults.string(forKey: lastKey).flatMap(LaunchStyle.init(rawValue:))
        let style = LaunchPool.next(choice: shared.launchChoice, last: last)
        defaults.set(style.rawValue, forKey: lastKey)
        return style
    }()

    // MARK: App-Symbol

    /// Ob die App ihr Symbol wechseln kann. Auf dem Apple TV gibt es dafür keine Schnittstelle.
    public static var canChangeIcon: Bool {
        #if os(tvOS)
        return false
        #else
        return true
        #endif
    }

    /// Schaltet das App-Symbol um. Auf iPhone und iPad zeigt das System dazu selbst eine Meldung.
    @MainActor
    public func setIcon(_ choice: AppIconChoice) async {
        guard Self.canChangeIcon else { return }
        #if os(iOS)
        guard UIApplication.shared.supportsAlternateIcons else { return }
        do {
            try await UIApplication.shared.setAlternateIconName(choice.alternateName)
        } catch {
            return
        }
        #endif
        storedIcon = choice
        UserDefaults.standard.set(choice.rawValue, forKey: Self.iconKey)
        applyDockIcon()
    }

    /// Auf dem Mac gibt es keine alternativen Symbole im System. Die App setzt ihr Dock-Symbol stattdessen selbst,
    /// solange sie läuft.
    @MainActor
    public func applyDockIcon() {
        #if os(macOS)
        if storedIcon == .einzelbilder {
            NSApplication.shared.applicationIconImage = nil
        } else if let image = NSImage(named: storedIcon.previewAsset) {
            NSApplication.shared.applicationIconImage = image
        }
        #endif
    }
}
#endif
