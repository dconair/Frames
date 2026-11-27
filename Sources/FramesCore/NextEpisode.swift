import Foundation

extension Meta {
    public func video(id: String) -> Video? {
        videos.first { $0.id == id }
    }

    /// Die Folge nach dieser, über Staffelgrenzen hinweg. Specials folgen nur auf Specials,
    /// noch nicht erschienene Folgen zählen nicht.
    public func episode(after videoId: String, now: Date = Date()) -> Video? {
        guard let current = video(id: videoId), let season = current.season else { return nil }
        let order = videos
            .filter { ($0.season == 0) == (season == 0) && $0.season != nil }
            .sorted { ($0.season ?? 0, $0.episode ?? 0) < ($1.season ?? 0, $1.episode ?? 0) }
        guard let index = order.firstIndex(where: { $0.id == current.id }) else { return nil }
        return order.dropFirst(index + 1).first { video in
            guard let released = video.released else { return true }
            return released <= now
        }
    }
}

/// Merkmale der Quelle, die gerade läuft. Daran wird für die nächste Folge eine passende gesucht.
public struct StreamOrigin: Sendable, Hashable {
    public var addonName: String
    public var bingeGroup: String?
    public var resolution: StreamInfo.Resolution?
    public var service: StreamInfo.Service?

    public init(addonName: String, bingeGroup: String?, resolution: StreamInfo.Resolution?, service: StreamInfo.Service?) {
        self.addonName = addonName
        self.bingeGroup = bingeGroup
        self.resolution = resolution
        self.service = service
    }

    public init(_ item: SourcedStream) {
        self.init(
            addonName: item.addonName, bingeGroup: item.stream.bingeGroup,
            resolution: item.info.resolution, service: item.info.service
        )
    }
}

extension StreamRanker {
    /// Die Quelle für die nächste Folge, ohne dass man wählen muss.
    ///
    /// Zuerst dieselbe `bingeGroup` wie bisher: so kennzeichnen Addons Dateien aus derselben Reihe
    /// (gleiche Gruppe, gleiche Auflösung, gleicher Ton). Danach dasselbe Addon mit derselben Auflösung
    /// und demselben Dienst, dann dasselbe Addon, sonst die beste Quelle nach den eigenen Einstellungen und Filtern.
    public static func continuation(
        _ streams: [SourcedStream], after origin: StreamOrigin?, preferences: PlaybackSettings = .init()
    ) -> SourcedStream? {
        let ranked = ranked(streams, preferences: preferences)
        guard !ranked.isEmpty else { return nil }
        guard let origin else { return preferred(ranked, preferences) }
        if let group = origin.bingeGroup, let match = ranked.first(where: { $0.stream.bingeGroup == group }) {
            return match
        }
        let sameAddon = ranked.filter { $0.addonName == origin.addonName }
        if let match = sameAddon.first(where: { $0.info.resolution == origin.resolution && $0.info.service == origin.service }) {
            return match
        }
        if let match = sameAddon.first(where: { $0.info.resolution == origin.resolution }) ?? sameAddon.first {
            return match
        }
        return preferred(ranked, preferences)
    }

    private static func preferred(_ ranked: [SourcedStream], _ preferences: PlaybackSettings) -> SourcedStream? {
        preferences.streamFilter.apply(to: ranked).first ?? ranked.first
    }
}
