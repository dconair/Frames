#if canImport(SwiftUI)
import SwiftUI

/// Start-Animation: Die drei Einzelbilder des Logos legen sich nacheinander versetzt übereinander,
/// das vorderste leuchtet in Limette auf, dann erscheint die Wortmarke.
public struct LaunchAnimation: View {
    /// So lange bleibt die Animation stehen, bevor die App sie ausblendet. In Millisekunden.
    public static let duration = 2000

    @State private var step = 0

    public init() {}

    public var body: some View {
        ZStack {
            Signal.Palette.background.ignoresSafeArea()
            VStack(spacing: 30) {
                LaunchMark(step: step)
                    .frame(width: 156, height: 144)
                Text("frames")
                    .font(SignalFonts.make(family: "Space Grotesk", size: 44, weight: .bold))
                    .tracking(-1.3)
                    .foregroundStyle(Signal.Palette.text)
                    .opacity(step >= 4 ? 1 : 0)
                    .offset(y: step >= 4 ? 0 : 14)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Frames")
        .task {
            for next in 1...4 {
                try? await Task.sleep(for: .milliseconds(next == 1 ? 200 : 260))
                withAnimation(Signal.Motion.sheet) { step = next }
            }
        }
    }
}

private struct LaunchMark: View {
    let step: Int

    var body: some View {
        GeometryReader { proxy in
            let unit = min(proxy.size.width / 130, proxy.size.height / 120)
            ZStack(alignment: .topLeading) {
                piece(1, x: 6, y: 6, unit: unit) {
                    Rectangle().stroke(Signal.Palette.border, lineWidth: 9 * unit)
                }
                piece(2, x: 26, y: 30, unit: unit) {
                    Rectangle()
                        .fill(Signal.Palette.background)
                        .overlay { Rectangle().stroke(Signal.Palette.textMuted, lineWidth: 9 * unit) }
                }
                piece(3, x: 46, y: 54, unit: unit) {
                    Rectangle()
                        .fill(Signal.Palette.lime)
                        .shadow(color: Signal.Palette.lime.opacity(step >= 3 ? 0.55 : 0), radius: 26)
                }
            }
            .frame(width: 130 * unit, height: 120 * unit, alignment: .topLeading)
        }
    }

    /// Jedes Bild startet auf dem Platz seines Vorgängers und gleitet auf seinen eigenen.
    private func piece<Content: View>(
        _ index: Int, x: CGFloat, y: CGFloat, unit: CGFloat, @ViewBuilder _ content: () -> Content
    ) -> some View {
        let shown = step >= index
        return content()
            .frame(width: 78 * unit, height: 58 * unit)
            .opacity(shown ? 1 : 0)
            .offset(x: (x - (shown ? 0 : 20)) * unit, y: (y - (shown ? 0 : 24)) * unit)
    }
}
#endif
