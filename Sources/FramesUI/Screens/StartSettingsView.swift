#if canImport(SwiftUI)
import SwiftUI
import FramesCore

/// Einstellungen › Start: die Start-Animation und das App-Symbol.
struct StartSettingsSection: View {
    @State private var preferences = StartPreferences.shared
    /// Nummer des laufenden Probelaufs. Eine neue Nummer startet die Animation von vorn.
    @State private var previewRun = 0
    @State private var previewStyle: LaunchStyle?

    var body: some View {
        VStack(alignment: .leading, spacing: Signal.pt(10)) {
            SignalEyebrow("Einstellungen // Start")
                .padding(.top, Signal.pt(40))
                .padding(.bottom, Signal.pt(8))

            animationRow
            if previewStyle != nil { previewBox }
            iconRow
        }
    }

    // MARK: Start-Animation

    private var animationRow: some View {
        VStack(alignment: .leading, spacing: Signal.pt(18)) {
            VStack(alignment: .leading, spacing: Signal.pt(5)) {
                Text("Start-Animation")
                    .font(.signal(26, .semibold))
                    .foregroundStyle(Signal.Palette.text)
                Text("Wechselt bei jedem Start oder bleibt fest".uppercased())
                    .font(.signalMono(15))
                    .foregroundStyle(Signal.Palette.textMuted)
            }
            SignalFlow(spacing: Signal.pt(8)) {
                chip("WECHSELND", isOn: preferences.launchChoice == .rotating) {
                    preferences.launchChoice = .rotating
                    preview(LaunchStyle.allCases.randomElement() ?? .stapel)
                }
                ForEach(LaunchStyle.allCases) { style in
                    chip(style.label, isOn: preferences.launchChoice == .fixed(style)) {
                        preferences.launchChoice = .fixed(style)
                        preview(style)
                    }
                }
            }
        }
        .settingPanel()
    }

    private var previewBox: some View {
        ZStack {
            if let style = previewStyle {
                LaunchAnimation(style: style)
                    .id(previewRun)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Signal.pt(300))
        .clipped()
        .overlay { Rectangle().stroke(Signal.Palette.line, lineWidth: 1) }
        .overlay(alignment: .topTrailing) {
            Button("NOCH MAL") { previewRun += 1 }
                .buttonStyle(SignalChipStyle(isSelected: false))
                .padding(Signal.pt(12))
        }
    }

    private func preview(_ style: LaunchStyle) {
        previewStyle = style
        previewRun += 1
    }

    // MARK: App-Symbol

    private var iconRow: some View {
        VStack(alignment: .leading, spacing: Signal.pt(18)) {
            VStack(alignment: .leading, spacing: Signal.pt(5)) {
                Text("App-Symbol")
                    .font(.signal(26, .semibold))
                    .foregroundStyle(Signal.Palette.text)
                Text(iconDetail.uppercased())
                    .font(.signalMono(15))
                    .foregroundStyle(Signal.Palette.textMuted)
            }
            if StartPreferences.canChangeIcon {
                SignalFlow(spacing: Signal.pt(14)) {
                    ForEach(AppIconChoice.allCases) { choice in
                        iconTile(choice)
                    }
                }
            }
        }
        .settingPanel()
    }

    private var iconDetail: String {
        #if os(tvOS)
        return "Auf dem Apple TV bleibt das Symbol fest: Das System erlaubt dort keinen Wechsel"
        #elseif os(macOS)
        return "Gilt im Dock, solange Frames läuft"
        #else
        return "Das System fragt beim Wechsel kurz nach"
        #endif
    }

    private func iconTile(_ choice: AppIconChoice) -> some View {
        let isOn = preferences.icon == choice
        let side = max(56, Signal.pt(96))
        return Button {
            Task { await preferences.setIcon(choice) }
        } label: {
            VStack(spacing: Signal.pt(8)) {
                Image(choice.previewAsset)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: side * 0.225, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
                            .stroke(isOn ? Signal.Palette.lime : Signal.Palette.line, lineWidth: isOn ? 3 : 1)
                    }
                Text(choice.label)
                    .font(.signalMono(13, isOn ? .bold : .medium))
                    .foregroundStyle(isOn ? Signal.Palette.lime : Signal.Palette.textMuted)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: side + Signal.pt(24))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(SignalChipStyle(isSelected: isOn))
    }
}

private extension View {
    func settingPanel() -> some View {
        self
            .padding(.horizontal, Signal.pt(26))
            .padding(.vertical, Signal.pt(18))
            .frame(maxWidth: .infinity, alignment: .leading)
            .signalPanel()
    }
}
#endif
