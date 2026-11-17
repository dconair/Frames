import Foundation

/// Reihenfolge der Quellenliste.
public enum StreamSort: String, Codable, Sendable, CaseIterable, Identifiable {
    case recommended, bitrate, smallest, audio, release

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .recommended: return "BESTE ZUERST"
        case .bitrate: return "BITRATE"
        case .smallest: return "KLEINSTE"
        case .audio: return "TON"
        case .release: return "FASSUNG"
        }
    }
}

/// Auswahl in der Quellenliste. Innerhalb einer Gruppe genügt ein Treffer, zwischen den Gruppen müssen alle passen.
/// Eine leere Gruppe schränkt nicht ein.
public struct StreamFilter: Codable, Sendable, Hashable {
    public enum Picture: String, Codable, Sendable, CaseIterable {
        case dolbyVision, hdr, sdr

        public var label: String {
            switch self {
            case .dolbyVision: return "DOLBY VISION"
            case .hdr: return "HDR"
            case .sdr: return "SDR"
            }
        }
    }

    public enum Sound: String, Codable, Sendable, CaseIterable {
        case atmos, lossless, surround, stereo

        public var label: String {
            switch self {
            case .atmos: return "ATMOS"
            case .lossless: return "TRUEHD · DTS-HD"
            case .surround: return "DD · DTS"
            case .stereo: return "AAC"
            }
        }
    }

    public var resolutions: Set<StreamInfo.Resolution> = []
    public var pictures: Set<Picture> = []
    public var sounds: Set<Sound> = []
    public var services: Set<StreamInfo.Service> = []
    public var releases: Set<StreamInfo.Release> = []
    public var languages: Set<String> = []

    public init() {}

    // Unbekannte Werte aus einer neueren Version fallen weg, statt die gespeicherte Auswahl zu verwerfen.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        resolutions = Set(c.list("resolutions", of: StreamInfo.Resolution.self))
        pictures = Set(c.list("pictures", of: Picture.self))
        sounds = Set(c.list("sounds", of: Sound.self))
        services = Set(c.list("services", of: StreamInfo.Service.self))
        releases = Set(c.list("releases", of: StreamInfo.Release.self))
        languages = Set(c.strings("languages"))
    }

    public var isEmpty: Bool { activeCount == 0 }

    public var activeCount: Int {
        resolutions.count + pictures.count + sounds.count + services.count + releases.count + languages.count
    }

    public func matches(_ info: StreamInfo) -> Bool {
        if !resolutions.isEmpty, !(info.resolution.map(resolutions.contains) ?? false) { return false }
        if !pictures.isEmpty, !pictures.contains(Self.picture(of: info)) { return false }
        if !sounds.isEmpty, !(Self.sound(of: info).map(sounds.contains) ?? false) { return false }
        if !services.isEmpty, !(info.service.map(services.contains) ?? false) { return false }
        if !releases.isEmpty, !(info.release.map(releases.contains) ?? false) { return false }
        if !languages.isEmpty, languages.isDisjoint(with: info.languages) { return false }
        return true
    }

    public func apply(to streams: [SourcedStream]) -> [SourcedStream] {
        isEmpty ? streams : streams.filter { matches($0.info) }
    }

    /// Ohne Angabe im Namen gilt ein Stream als SDR.
    public static func picture(of info: StreamInfo) -> Picture {
        switch info.dynamicRange {
        case .dolbyVision: return .dolbyVision
        case .hdr10, .hdr10Plus: return .hdr
        case nil: return .sdr
        }
    }

    public static func sound(of info: StreamInfo) -> Sound? {
        switch info.audio {
        case .atmos: return .atmos
        case .trueHD, .dtsHD: return .lossless
        case .dolbyDigital, .dolbyDigitalPlus, .dts: return .surround
        case .aac: return .stereo
        case nil: return nil
        }
    }

    public static func languageLabel(_ code: String) -> String {
        switch code {
        case "de": return "DEUTSCH"
        case "en": return "ENGLISCH"
        case "multi": return "MULTI"
        default: return code.uppercased()
        }
    }
}

/// Was in einer Quellenliste überhaupt vorkommt. Daraus entstehen die Filter, damit keiner ins Leere führt.
public struct StreamFacets: Sendable, Hashable {
    public var resolutions: [StreamInfo.Resolution] = []
    public var pictures: [StreamFilter.Picture] = []
    public var sounds: [StreamFilter.Sound] = []
    public var services: [StreamInfo.Service] = []
    public var releases: [StreamInfo.Release] = []
    public var languages: [String] = []

    /// Die Werte der Liste, dazu die schon gewählten: eine Auswahl von einem anderen Titel muss sich abwählen lassen.
    public init(_ streams: [SourcedStream], selected: StreamFilter = .init()) {
        let infos = streams.map(\.info)
        resolutions = Set(infos.compactMap(\.resolution)).union(selected.resolutions).sorted(by: >)
        let foundPictures = Set(infos.map(StreamFilter.picture(of:))).union(selected.pictures)
        pictures = StreamFilter.Picture.allCases.filter(foundPictures.contains)
        let foundSounds = Set(infos.compactMap(StreamFilter.sound(of:))).union(selected.sounds)
        sounds = StreamFilter.Sound.allCases.filter(foundSounds.contains)
        services = Set(infos.compactMap(\.service)).union(selected.services).sorted()
        releases = Set(infos.compactMap(\.release)).union(selected.releases).sorted(by: >)
        let foundLanguages = infos.reduce(into: selected.languages) { $0.formUnion($1.languages) }
        languages = ["de", "en", "multi"].filter(foundLanguages.contains)
    }
}
