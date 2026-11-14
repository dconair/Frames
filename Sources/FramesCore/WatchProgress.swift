import Foundation

/// Wiedergabestand eines Titels, wie Frames ihn ans Stremio-Konto meldet.
public struct WatchProgress: Sendable, Hashable {
    public var metaId: String
    public var type: String
    public var name: String
    public var poster: String?
    /// Bei Serien die id der Folge, bei Filmen die des Titels.
    public var videoId: String
    /// Sekunden.
    public var position: Double
    public var duration: Double

    public init(
        metaId: String, type: String, name: String, poster: String? = nil,
        videoId: String, position: Double, duration: Double
    ) {
        self.metaId = metaId
        self.type = type
        self.name = name
        self.poster = poster
        self.videoId = videoId
        self.position = position
        self.duration = duration
    }

    public var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, position / duration))
    }

    /// Ab hier gilt der Titel als gesehen und verschwindet aus „Weiter ansehen“.
    public static let finishedFraction = 0.95

    public var isFinished: Bool { fraction >= Self.finishedFraction }

    /// Stände aus den ersten Sekunden lohnen keinen Eintrag.
    public var isWorthSaving: Bool { duration > 0 && position.isFinite && (position >= 15 || isFinished) }
}

/// Baut den Bibliothekseintrag, der zurück ans Konto geht.
///
/// Der vorhandene Eintrag wird unverändert übernommen und nur im Wiedergabestand angepasst.
/// So gehen Felder, die Frames nicht kennt, beim Zurückschreiben nicht verloren.
public enum LibraryProgress {
    public static func dateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    public static func apply(_ progress: WatchProgress, to existing: [String: Any]?, now: Date) -> [String: Any] {
        let stamp = dateString(now)
        var item = existing ?? newTemporaryItem(for: progress, stamp: stamp)
        var state = item["state"] as? [String: Any] ?? [:]

        let sameVideo = (state["video_id"] as? String) == progress.videoId
        state["video_id"] = progress.videoId
        state["lastWatched"] = stamp
        state["duration"] = Int((progress.duration * 1000).rounded())
        if progress.isFinished {
            // Zu Ende gesehen: Stand zurücksetzen und als gesehen zählen.
            let wasFinished = sameVideo && number(state["timeOffset"]) == 0 && number(state["timesWatched"]) > 0
            state["timeOffset"] = 0
            if !wasFinished {
                state["timesWatched"] = Int(number(state["timesWatched"])) + 1
            }
            state["flaggedWatched"] = 1
        } else {
            state["timeOffset"] = Int((progress.position * 1000).rounded())
        }
        item["state"] = state
        item["_mtime"] = stamp
        return item
    }

    /// Titel, die nicht in der Bibliothek stehen, bekommen wie in Stremio einen vorübergehenden Eintrag,
    /// der nur den Wiedergabestand trägt.
    static func newTemporaryItem(for progress: WatchProgress, stamp: String) -> [String: Any] {
        var item: [String: Any] = [
            "_id": progress.metaId,
            "name": progress.name,
            "type": progress.type,
            "posterShape": "poster",
            "removed": true,
            "temp": true,
            "_ctime": stamp,
            "_mtime": stamp,
            "state": [
                "lastWatched": stamp,
                "timeWatched": 0,
                "timeOffset": 0,
                "overallTimeWatched": 0,
                "timesWatched": 0,
                "flaggedWatched": 0,
                "duration": 0,
                "video_id": progress.videoId,
                "watched": NSNull(),
                "noNotif": false,
            ] as [String: Any],
            "behaviorHints": [
                "defaultVideoId": NSNull(),
                "featuredVideoId": NSNull(),
                "hasScheduledVideos": false,
            ] as [String: Any],
        ]
        if let poster = progress.poster { item["poster"] = poster }
        return item
    }

    private static func number(_ value: Any?) -> Double {
        (value as? NSNumber)?.doubleValue ?? 0
    }
}

extension Array where Element == LibraryItem {
    /// Position in Sekunden, an der die Wiedergabe dieses Videos weitergeht. `nil`, wenn es von vorn beginnt.
    public func resumePosition(metaId: String, videoId: String) -> Double? {
        guard let item = first(where: { $0.id == metaId }),
              item.videoId == nil || item.videoId == videoId,
              let fraction = item.progress, fraction < WatchProgress.finishedFraction,
              item.timeOffset >= 15_000
        else { return nil }
        return item.timeOffset / 1000
    }
}
