#if canImport(SwiftUI)
import SwiftUI
import FramesCore
#if canImport(CoreImage)
import CoreImage
import CoreImage.CIFilterBuiltins
#endif

/// Das X-Ray im Player: Besetzung mit Fotos und Rollen, darunter die Musik mit dem Weg zu Spotify.
struct XRayPanel: View {
    let model: XRayModel
    let title: String
    let onClose: () -> Void

    enum Tab: Hashable {
        case cast, music
    }

    @State private var tab: Tab = .cast
    @State private var qrTrack: XRayTrack?
    @Environment(\.openURL) private var openURL
    private var spotify: SpotifyAccount { SpotifyAccount.shared }

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: Signal.pt(16)) {
                SignalEyebrow("X-Ray // \(title)")
                SignalSegments(
                    [(Tab.cast, "BESETZUNG\(count(model.cast.count))"), (Tab.music, "MUSIK\(count(model.trackCount))")],
                    selection: $tab
                )
                .accessibilityIdentifier("xray-tabs")
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Signal.pt(10)) {
                        switch tab {
                        case .cast: castList
                        case .music: musicList
                        }
                    }
                    .padding(Signal.pt(10))
                }
                .scrollClipDisabled()
                .scrollIndicators(.hidden)
                Button("SCHLIESSEN", action: onClose)
                    .buttonStyle(SignalButtonStyle())
            }
            // Solange der QR-Code offen ist, gehört ihm der Fokus.
            .disabled(qrTrack != nil)
            .padding(Signal.pt(32))
            .frame(width: max(330, Signal.pt(780)))
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(Signal.Palette.sidebar.ignoresSafeArea())
            .overlay(alignment: .leading) {
                Rectangle().fill(Signal.Palette.lime).frame(width: 3).ignoresSafeArea()
            }
            .overlay {
                if let qrTrack {
                    qrCard(qrTrack).transition(.opacity)
                }
            }
            #if os(tvOS) || os(macOS)
            .focusSection()
            #endif
        }
        .animation(Signal.Motion.focus, value: qrTrack)
    }

    private func count(_ value: Int) -> String {
        value > 0 ? "  \(value)" : ""
    }

    // MARK: Besetzung

    @ViewBuilder
    private var castList: some View {
        if model.castPhase != .loaded {
            SignalNotice("Lädt Besetzung", isLoading: true)
        } else if model.cast.isEmpty {
            SignalNotice("Keine Besetzung", detail: "Zu diesem Titel gibt es keine Angaben.")
        } else {
            ForEach(model.cast) { person in
                PersonRow(person: person)
            }
            Text("BESETZUNG: TVMAZE.COM · CC BY-SA")
                .font(.signalMono(13))
                .foregroundStyle(Signal.Palette.textMuted)
                .padding(.top, Signal.pt(10))
        }
    }

    // MARK: Musik

    @ViewBuilder
    private var musicList: some View {
        if model.musicPhase != .loaded {
            SignalNotice("Sucht Soundtrack", isLoading: true)
        } else if model.soundtracks.isEmpty {
            SignalNotice("Kein Soundtrack gefunden", detail: "MusicBrainz kennt zu diesem Titel kein Soundtrack-Album.")
        } else {
            spotifyHint
            ForEach(model.soundtracks) { album in
                HStack(spacing: Signal.pt(10)) {
                    Text(album.title)
                        .font(.signal(22, .semibold))
                        .foregroundStyle(Signal.Palette.text)
                        .lineLimit(2)
                    if album.isScore { SignalBadge("Score", kind: .audio) }
                    if let year = album.year { SignalBadge(String(year)) }
                }
                .padding(.top, Signal.pt(14))
                ForEach(album.tracks) { track in
                    TrackRow(track: track, state: spotify.states[track.id], action: { act(on: track) })
                }
            }
            Text("SOUNDTRACK DES TITELS, NICHT DER SZENE · MUSICBRAINZ.ORG")
                .font(.signalMono(13))
                .foregroundStyle(Signal.Palette.textMuted)
                .padding(.top, Signal.pt(10))
        }
    }

    @ViewBuilder
    private var spotifyHint: some View {
        let text: String = {
            if !SpotifyAccount.supportsLogin { return "Song wählen, QR-Code mit dem Handy scannen, in Spotify öffnen." }
            if spotify.isConnected { return "Song wählen: er landet in deinen Spotify-Lieblingssongs." }
            return "Song wählen: er öffnet in Spotify. Mit Spotify verbunden (Einstellungen) landet er direkt in deinen Lieblingssongs."
        }()
        Text(text.uppercased())
            .font(.signalMono(14))
            .foregroundStyle(Signal.Palette.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func act(on track: XRayTrack) {
        if !SpotifyAccount.supportsLogin {
            qrTrack = track
        } else if spotify.isConnected {
            Task { await spotify.save(track) }
        } else {
            openURL(SpotifyClient.searchLink(title: track.title, artist: track.artist))
        }
    }

    // MARK: QR-Code für den Fernseher

    private func qrCard(_ track: XRayTrack) -> some View {
        VStack(spacing: Signal.pt(18)) {
            SignalEyebrow("Spotify // Mit dem Handy scannen")
            if let image = QRCode.image(for: SpotifyClient.searchLink(title: track.title, artist: track.artist).absoluteString) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: Signal.pt(320), height: Signal.pt(320))
                    .padding(Signal.pt(16))
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
            }
            Text(track.title)
                .font(.signal(26, .semibold))
                .foregroundStyle(Signal.Palette.text)
                .multilineTextAlignment(.center)
            Text(track.artist.uppercased())
                .font(.signalMono(16))
                .foregroundStyle(Signal.Palette.textMuted)
            Button("FERTIG") { qrTrack = nil }
                .buttonStyle(SignalButtonStyle(.primary))
        }
        .padding(Signal.pt(36))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Signal.Palette.sidebar.opacity(0.97))
        #if os(tvOS)
        .onExitCommand { qrTrack = nil }
        #endif
    }
}

