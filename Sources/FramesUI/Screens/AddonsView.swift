#if canImport(SwiftUI)
import SwiftUI
import FramesCore

/// Die im Stremio-Konto installierten Addons. Frames zeigt sie an und ändert nichts daran.
struct AddonsView: View {
    @Environment(AppModel.self) private var model

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
            }
            .padding(.horizontal, PageInsets.horizontal)
            .padding(.top, PageInsets.top)
            .padding(.bottom, Signal.pt(80))
        }
        .scrollIndicators(.hidden)
        .signalPage()
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
        if addon.isReachable { return ("AKTIV", Signal.Palette.lime) }
        return ("NICHT ERREICHBAR", Signal.Palette.textMuted)
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
