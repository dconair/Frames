#if canImport(SwiftUI)
import SwiftUI
import FramesCore

/// Die im Stremio-Konto installierten Addons. Neue lassen sich über ihre Adresse hinzufügen,
/// etwa das persönliche Webtor-Addon. Entfernt wird weiterhin in Stremio.
struct AddonsView: View {
    @Environment(AppModel.self) private var model
    @State private var address = ""
    @State private var installNote: (text: String, isError: Bool)?
    @State private var isInstalling = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Signal.pt(32)) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: Signal.pt(24)) {
                        SignalPageHeader(eyebrow: "Synchron mit deinem Stremio-Konto", title: "Addons")
                        reload
                    }
                    VStack(alignment: .leading, spacing: Signal.pt(24)) {
                        SignalPageHeader(eyebrow: "Synchron mit deinem Stremio-Konto", title: "Addons")
                        reload
                    }
                }

                VStack(alignment: .leading, spacing: Signal.pt(10)) {
                    HStack(spacing: Signal.pt(20)) {
                        Text("INSTALLIERT")
                            .font(.signalMono(17, .bold))
                            .tracking(1.2)
                            .foregroundStyle(Signal.Palette.text)
                        Rectangle().fill(Signal.Palette.line).frame(height: 1)
                        Text(String(format: "%02d", model.addons.count))
                            .font(.signalMono(17))
                            .foregroundStyle(Signal.Palette.textMuted)
                    }
                    .padding(.bottom, Signal.pt(6))

                    if model.addons.isEmpty {
                        SignalNotice(
                            model.isBusy ? "Addons werden geladen" : "Keine Addons",
                            detail: model.isBusy ? nil : (model.errorMessage ?? "Installiere Addons in Stremio, dann erscheinen sie hier."),
                            isLoading: model.isBusy
                        )
                    }
                    ForEach(model.addons) { addon in
                        AddonRow(addon: addon)
                    }
                }

                if let message = model.errorMessage, !model.addons.isEmpty {
                    Text(message.uppercased())
                        .font(.signalMono(15))
                        .foregroundStyle(Signal.Palette.danger)
                }

                install
            }
            .padding(.horizontal, PageInsets.horizontal)
            .padding(.top, PageInsets.top)
            .padding(.bottom, Signal.pt(80))
        }
        .scrollIndicators(.hidden)
        .signalPage()
    }

    /// Addon über seine Adresse ins Konto holen. Bei Webtor ist die Adresse zugleich die Anmeldung.
    private var install: some View {
        VStack(alignment: .leading, spacing: Signal.pt(14)) {
            HStack(spacing: Signal.pt(20)) {
                Text("ADDON HINZUFÜGEN")
                    .font(.signalMono(17, .bold))
                    .tracking(1.2)
                    .foregroundStyle(Signal.Palette.text)
                Rectangle().fill(Signal.Palette.line).frame(height: 1)
            }
            Text("Füge die Adresse des Addons ein. Für Webtor: auf webtor.io anmelden, im Profil unter Stremio "
                + "„Generate addon URL“ wählen und die Adresse hierher kopieren. Sie gilt nur für dein Konto, "
                + "also behandle sie wie ein Passwort. Das Addon landet in deinem Stremio-Konto und gilt damit auf allen Geräten.")
                .font(.signal(21))
                .foregroundStyle(Signal.Palette.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Signal.pt(14)) {
                    addressField
                    installButton
                }
                VStack(alignment: .leading, spacing: Signal.pt(14)) {
                    addressField
                    installButton
                }
            }
            if let installNote {
                Text(installNote.text.uppercased())
                    .font(.signalMono(15))
                    .foregroundStyle(installNote.isError ? Signal.Palette.danger : Signal.Palette.lime)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("addon-meldung")
            }
        }
    }

    private var addressField: some View {
        TextField("https://…/manifest.json", text: $address)
            .font(.signalMono(18))
            .foregroundStyle(Signal.Palette.text)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit(submit)
            .accessibilityIdentifier("addon-adresse")
            #if !os(macOS)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            #endif
            #if os(macOS)
            .textFieldStyle(.plain)
            #endif
            #if !os(tvOS)
            .padding(.horizontal, Signal.pt(26))
            .frame(minWidth: 220, minHeight: max(48, Signal.pt(72)))
            .signalPanel()
            #endif
    }

    private var installButton: some View {
        Button(isInstalling ? "WIRD GEPRÜFT" : "HINZUFÜGEN", action: submit)
            .buttonStyle(SignalButtonStyle(.primary))
            .disabled(isInstalling || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func submit() {
        guard !isInstalling else { return }
        isInstalling = true
        installNote = nil
        Task {
            switch await model.installAddon(address: address) {
            case .success(let name):
                address = ""
                installNote = ("\(name) ist installiert.", false)
            case .failure(let failure):
                installNote = (failure.message, true)
            }
            isInstalling = false
        }
    }

    private var reload: some View {
        Button(model.isBusy ? "LÄDT" : "NEU LADEN") {
            Task { await model.refresh() }
        }
        .buttonStyle(SignalButtonStyle())
        .disabled(model.isBusy)
    }
}

private struct AddonRow: View {
    let addon: InstalledAddon

    /// Berechnet, damit die Farben dem gewählten Farbthema folgen.
    private static var tints: [Color] {
        [
            Signal.Palette.lime, Color(hex: 0x8A7BFF), Signal.Palette.text, Color(hex: 0xE59A62),
            Color(hex: 0x17BEBB), Color(hex: 0xF2C14E), Signal.Palette.cyan,
        ]
    }

    private var initials: String {
        let words = addon.manifest.name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let letters = words.count >= 2
            ? String(words[0].prefix(1)) + String(words[1].prefix(1))
            : String(addon.manifest.name.prefix(2))
        return letters.uppercased()
    }

    private var tint: Color {
        // Feste Farbe je Addon, unabhängig von der Reihenfolge.
        let sum = addon.manifest.id.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 9973 }
        return Self.tints[sum % Self.tints.count]
    }

    private var status: (String, Color) {
        guard addon.isReachable else { return ("NICHT ERREICHBAR", Signal.Palette.textMuted) }
        // Webtor ohne persönliche Adresse und andere Addons, die noch eingerichtet werden wollen, liefern nichts.
        if addon.manifest.needsConfiguration || (Webtor.isWebtor(addon) && !Webtor.isSignedIn(addon)) {
            return ("EINRICHTUNG FEHLT", Signal.Palette.danger)
        }
        return ("AKTIV", Signal.Palette.lime)
    }

    private func label(for capability: String) -> String {
        switch capability {
        case "catalog": return "KATALOG"
        case "meta": return "META"
        case "stream": return "STREAMS"
        case "subtitles": return "UNTERTITEL"
        default: return capability.uppercased()
        }
    }

    var body: some View {
        HStack(spacing: Signal.pt(20)) {
            Text(initials)
                .font(.signalMono(20, .bold))
                .foregroundStyle(Signal.Palette.background)
                .frame(width: max(36, Signal.pt(52)), height: max(36, Signal.pt(52)))
                .background(tint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: Signal.pt(4)) {
                Text(addon.manifest.name)
                    .font(.signal(26, .semibold))
                    .foregroundStyle(Signal.Palette.text)
                    .lineLimit(1)
                Text("v\(addon.manifest.version)\(addon.isOfficial ? " · OFFIZIELL" : "")")
                    .font(.signalMono(15))
                    .foregroundStyle(Signal.Palette.textMuted)
            }
            Spacer(minLength: Signal.pt(12))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Signal.pt(8)) {
                    ForEach(addon.capabilities.filter { $0 != "addon_catalog" }, id: \.self) { capability in
                        SignalBadge(label(for: capability))
                    }
                }
                EmptyView()
            }
            HStack(spacing: Signal.pt(8)) {
                Circle().fill(status.1).frame(width: 8, height: 8)
                Text(status.0)
                    .font(.signalMono(15))
                    .foregroundStyle(status.1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, Signal.pt(24))
        .frame(maxWidth: .infinity, minHeight: max(56, Signal.pt(92)), alignment: .leading)
        .signalPanel()
    }
}
#endif
