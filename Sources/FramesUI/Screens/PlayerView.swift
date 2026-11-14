#if canImport(SwiftUI)
import SwiftUI
import AVKit
import Combine
import FramesCore

/// Erste Fassung des Players auf Basis des Systemplayers.
///
/// Auf iPhone, iPad und Mac liegen die Skip-Tasten mit den eingestellten Intervallen über dem Bild.
/// Auf dem Fernseher übernimmt vorerst die Systemsteuerung. Der eigene Player mit Bildvorschau beim
/// Spulen und MKV-Wiedergabe über libmpv folgt als nächster Abschnitt.
struct PlayerView: View {
    let route: PlayerRoute
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var flash: String?
    @State private var failure: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }
            if let failure {
                SignalNotice("Wiedergabe nicht möglich", detail: failure)
            }
            #if !os(tvOS)
            controls
            #endif
        }
        .navigationBarBackButtonHidden()
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .task(id: route) {
            let asset = AVURLAsset(
                url: route.url,
                options: route.headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": route.headers]
            )
            let item = AVPlayerItem(asset: asset)
            let newPlayer = AVPlayer(playerItem: item)
            player = newPlayer
            newPlayer.play()
            // Meldet der Systemplayer einen Fehler, liegt es meist am Dateiformat.
            for await status in item.publisher(for: \.status).values where status == .failed {
                failure = "Der Systemplayer kann dieses Format nicht abspielen. MKV-Dateien laufen erst mit dem eigenen Player, der als Nächstes kommt."
                break
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    #if !os(tvOS)
    private var controls: some View {
        VStack {
            HStack(alignment: .top) {
                Button("‹  ZURÜCK") { dismiss() }
                    .buttonStyle(SignalButtonStyle())
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(route.title)
                        .font(.signal(28, .bold))
                    if let subtitle = route.subtitle {
                        Text(subtitle.uppercased())
                            .font(.signalMono(15))
                            .foregroundStyle(Signal.Palette.lime)
                    }
                }
                .foregroundStyle(Signal.Palette.text)
                .shadow(color: .black.opacity(0.8), radius: 8)
            }
            Spacer()
            if let flash {
                Text(flash)
                    .font(.signalMono(26, .bold))
                    .foregroundStyle(Signal.Palette.lime)
                    .shadow(color: .black.opacity(0.8), radius: 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            HStack(spacing: Signal.pt(24)) {
                Button("«  \(model.settings.skipBackward.label)") { skip(.backward) }
                Button("\(model.settings.skipForward.label)  »") { skip(.forward) }
            }
            .buttonStyle(SignalButtonStyle())
            // Lässt die Zeitleiste des Systemplayers darunter frei.
            .padding(.bottom, 72)
        }
        .padding(PageInsets.horizontal)
    }
    #endif

    private func skip(_ direction: SkipDirection) {
        guard let player else { return }
        let position = player.currentTime().seconds
        guard position.isFinite else { return }
        let total = player.currentItem?.duration.seconds
        let duration = total.flatMap { $0.isFinite ? $0 : nil }
        let target = model.settings.seekTarget(from: position, duration: duration, direction: direction)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)

        let interval = direction == .forward ? model.settings.skipForward : model.settings.skipBackward
        withAnimation(Signal.Motion.press) {
            flash = "\(direction == .forward ? "+" : "−")\(interval.label)"
        }
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(Signal.Motion.sheet) { flash = nil }
        }
    }
}
#endif
