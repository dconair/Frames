import Foundation

/// Technische Angaben zu einem Stream, gelesen aus Name, Beschreibung und Dateiname.
/// Daraus entstehen die farbigen Badges: Auflösung, Bild, Ton.
public struct StreamInfo: Sendable, Hashable {
    public enum Resolution: Int, Sendable, Comparable, CaseIterable, Codable {
        case sd = 480, hd = 720, fullHD = 1080, uhd = 2160

        public static func < (lhs: Resolution, rhs: Resolution) -> Bool { lhs.rawValue < rhs.rawValue }
        public var label: String { "\(rawValue)p" }
    }

    public enum DynamicRange: Int, Sendable, Comparable {
        case hdr10 = 1, hdr10Plus, dolbyVision

        public static func < (lhs: DynamicRange, rhs: DynamicRange) -> Bool { lhs.rawValue < rhs.rawValue }
        public var label: String {
            switch self {
            case .hdr10: return "HDR10"
            case .hdr10Plus: return "HDR10+"
            case .dolbyVision: return "DOLBY VISION"
            }
        }
    }

    public enum Audio: Int, Sendable, Comparable {
        case aac = 1, dolbyDigital, dts, dolbyDigitalPlus, dtsHD, trueHD, atmos

        public static func < (lhs: Audio, rhs: Audio) -> Bool { lhs.rawValue < rhs.rawValue }
        public var label: String {
            switch self {
            case .aac: return "AAC"
            case .dolbyDigital: return "DD"
            case .dts: return "DTS"
            case .dolbyDigitalPlus: return "DD+"
            case .dtsHD: return "DTS-HD"
            case .trueHD: return "TRUEHD"
            case .atmos: return "ATMOS"
            }
        }
    }

    public enum Codec: String, Sendable {
        case h264 = "H.264", hevc = "HEVC", av1 = "AV1"
    }

    public var resolution: Resolution?
    public var dynamicRange: DynamicRange?
    public var audio: Audio?
    public var channels: String?
    public var codec: Codec?
    public var sizeBytes: Int64?
    /// Bei Debrid-Addons: liegt die Datei schon beim Dienst und startet sofort?
    public var isCached: Bool?

    public init(
        resolution: Resolution? = nil, dynamicRange: DynamicRange? = nil, audio: Audio? = nil,
        channels: String? = nil, codec: Codec? = nil, sizeBytes: Int64? = nil, isCached: Bool? = nil
    ) {
        self.resolution = resolution
        self.dynamicRange = dynamicRange
        self.audio = audio
        self.channels = channels
        self.codec = codec
        self.sizeBytes = sizeBytes
        self.isCached = isCached
    }

    public init(stream: Stream) {
        let text = [stream.name, stream.title, stream.filename].compactMap { $0 }.joined(separator: "\n")
        self.init(text: text)
        if let size = stream.videoSize, size > 0 { sizeBytes = size }
    }

