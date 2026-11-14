import Foundation

/// Eine Quelle für einen Titel, wie sie ein Addon unter `/stream` liefert.
public struct Stream: Decodable, Sendable, Hashable {
    public var url: URL?
    public var infoHash: String?
    public var ytId: String?
    public var externalUrl: URL?
    public var name: String?
    public var title: String?
    public var filename: String?
    public var videoSize: Int64?
    public var bingeGroup: String?
    public var notWebReady: Bool
    public var requestHeaders: [String: String]
    public var subtitles: [Subtitle]

    public init(
        url: URL? = nil, infoHash: String? = nil, ytId: String? = nil, externalUrl: URL? = nil,
        name: String? = nil, title: String? = nil, filename: String? = nil, videoSize: Int64? = nil,
        bingeGroup: String? = nil, notWebReady: Bool = false, requestHeaders: [String: String] = [:],
        subtitles: [Subtitle] = []
    ) {
        self.url = url
        self.infoHash = infoHash
        self.ytId = ytId
        self.externalUrl = externalUrl
        self.name = name
        self.title = title
        self.filename = filename
        self.videoSize = videoSize
        self.bingeGroup = bingeGroup
        self.notWebReady = notWebReady
        self.requestHeaders = requestHeaders
        self.subtitles = subtitles
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        url = c.string("url").flatMap(URL.init(string:))
        infoHash = c.string("infoHash")
        ytId = c.string("ytId")
        externalUrl = c.string("externalUrl").flatMap(URL.init(string:))
        name = c.string("name")
        // Neuere Addons schreiben den Beschreibungstext nach `description`, ältere nach `title`.
        title = c.string("description") ?? c.string("title")
        subtitles = c.list("subtitles")
        let hints = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("behaviorHints"))
        filename = hints?.string("filename")
        videoSize = hints?.double("videoSize").map { Int64($0) }
        bingeGroup = hints?.string("bingeGroup")
        notWebReady = hints?.bool("notWebReady") ?? false
        let proxy = try? hints?.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("proxyHeaders"))
        requestHeaders = proxy?.value("request", as: [String: String].self) ?? [:]
    }

    public var kind: StreamKind {
        if let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return .direct(url)
        }
        if infoHash != nil || url?.scheme?.lowercased() == "magnet" { return .torrent }
        if let ytId { return .youtube(ytId) }
        if let externalUrl { return .external(externalUrl) }
        return .unknown
    }

    /// Frames spielt nur direkte Links ab, also das, was Debrid-Addons liefern. Torrents laufen auf dem Gerät nicht.
    public var playableURL: URL? {
        if case .direct(let url) = kind { return url }
        return nil
    }
}

public enum StreamKind: Sendable, Hashable {
    case direct(URL)
    case torrent
    case youtube(String)
    case external(URL)
    case unknown
}

public struct Subtitle: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var url: URL
    public var lang: String

    public init(id: String, url: URL, lang: String) {
        self.id = id
        self.url = url
        self.lang = lang
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let url = c.string("url").flatMap(URL.init(string:)) else {
            throw DecodingError.keyNotFound(AnyKey("url"), .init(codingPath: c.codingPath, debugDescription: "Untertitel ohne url"))
        }
        self.url = url
        lang = c.string("lang") ?? "und"
        id = c.string("id") ?? url.absoluteString
    }
}

struct StreamsEnvelope: Decodable {
    let streams: [Stream]
    init(from decoder: Decoder) throws {
        streams = try decoder.container(keyedBy: AnyKey.self).list("streams")
    }
}

struct SubtitlesEnvelope: Decodable {
    let subtitles: [Subtitle]
    init(from decoder: Decoder) throws {
        subtitles = try decoder.container(keyedBy: AnyKey.self).list("subtitles")
    }
}
