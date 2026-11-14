#if canImport(SwiftUI)
import SwiftUI
import FramesCore

/// Anmeldung mit dem Stremio-Konto. Danach lädt Frames die dort installierten Addons.
struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?

    private enum Field {
        case email, password
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Signal.pt(28)) {
                FramesWordmark(size: 44)
                    .padding(.bottom, Signal.pt(24))

                VStack(alignment: .leading, spacing: Signal.pt(10)) {
                    SignalEyebrow("Schritt 01 // Anmeldung")
                    Text("Mit Stremio anmelden")
                        .font(.signal(72, .bold))
                        .tracking(-0.05 * Signal.text(72))
                        .foregroundStyle(Signal.Palette.text)
                        .minimumScaleFactor(0.5)
                        .lineLimit(2)
                    Text("Frames lädt die Addons und die Bibliothek aus deinem Konto. Mehr ist nicht einzurichten.")
                        .font(.signal(24))
                        .foregroundStyle(Signal.Palette.textSoft)
                }

                VStack(spacing: Signal.pt(14)) {
                    field {
                        TextField("E-Mail", text: $email)
                            .focused($focus, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focus = .password }
                            .autocorrectionDisabled()
                            #if !os(macOS)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            #endif
                    }
                    field {
                        SecureField("Passwort", text: $password)
                            .focused($focus, equals: .password)
                            .submitLabel(.go)
                            .onSubmit(submit)
                            #if !os(macOS)
                            .textContentType(.password)
                            #endif
                    }
                }

                if let message = model.errorMessage {
                    Text(message.uppercased())
                        .font(.signalMono(17))
                        .foregroundStyle(Signal.Palette.danger)
                        .transition(.opacity)
                }

                Button(action: submit) {
                    Text(model.isBusy ? "ANMELDUNG LÄUFT" : "ANMELDEN")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SignalButtonStyle(.primary))
                .disabled(model.isBusy)

                Text("DEIN PASSWORT GEHT NUR AN STREMIO. FRAMES SPEICHERT ALLEIN DEN SITZUNGSSCHLÜSSEL IM SCHLÜSSELBUND.")
                    .font(.signalMono(15))
                    .foregroundStyle(Signal.Palette.textMuted)
            }
            .frame(maxWidth: max(340, Signal.pt(900)), alignment: .leading)
            .padding(.horizontal, PageInsets.horizontal)
            .padding(.vertical, Signal.pt(96))
            .frame(maxWidth: .infinity)
            .animation(Signal.Motion.focus, value: model.errorMessage)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.signal(26, .medium))
            .foregroundStyle(Signal.Palette.text)
            #if os(macOS)
            .textFieldStyle(.plain)
            #endif
            #if !os(tvOS)
            .padding(.horizontal, Signal.pt(26))
            .frame(minHeight: max(48, Signal.pt(72)))
            .signalPanel()
            #endif
    }

    private func submit() {
        Task { await model.login(email: email, password: password) }
    }
}
#endif