// MARK: Zeilen

private struct PersonRow: View {
    let person: XRayPerson

    var body: some View {
        HStack(spacing: Signal.pt(18)) {
            Portrait(url: person.photo, name: person.name, size: max(44, Signal.pt(84)))
            VStack(alignment: .leading, spacing: Signal.pt(4)) {
                Text(person.name)
                    .font(.signal(24, .semibold))
                    .foregroundStyle(Signal.Palette.text)
                    .lineLimit(1)
                if let character = person.character {
                    Text(character.uppercased())
                        .font(.signalMono(15))
                        .foregroundStyle(Signal.Palette.textSoft)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if person.isGuest {
                SignalBadge("Gast", kind: .picture)
            }
        }
        .padding(.horizontal, Signal.pt(14))
        .padding(.vertical, Signal.pt(10))
        .frame(maxWidth: .infinity, alignment: .leading)
        .signalPanel()
        .xrayFocusable()
        .accessibilityElement(children: .combine)
    }
}

private struct TrackRow: View {
    let track: XRayTrack
    let state: SpotifyAccount.SaveState?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Signal.pt(16)) {
                VStack(alignment: .leading, spacing: Signal.pt(4)) {
                    Text(track.title)
                        .font(.signal(22, .medium))
                        .foregroundStyle(Signal.Palette.text)
                        .lineLimit(1)
                    Text([track.artist, track.durationLabel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ").uppercased())
                        .font(.signalMono(14))
                        .foregroundStyle(Signal.Palette.textMuted)
                        .lineLimit(1)
                    if case .failed(let message) = state {
                        Text(message)
                            .font(.signal(16))
                            .foregroundStyle(Signal.Palette.danger)
                    }
                }
                Spacer(minLength: 0)
                status
            }
            .padding(.horizontal, Signal.pt(16))
            .padding(.vertical, Signal.pt(12))
            .frame(maxWidth: .infinity, minHeight: max(44, Signal.pt(72)), alignment: .leading)
            .signalPanel(active: state == .saved)
        }
        .buttonStyle(SignalCardButtonStyle(radius: 8, grows: false))
        .disabled(state == .saving || state == .saved)
    }

    @ViewBuilder
    private var status: some View {
        switch state {
        case .saving:
            ProgressView().tint(Signal.Palette.lime)
        case .saved:
            SignalBadge("✓ Gespeichert", kind: .resolution)
        case .notFound:
            SignalBadge("Nicht bei Spotify")
        default:
            SignalBadge(label, kind: .audio)
        }
    }

    private var label: String {
        if !SpotifyAccount.supportsLogin { return "QR · Spotify" }
        return SpotifyAccount.shared.isConnected ? "+ Spotify" : "↗ Spotify"
    }
}

/// Rundes Foto mit Initialen, solange keins da ist.
struct Portrait: View {
    let url: URL?
    let name: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Signal.Palette.panelActive)
            Text(initials)
                .font(.signalMono(size * 0.32 / Signal.scale, .bold))
                .foregroundStyle(Signal.Palette.textMuted)
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().stroke(Signal.Palette.border, lineWidth: 1) }
    }

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

extension View {
    /// Auf dem Fernseher muss jede Zeile den Fokus nehmen können, sonst lässt sich die Liste nicht rollen.
    @ViewBuilder
    func xrayFocusable() -> some View {
        #if os(tvOS)
        XRayFocusWrapper { self }
        #else
        self
        #endif
    }
}

#if os(tvOS)
private struct XRayFocusWrapper<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @FocusState private var focused: Bool

    var body: some View {
        content()
            .signalFocusRing(focused, radius: 8)
            .focusable()
            .focused($focused)
    }
}
#endif

// MARK: Vorschau beim Pausieren

/// Kleine Leiste über der Zeitleiste, solange pausiert ist: die ersten Gesichter und wie viel Musik es gibt.
struct XRayTeaser: View {
    let model: XRayModel

    var body: some View {
        if model.castPhase == .loaded, !model.cast.isEmpty {
            VStack(alignment: .leading, spacing: Signal.pt(12)) {
                SignalEyebrow(teaserTitle)
                HStack(alignment: .top, spacing: Signal.pt(18)) {
                    ForEach(model.cast.prefix(5)) { person in
                        VStack(spacing: Signal.pt(8)) {
                            Portrait(url: person.photo, name: person.name, size: max(40, Signal.pt(88)))
                            Text(person.name)
                                .font(.signal(16, .medium))
                                .foregroundStyle(Signal.Palette.text)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            if let character = person.character {
                                Text(character.uppercased())
                                    .font(.signalMono(12))
                                    .foregroundStyle(Signal.Palette.textMuted)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: max(64, Signal.pt(140)))
                    }
                }
            }
            .padding(Signal.pt(18))
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityIdentifier("xray-teaser")
        }
    }

    private var teaserTitle: String {
        let music = model.trackCount > 0 ? " · \(model.trackCount) Songs" : ""
        return "X-Ray // \(model.cast.count) Personen\(music)"
    }
}

// MARK: QR-Code

enum QRCode {
    static func image(for text: String) -> CGImage? {
        #if canImport(CoreImage)
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
        #else
        return nil
        #endif
    }
}
#endif
