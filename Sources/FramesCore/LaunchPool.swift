import Foundation

/// Eine Start-Animation. Welche beim Start läuft, entscheidet `LaunchPool`.
public enum LaunchStyle: String, CaseIterable, Sendable, Identifiable {
    /// Die drei Einzelbilder gleiten übereinander.
    case stapel
    /// Drei Bilder liegen nebeneinander und rücken zusammen.
    case filmstreifen
    /// Das leuchtende Bild zuerst, die anderen fächern sich dahinter auf, die Wortmarke wird getippt.
    case auffaechern
    /// Die Rahmen werden Strich für Strich gezeichnet.
    case zeichnen
    /// Ein Blitz füllt den Bildschirm und zieht sich zum Logo zusammen.
    case blitz
    /// Eine Abtastlinie fährt über den Bildschirm und deckt das Logo auf.
    case abtaster
    /// Ein Filmvorspann zählt von 3 herunter.
    case countdown
    /// Das leuchtende Bild fällt herein und federt nach.
    case huepfer

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .stapel: return "STAPEL"
        case .filmstreifen: return "FILMSTREIFEN"
        case .auffaechern: return "AUFFÄCHERN"
        case .zeichnen: return "ZEICHNEN"
        case .blitz: return "BLITZ"
        case .abtaster: return "ABTASTER"
        case .countdown: return "COUNTDOWN"
        case .huepfer: return "HÜPFER"
        }
    }

    /// So lange bleibt die Animation stehen, bevor die App sie ausblendet. In Millisekunden.
    public var duration: Int {
        switch self {
        case .stapel: return 2000
        case .filmstreifen: return 2400
        case .auffaechern: return 2600
        case .zeichnen: return 2400
        case .blitz: return 2000
        case .abtaster: return 2200
        case .countdown: return 2800
        case .huepfer: return 2200
        }
    }
}

/// Die Wahl unter Einstellungen › Start: jedes Mal eine andere Animation oder eine feste.
public enum LaunchChoice: Equatable, Sendable {
    case rotating
    case fixed(LaunchStyle)

    /// Der Text, unter dem die Wahl gespeichert wird.
    public var storage: String {
        switch self {
        case .rotating: return "wechselnd"
        case .fixed(let style): return style.rawValue
        }
    }

    public init(storage: String?) {
        if let storage, let style = LaunchStyle(rawValue: storage) {
            self = .fixed(style)
        } else {
            self = .rotating
        }
    }
}

public enum LaunchPool {
    /// Die Animation für diesen Start. Bei „wechselnd“ eine zufällige, aber nie dieselbe wie beim letzten Start.
    public static func next<G: RandomNumberGenerator>(
        choice: LaunchChoice, last: LaunchStyle?, using generator: inout G
    ) -> LaunchStyle {
        switch choice {
        case .fixed(let style):
            return style
        case .rotating:
            let candidates = LaunchStyle.allCases.filter { $0 != last }
            return candidates.randomElement(using: &generator) ?? .stapel
        }
    }

    public static func next(choice: LaunchChoice, last: LaunchStyle?) -> LaunchStyle {
        var generator = SystemRandomNumberGenerator()
        return next(choice: choice, last: last, using: &generator)
    }
}

/// Ein wählbares App-Symbol. Das Symbol „Einzelbilder“ ist das Standardsymbol der App.
public enum AppIconChoice: String, CaseIterable, Sendable, Identifiable {
    case einzelbilder, einzelbilderLimette, schraegstrich, sucher, balkenF, zeitleiste, kontaktbogen

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .einzelbilder: return "EINZELBILDER"
        case .einzelbilderLimette: return "EINZELBILDER LIMETTE"
        case .schraegstrich: return "SCHRÄGSTRICH"
        case .sucher: return "SUCHER"
        case .balkenF: return "BALKEN-F"
        case .zeitleiste: return "ZEITLEISTE"
        case .kontaktbogen: return "KONTAKTBOGEN"
        }
    }

    /// Das Standardsymbol hat keinen eigenen Namen im System, die anderen sind alternative Symbole.
    public var alternateName: String? {
        self == .einzelbilder ? nil : "Icon-\(rawValue)"
    }

    /// Name des Bildes in den Assets, das die App für die Vorschau und das Dock-Symbol auf dem Mac nutzt.
    public var previewAsset: String { "IconVorschau-\(rawValue)" }

    public init(storage: String?) {
        self = storage.flatMap(AppIconChoice.init(rawValue:)) ?? .einzelbilder
    }
}
