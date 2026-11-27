#if canImport(SwiftUI)
import SwiftUI
import FramesCore

/// Einstellungen: Wiedergabe mit den Skip-Intervallen, darunter Erscheinungsbild und Konto.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        @Bindable var appearance = SignalAppearance.shared
        ScrollView {
            VStack(alignment: .leading, spacing: Signal.pt(10)) {
                SignalPageHeader(eyebrow: "Einstellungen // Wiedergabe", title: "Wiedergabe")
                    .padding(.bottom, Signal.pt(24))

                SettingRow("Vorspulen", detail: "Sprung nach vorn pro Tastendruck") {
                    SignalSegments(SkipInterval.allCases.map { ($0, $0.label) }, selection: $model.settings.skipForward)
                }
                SettingRow("Zurückspulen", detail: "Sprung zurück pro Tastendruck") {
                    SignalSegments(SkipInterval.allCases.map { ($0, $0.label) }, selection: $model.settings.skipBackward)
                }
                SettingRow("Bildvorschau beim Spulen", detail: "Vorschaubild mit Zeitmarke über der Zeitleiste") {
                    SignalSegments([(true, "AN"), (false, "AUS")], selection: $model.settings.scrubPreview)
                }
                SettingRow("Intro überspringen", detail: "Wenn ein Addon Intro-Marken liefert") {
                    SignalSegments(
                        [(IntroSkipMode.showButton, "TASTE"), (IntroSkipMode.automatic, "AUTO"), (IntroSkipMode.off, "AUS")],
                        selection: $model.settings.introSkip
                    )
                }
                SettingRow("Nächste Folge", detail: "Startet nach dem Abspann") {
                    SignalSegments([(true, "AN"), (false, "AUS")], selection: $model.settings.autoplayNextEpisode)
                }
                SettingRow("Höchste Auflösung", detail: "Größere Streams rücken nach hinten") {
                    SignalSegments(
                        [(StreamInfo.Resolution.hd, "720p"), (StreamInfo.Resolution.fullHD, "1080p"), (StreamInfo.Resolution.uhd, "2160p")],
                        selection: $model.settings.maxResolution
                    )
                }
                SettingRow("Dolby Vision bevorzugen", detail: "Wird bei „Abspielen“ zuerst gewählt") {
                    SignalSegments([(true, "AN"), (false, "AUS")], selection: $model.settings.preferDolbyVision)
                }

                SignalEyebrow("Einstellungen // Erscheinungsbild")
                    .padding(.top, Signal.pt(40))
                    .padding(.bottom, Signal.pt(8))

                SettingRow("Farbthema", detail: "Farben der ganzen App") {
                    SignalSegments(SignalColorTheme.allCases.map { ($0, $0.label) }, selection: $appearance.theme)
                }
                SettingRow("Schrift", detail: "Standard oder kantig wie auf einer Konsole") {
                    SignalSegments(SignalTypeface.allCases.map { ($0, $0.label) }, selection: $appearance.typeface)
                }

                SpotifySettings()

                StartSettingsSection()

                SignalEyebrow("Einstellungen // Konto")
                    .padding(.top, Signal.pt(40))
                    .padding(.bottom, Signal.pt(8))

                SettingRow("Stremio", detail: model.session?.email ?? "Nicht angemeldet") {
                    Button("ABMELDEN") { model.logout() }
                        .buttonStyle(SignalButtonStyle())
                }
                SettingRow("Letzter Sync", detail: syncText) {
                    Button(model.isBusy ? "LÄDT" : "JETZT SYNCHRONISIEREN") {
                        Task { await model.refresh() }
                    }
                    .buttonStyle(SignalButtonStyle())
                    .disabled(model.isBusy)
                }
            }
            .padding(.horizontal, PageInsets.horizontal)
            .padding(.top, PageInsets.top)
            .padding(.bottom, Signal.pt(80))
        }
        .scrollIndicators(.hidden)
        .signalPage()
    }

    private var syncText: String {
        guard let date = model.lastSync else { return "Noch nicht synchronisiert" }
        return "\(model.library.library.count) Titel · \(date.formatted(date: .omitted, time: .shortened))"
    }
}

