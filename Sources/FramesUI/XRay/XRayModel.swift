#if canImport(SwiftUI)
import SwiftUI
import FramesCore

/// Lädt Besetzung und Musik für das X-Ray, sobald der Player startet. Beides kommt unabhängig voneinander,
/// damit die Besetzung nicht auf MusicBrainz wartet, das nur eine Anfrage pro Sekunde erlaubt.
@MainActor
@Observable
final class XRayModel {
    enum Phase: Equatable {
        case idle, loading, loaded
    }

    private(set) var cast: [XRayPerson] = []
    private(set) var soundtracks: [XRaySoundtrack] = []
    private(set) var castPhase: Phase = .idle
    private(set) var musicPhase: Phase = .idle

    private let castService: CastService
    private let soundtrackService: SoundtrackService

    init(castService: CastService = CastService(), soundtrackService: SoundtrackService = SoundtrackService()) {
        self.castService = castService
        self.soundtrackService = soundtrackService
    }

    var trackCount: Int { soundtracks.reduce(0) { $0 + $1.tracks.count } }
    var isEmpty: Bool { castPhase == .loaded && musicPhase == .loaded && cast.isEmpty && soundtracks.isEmpty }

    func load(_ request: XRayRequest) async {
        guard castPhase == .idle else { return }
        castPhase = .loading
        musicPhase = .loading
        let castService = castService
        let soundtrackService = soundtrackService
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor [weak self] in
                let people = await castService.cast(for: request)
                self?.cast = people
                self?.castPhase = .loaded
            }
            group.addTask { @MainActor [weak self] in
                let albums = await soundtrackService.soundtracks(for: request)
                self?.soundtracks = albums
                self?.musicPhase = .loaded
            }
        }
    }
}

extension PlaybackItem {
    /// Was das X-Ray zu diesem Eintrag nachschlägt.
    var xrayRequest: XRayRequest {
        XRayRequest(metaId: metaId, type: type, name: name, videoId: videoId, year: year, castNames: cast)
    }
}
#endif
