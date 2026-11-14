#if canImport(SwiftUI)
import SwiftUI
import CoreText

/// Das Signal-Design: Graphit, Limette, Space Grotesk und JetBrains Mono, weiche Bewegung.
/// Alle Werte stammen aus den abgenommenen Entwürfen.
public enum Signal {
    public enum Palette {
        public static let background = Color(hex: 0x0E1012)
        public static let panelTop = Color(hex: 0x20252B)
        public static let panelBottom = Color(hex: 0x121518)
        public static let panelActive = Color(hex: 0x1C2025)
        public static let sidebarTop = Color(hex: 0x191C20)
        public static let sidebarBottom = Color(hex: 0x0F1113)
        public static let line = Color(hex: 0x2A2F36)
        public static let border = Color(hex: 0x4A515B)
        public static let text = Color(hex: 0xE8EAED)
        public static let textSoft = Color(hex: 0xC4CAD2)
        public static let textMuted = Color(hex: 0xAAB2BC)
        /// Signalfarbe und Farbcode für die Auflösung.
        public static let lime = Color(hex: 0xC6F24E)
        public static let limeTop = Color(hex: 0xDCFF73)
        public static let limeBottom = Color(hex: 0xA9D62F)
        /// Farbcode für Bildangaben wie Dolby Vision.
        public static let violet = Color(hex: 0xA895FF)
        /// Farbcode für Tonangaben wie Atmos.
        public static let cyan = Color(hex: 0x5FE0E6)
        public static let danger = Color(hex: 0xFF7A66)

        public static let panel = LinearGradient(colors: [panelTop, panelBottom], startPoint: .top, endPoint: .bottom)
        public static let sidebar = LinearGradient(colors: [sidebarTop, sidebarBottom], startPoint: .top, endPoint: .bottom)
        public static let limeFill = LinearGradient(colors: [limeTop, limeBottom], startPoint: .top, endPoint: .bottom)
    }

    /// Bewegung, Fassung B „weich“.
    public enum Motion {
        /// Fokus gleitet in 400 ms weiter.
        public static let focus = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.4)
        /// Tafeln und Seiten gleiten in 500 ms herein und blenden dabei auf.
        public static let sheet = Animation.timingCurve(0.3, 0.7, 0.2, 1, duration: 0.5)
        /// Tasten glimmen 300 ms nach.
        public static let press = Animation.easeOut(duration: 0.3)
        /// Die fokussierte Kachel wächst auf 106 %.
        public static let focusScale: CGFloat = 1.06
    }

    /// Die Entwürfe sind für den Fernseher bemaßt. Auf den anderen Geräten wird kleiner gesetzt.
    public static var scale: CGFloat {
        #if os(tvOS)
        return 1
        #elseif os(macOS)
        return 0.6
        #else
        return 0.56
        #endif
    }

    /// Rechnet ein Maß aus dem tvOS-Entwurf auf das aktuelle Gerät um.
    public static func pt(_ tvPoints: CGFloat) -> CGFloat {
        (tvPoints * scale).rounded()
    }

    /// Wie `pt`, aber mit Untergrenze, damit Text auf kleinen Geräten lesbar bleibt.
    public static func text(_ tvPoints: CGFloat) -> CGFloat {
        max(11, pt(tvPoints))
    }
}

extension Color {
    public init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

public enum SignalWeight: CGFloat, Sendable {
    case regular = 400, medium = 500, semibold = 600, bold = 700
}

public enum SignalFonts {
    private static let registered: Bool = {
        for name in ["SpaceGrotesk", "JetBrainsMono"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return true
    }()

    /// Meldet die mitgelieferten Schriften an. Mehrfache Aufrufe sind harmlos.
    public static func register() {
        _ = registered
    }

    /// Beide Schriften sind variable Fonts. Die Strichstärke wird über die Achse `wght` gesetzt.
    static func make(family: String, size: CGFloat, weight: SignalWeight) -> Font {
        register()
        let weightAxis = NSNumber(value: 0x7767_6874)
        let attributes: [CFString: Any] = [
            kCTFontFamilyNameAttribute: family,
            kCTFontVariationAttribute: [weightAxis: NSNumber(value: Double(weight.rawValue))],
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
    }
}

extension Font {
    /// Space Grotesk für Titel und Fließtext. Die Größe ist ein Maß aus dem tvOS-Entwurf.
    public static func signal(_ tvSize: CGFloat, _ weight: SignalWeight = .regular) -> Font {
        SignalFonts.make(family: "Space Grotesk", size: Signal.text(tvSize), weight: weight)
    }

    /// JetBrains Mono für Metadaten, Badges und Tasten.
    public static func signalMono(_ tvSize: CGFloat, _ weight: SignalWeight = .medium) -> Font {
        SignalFonts.make(family: "JetBrains Mono", size: Signal.text(tvSize), weight: weight)
    }
}
#endif