/// Spotify für das X-Ray: Songs aus dem Player landen in den eigenen Lieblingssongs.
private struct SpotifySettings: View {
    @State private var message: String?
    #if !os(tvOS)
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    #endif

    var body: some View {
        @Bindable var spotify = SpotifyAccount.shared
        SignalEyebrow("Einstellungen // X-Ray und Spotify")
            .padding(.top, Signal.pt(40))
            .padding(.bottom, Signal.pt(8))

        #if os(tvOS)
        SettingRow("Spotify", detail: "Im X-Ray zeigt jeder Song einen QR-Code. Scannen öffnet ihn in Spotify auf dem Handy.") {
            EmptyView()
        }
        #else
        if spotify.isConnected {
            SettingRow("Spotify", detail: "Verbunden. Ein Tipp im X-Ray legt den Song ab, Spotify bleibt zu.") {
                Button("TRENNEN") { spotify.disconnect() }
                    .buttonStyle(SignalButtonStyle())
            }
            SettingRow("Songs landen in", detail: "Die Playlist „Frames“ entsteht beim ersten Song, wie bei Shazam") {
                SignalSegments(
                    [(SpotifyDestination.playlist, "PLAYLIST FRAMES"), (SpotifyDestination.liked, "LIEBLINGSSONGS")],
                    selection: $spotify.destination
                )
            }
        } else {
            SettingRow("Spotify-Client-ID", detail: "Aus deiner App auf developer.spotify.com") {
                TextField("32 Zeichen", text: $spotify.clientId)
                    .font(.signalMono(18))
                    .foregroundStyle(Signal.Palette.text)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("spotify-client-id")
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    #if os(macOS)
                    .textFieldStyle(.plain)
                    #endif
                    .padding(.horizontal, Signal.pt(26))
                    .frame(minWidth: 240, maxWidth: 420, minHeight: max(48, Signal.pt(72)))
                    .signalPanel()
            }
            SettingRow("Mit Spotify verbinden", detail: "Redirect-URI in der Spotify-App: \(SpotifyClient.redirectURI)") {
                Button(spotify.isConnecting ? "VERBINDET" : "VERBINDEN") {
                    Task { message = await spotify.connect(using: webAuthenticationSession) }
                }
                .buttonStyle(SignalButtonStyle(.primary))
                .disabled(spotify.isConnecting || !spotify.hasValidClientId)
            }
            Text(
                "Ohne Verbindung öffnet ein Song aus dem X-Ray die Suche in Spotify. Zum Verbinden auf developer.spotify.com "
                    + "eine App anlegen (Web API), die Redirect-URI oben eintragen und die Client-ID hier einfügen. "
                    + "Spotify verlangt dafür ein Premium-Konto."
            )
            .font(.signal(18))
            .foregroundStyle(Signal.Palette.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Signal.pt(26))
        }
        if let message {
            Text(message)
                .font(.signal(18, .medium))
                .foregroundStyle(Signal.Palette.danger)
                .padding(.horizontal, Signal.pt(26))
        }
        #endif
    }
}

/// Zeile mit Titel, Erklärung in Mono und dem Bedienelement rechts. Auf schmalen Geräten darunter.
private struct SettingRow<Control: View>: View {
    private let title: String
    private let detail: String
    private let control: Control

    init(_ title: String, detail: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Signal.pt(24)) {
                labels
                Spacer(minLength: Signal.pt(24))
                control
            }
            VStack(alignment: .leading, spacing: Signal.pt(18)) {
                labels
                control
            }
        }
        .padding(.horizontal, Signal.pt(26))
        .padding(.vertical, Signal.pt(18))
        .frame(maxWidth: .infinity, minHeight: max(64, Signal.pt(96)), alignment: .leading)
        .signalPanel()
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: Signal.pt(5)) {
            Text(title)
                .font(.signal(26, .semibold))
                .foregroundStyle(Signal.Palette.text)
            Text(detail.uppercased())
                .font(.signalMono(15))
                .foregroundStyle(Signal.Palette.textMuted)
                .lineLimit(2)
        }
    }
}
#endif
