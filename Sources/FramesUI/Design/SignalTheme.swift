#if canImport(SwiftUI)
import SwiftUI
import CoreText

/// Ein Farbthema. Jedes Thema bringt Flächen, Text und die drei Farbcodes mit.
public enum SignalColorTheme: String, CaseIterable, Sendable {
    case limette, phosphor

    public var label: String {
        switch self {
        case .limette: return "LIMETTE"
        case .phosphor: return "PHOSPHOR"
        }
    }

    var colors: SignalColors {
        switch self {
        case .limette:
            return SignalColors(
                background: 0x0E1012, panelTop: 0x20252B, panelBottom: 0x121518, panelActive: 0x1C2025,
                sidebarTop: 0x191C20, sidebarBottom: 0x0F1113, line: 0x2A2F36, border: 0x4A515B,
                text: 0xE8EAED, textSoft: 0xC4CAD2, textMuted: 0xAAB2BC,
                accent: 0xC6F24E, accentTop: 0xDCFF73, accentBottom: 0xA9D62F,
                picture: 0xA895FF, sound: 0x5FE0E6
            )
        case .phosphor:
            return SignalColors(
                background: 0x090E0B, panelTop: 0x19241D, panelBottom: 0x0D1410, panelActive: 0x17211B,
                sidebarTop: 0x131B16, sidebarBottom: 0x090E0B, line: 0x223128, border: 0x3F5548,
                text: 0xE3EDE6, textSoft: 0xBDCDC3, textMuted: 0x9CAFA3,
                accent: 0x4DF29A, accentTop: 0x7CFFB8, accentBottom: 0x2BD47C,
                picture: 0xE5F06A, sound: 0x6CCBFF
            )
        }
    }
}

struct SignalColors {
    let background, panelTop, panelBottom, panelActive, sidebarTop, sidebarBottom, line, border: UInt32
    let text, textSoft, textMuted, accent, accentTop, accentBottom, picture, sound: UInt32
}

/// Ein Schriftpaar: eine Schrift für Titel und Fließtext, eine Mono für Metadaten.
public enum SignalTypeface: String, CaseIterable, Sendable {
    /// Space Grotesk und JetBrains Mono.
    case standard
    /// Chakra Petch und Azeret Mono.
    case konsole

    public var label: String {
        switch self {
        case .standard: return "STANDARD"
        case .konsole: return "KONSOLE"
        }
    }
}

/// Das gewählte Erscheinungsbild. Views, die Farben oder Schriften aus `Signal` lesen,
/// zeichnen sich bei einer Änderung von selbst neu. Die Wahl bleibt über Neustarts erhalten.
@Observable
public final class SignalAppearance: @unchecked Sendable {
    public static let shared = SignalAppearance()

    private static let themeKey = "frames.appearance.theme"
    private static let typefaceKey = "frames.appearance.typeface"

    private var storedTheme: SignalColorTheme
    private var storedTypeface: SignalTypeface

    public var theme: SignalColorTheme {
        get { storedTheme }
        set {
            storedTheme = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.themeKey)
        }
    }

    public var typeface: SignalTypeface {
        get { storedTypeface }
        set {
            storedTypeface = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.typefaceKey)
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        storedTheme = defaults.string(forKey: Self.themeKey).flatMap(SignalColorTheme.init(rawValue:)) ?? .limette
        storedTypeface = defaults.string(forKey: Self.typefaceKey).flatMap(SignalTypeface.init(rawValue:)) ?? .standard
    }
}

/// Das Signal-Design: dunkle Flächen, eine Signalfarbe, Mono für Metadaten, weiche Bewegung.
/// Farben und Schriften folgen dem gewählten Erscheinungsbild.
public enum Signal {
    public enum Palette {
        private static var colors: SignalColors { SignalAppearance.shared.theme.colors }