    public init(text: String) {
        func has(_ pattern: String) -> Bool {
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }

        if has(#"\b(2160p|4k|uhd)\b"#) { resolution = .uhd }
        else if has(#"\b1080[pi]\b"#) { resolution = .fullHD }
        else if has(#"\b720p\b"#) { resolution = .hd }
        else if has(#"\b(480p|576p|dvdrip)\b"#) { resolution = .sd }

        if has(#"\b(dv|dovi|dolby[ .\-]?vision)\b"#) { dynamicRange = .dolbyVision }
        else if has(#"\bhdr10(\+|plus)"#) { dynamicRange = .hdr10Plus }
        else if has(#"\bhdr(10)?\b"#) { dynamicRange = .hdr10 }

        if has(#"\batmos\b"#) { audio = .atmos }
        else if has(#"\btrue[ \-]?hd\b"#) { audio = .trueHD }
        else if has(#"\bdts[ .\-]?(hd|ma|x)\b"#) { audio = .dtsHD }
        else if has(#"(?<![a-z0-9])(ddp|dd\+|e-?ac-?3)"#) { audio = .dolbyDigitalPlus }
        else if has(#"\bdts\b"#) { audio = .dts }
        else if has(#"(?<![a-z0-9])(dd(?![a-z+])|ac-?3)"#) { audio = .dolbyDigital }
        else if has(#"\baac"#) { audio = .aac }

        if let match = Self.groups(#"(?<![0-9])(?<![0-9]\.)([257])\.([01])(?![0-9])(?!\s?(?:gb|mb|gib|mib))"#, in: text) {
            channels = "\(match[1]).\(match[2])"
        }

        if has(#"\b(hevc|[hx][ .]?265)\b"#) { codec = .hevc }
        else if has(#"\bav1\b"#) { codec = .av1 }
        else if has(#"\b([hx][ .]?264|avc)\b"#) { codec = .h264 }

        if let match = Self.groups(#"([0-9]+(?:[.,][0-9]+)?)\s?(gb|gib|mb|mib)\b"#, in: text),
           let number = Double(match[1].replacingOccurrences(of: ",", with: ".")) {
            let unit: Double = match[2].lowercased().hasPrefix("g") ? 1_073_741_824 : 1_048_576
            sizeBytes = Int64(number * unit)
        }

        // Schreibweisen der verbreiteten Debrid-Addons: „[RD+]“ oder Blitz für vorhanden, „[RD download]“ oder Pfeil für nicht.
        if has(#"\[(rd|ad|pm|dl|tb|oc)\+\]"#) || text.contains("⚡") { isCached = true }
        else if has(#"\[(rd|ad|pm|dl|tb|oc) download\]"#) || text.contains("⬇") || text.contains("⏳") { isCached = false }
    }

    private static func groups(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }

    /// Größe als kurzer Text, etwa „58,2 GB“.
    public var sizeLabel: String? {
        guard let sizeBytes, sizeBytes > 0 else { return nil }
        let gigabytes = Double(sizeBytes) / 1_073_741_824
        let text = gigabytes >= 1
            ? String(format: "%.1f GB", gigabytes)
            : String(format: "%.0f MB", Double(sizeBytes) / 1_048_576)
        return text.replacingOccurrences(of: ".", with: ",")
    }

    public var audioLabel: String? {
        guard let audio else { return channels }
        return [audio.label, channels].compactMap { $0 }.joined(separator: " ")
    }
}

/// Ein Stream zusammen mit dem Addon, das ihn geliefert hat, und seinen technischen Angaben.
public struct SourcedStream: Sendable, Hashable, Identifiable {
    public var stream: Stream
    public var addonName: String
    public var info: StreamInfo
    public var index: Int

    public var id: String { "\(addonName)#\(index)" }

    public init(stream: Stream, addonName: String, index: Int) {
        self.stream = stream
        self.addonName = addonName
        self.index = index
        self.info = StreamInfo(stream: stream)
    }
}

public enum StreamRanker {
    /// Sortiert abspielbare Streams so, dass der gewünschte zuerst steht.
    /// Reihenfolge der Kriterien: sofort verfügbar, Auflösung bis zur Obergrenze, Bild, Ton, Größe.
    /// Nicht abspielbare Quellen (Torrents ohne Debrid, externe Seiten) fallen heraus.
    public static func ranked(_ streams: [SourcedStream], preferences: PlaybackSettings = .init()) -> [SourcedStream] {
        streams
            .filter { $0.stream.playableURL != nil }
            .sorted { score($0, preferences) > score($1, preferences) }
    }

    private static func score(_ item: SourcedStream, _ preferences: PlaybackSettings) -> [Int] {
        let info = item.info
        let cached = info.isCached == false ? 0 : 1
        // Über der Obergrenze liegende Auflösungen rutschen hinter alle passenden.
        let resolution: Int
        if let value = info.resolution {
            resolution = value <= preferences.maxResolution ? value.rawValue : -value.rawValue
        } else {
            resolution = 0
        }
        var range = info.dynamicRange?.rawValue ?? 0
        if !preferences.preferDolbyVision, info.dynamicRange == .dolbyVision { range = 0 }
        let audio = info.audio?.rawValue ?? 0
        let size = Int(clamping: (info.sizeBytes ?? 0) / 1_048_576)
        // Bei Gleichstand bleibt die Reihenfolge des Addons erhalten.
        return [cached, resolution, range, audio, size, -item.index]
    }
}

extension Array where Element == Int {
    fileprivate static func > (lhs: [Int], rhs: [Int]) -> Bool {
        for (left, right) in zip(lhs, rhs) where left != right { return left > right }
        return false
    }
}