        public static var background: Color { Color(hex: colors.background) }
        public static var panelTop: Color { Color(hex: colors.panelTop) }
        public static var panelBottom: Color { Color(hex: colors.panelBottom) }
        public static var panelActive: Color { Color(hex: colors.panelActive) }
        public static var sidebarTop: Color { Color(hex: colors.sidebarTop) }
        public static var sidebarBottom: Color { Color(hex: colors.sidebarBottom) }
        public static var line: Color { Color(hex: colors.line) }
        public static var border: Color { Color(hex: colors.border) }
        public static var text: Color { Color(hex: colors.text) }
        public static var textSoft: Color { Color(hex: colors.textSoft) }
        public static var textMuted: Color { Color(hex: colors.textMuted) }
        /// Signalfarbe des Themas und Farbcode für die Auflösung. Im Thema Limette ist sie limettengrün.
        public static var lime: Color { Color(hex: colors.accent) }
        public static var limeTop: Color { Color(hex: colors.accentTop) }
        public static var limeBottom: Color { Color(hex: colors.accentBottom) }
        /// Farbcode für Bildangaben wie Dolby Vision.
        public static var violet: Color { Color(hex: colors.picture) }
        /// Farbcode für Tonangaben wie Atmos.
        public static var cyan: Color { Color(hex: colors.sound) }
        public static let danger = Color(hex: 0xFF7A66)

        public static var panel: LinearGradient { LinearGradient(colors: [panelTop, panelBottom], startPoint: .top, endPoint: .bottom) }
        public static var sidebar: LinearGradient { LinearGradient(colors: [sidebarTop, sidebarBottom], startPoint: .top, endPoint: .bottom) }
        public static var limeFill: LinearGradient { LinearGradient(colors: [limeTop, limeBottom], startPoint: .top, endPoint: .bottom) }
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
        let files = [
            "SpaceGrotesk", "JetBrainsMono", "AzeretMono",
            "ChakraPetch-Regular", "ChakraPetch-Medium", "ChakraPetch-SemiBold", "ChakraPetch-Bold",
        ]
        for name in files {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return true
    }()

    /// Meldet die mitgelieferten Schriften an. Mehrfache Aufrufe sind harmlos.
    public static func register() {
        _ = registered
    }

    /// Für variable Fonts. Die Strichstärke wird über die Achse `wght` gesetzt.
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

    /// Chakra Petch liegt als einzelne Schnitte vor, einer je Strichstärke.
    static func makeChakraPetch(size: CGFloat, weight: SignalWeight) -> Font {
        register()
        let cut: String
        switch weight {
        case .regular: cut = "Regular"
        case .medium: cut = "Medium"
        case .semibold: cut = "SemiBold"
        case .bold: cut = "Bold"
        }
        return Font(CTFontCreateWithName("ChakraPetch-\(cut)" as CFString, size, nil))
    }
}

extension Font {
    /// Schrift für Titel und Fließtext. Die Größe ist ein Maß aus dem tvOS-Entwurf.
    public static func signal(_ tvSize: CGFloat, _ weight: SignalWeight = .regular) -> Font {
        switch SignalAppearance.shared.typeface {
        case .standard:
            return SignalFonts.make(family: "Space Grotesk", size: Signal.text(tvSize), weight: weight)
        case .konsole:
            return SignalFonts.makeChakraPetch(size: Signal.text(tvSize), weight: weight)
        }
    }

    /// Mono für Metadaten, Badges und Tasten.
    public static func signalMono(_ tvSize: CGFloat, _ weight: SignalWeight = .medium) -> Font {
        switch SignalAppearance.shared.typeface {
        case .standard:
            return SignalFonts.make(family: "JetBrains Mono", size: Signal.text(tvSize), weight: weight)
        case .konsole:
            // Azeret Mono läuft breiter und wird deshalb etwas kleiner gesetzt.
            return SignalFonts.make(family: "Azeret Mono", size: (Signal.text(tvSize) * 0.93).rounded(), weight: weight)
        }
    }
}
#endif
