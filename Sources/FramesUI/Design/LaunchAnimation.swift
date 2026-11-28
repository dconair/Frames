#if canImport(SwiftUI)
import SwiftUI
import FramesCore

/// Start-Animation. Es gibt acht davon, `LaunchStyle` nennt sie. Alle enden beim Logo „Einzelbilder“ mit der Wortmarke.
/// Jede läuft als Folge von Schritten: Ein Schritt setzt den Zustand, SwiftUI blendet dazwischen über.
public struct LaunchAnimation: View {
    public let style: LaunchStyle

    @State private var step = 0

    public init(style: LaunchStyle = .stapel) {
        self.style = style
    }

    public var body: some View {
        ZStack {
            Signal.Palette.background.ignoresSafeArea()
            scene
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Frames")
        .task { await run() }
    }

    // MARK: Ablauf

    /// Pause vor jedem Schritt in Millisekunden. Schritt 1 folgt nach der ersten Zahl.
    private var delays: [Int] {
        switch style {
        case .stapel: return [200, 260, 260, 260]
        case .filmstreifen: return [150, 170, 170, 520, 330]
        case .auffaechern: return [250, 300, 300, 70, 70, 70, 70, 70, 70, 700]
        case .zeichnen: return [150, 450, 450, 450]
        case .blitz: return [250, 300, 450, 260]
        case .abtaster: return [250, 150, 1000]
        case .countdown: return [250, 480, 480, 480, 300]
        case .huepfer: return [200, 600, 200, 200]
        }
    }

    private func animation(for step: Int) -> Animation {
        switch style {
        case .huepfer:
            return step == 1
                ? .interpolatingSpring(stiffness: 140, damping: 9)
                : (step == 4 ? Signal.Motion.sheet : .spring(response: 0.35, dampingFraction: 0.55))
        case .blitz:
            return step == 1 ? .easeIn(duration: 0.2) : (step == 2 ? .easeOut(duration: 0.5) : Signal.Motion.sheet)
        case .abtaster:
            return step == 2 ? .linear(duration: 0.9) : .easeOut(duration: 0.4)
        case .zeichnen:
            return step <= 2 ? .easeInOut(duration: 0.42) : Signal.Motion.sheet
        case .filmstreifen:
            return step == 4 ? .spring(response: 0.5, dampingFraction: 0.78) : Signal.Motion.sheet
        case .countdown:
            return .spring(response: 0.3, dampingFraction: 0.7)
        case .stapel, .auffaechern:
            return Signal.Motion.sheet
        }
    }

    @MainActor
    private func run() async {
        for (index, delay) in delays.enumerated() {
            try? await Task.sleep(for: .milliseconds(delay))
            let next = index + 1
            withAnimation(animation(for: next)) { step = next }
        }
    }

    // MARK: Szene

    @ViewBuilder
    private var scene: some View {
        switch style {
        case .zeichnen:
            HStack(spacing: 24) {
                FrameMark(pieces: pieces)
                    .frame(width: 104, height: 96)
                wordmark(size: 40)
            }
        case .abtaster:
            scanScene
        case .countdown:
            countdownScene
        case .auffaechern:
            VStack(spacing: 30) {
                FrameMark(pieces: pieces)
                    .frame(width: 156, height: 144)
                typedWordmark
            }
        default:
            VStack(spacing: 30) {
                FrameMark(pieces: pieces)
                    .frame(width: 156, height: 144)
                wordmark(size: 44)
            }
        }
    }

    private func wordmark(size: CGFloat) -> some View {
        let shown = wordmarkShown
        return Text("frames")
            .font(SignalFonts.make(family: "Space Grotesk", size: size, weight: .bold))
            .tracking(-size * 0.03)
            .foregroundStyle(Signal.Palette.text)
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
    }

    private var wordmarkShown: Bool {
        switch style {
        case .stapel, .blitz, .huepfer: return step >= 4
        case .filmstreifen: return step >= 5
        case .zeichnen: return step >= 4
        case .abtaster: return step >= 1
        case .countdown: return step >= 5
        case .auffaechern: return true
        }
    }

    /// Die Wortmarke Buchstabe für Buchstabe, hinten ein blinkender Cursor in Limette.
    private var typedWordmark: some View {
        let letters = max(0, min(6, step - 3))
        let text = String("frames".prefix(letters))
        let cursorVisible = step >= 3 && step < 10
        return HStack(spacing: 4) {
            Text(text)
                .font(SignalFonts.make(family: "Space Grotesk", size: 44, weight: .bold))
                .tracking(-1.3)
                .foregroundStyle(Signal.Palette.text)
            Rectangle()
                .fill(Signal.Palette.lime)
                .frame(width: 8, height: 38)
                .opacity(cursorVisible ? 1 : 0)
        }
        .frame(height: 56)
        .frame(minWidth: 190, alignment: .leading)
    }

    private var scanScene: some View {
        let progress: CGFloat = step >= 2 ? 1 : 0
        let height: CGFloat = 250
        return ZStack(alignment: .top) {
            VStack(spacing: 30) {
                FrameMark(pieces: MarkPiece.stack)
                    .frame(width: 156, height: 144)
                wordmark(size: 44)
            }
            .frame(height: height)
            .mask(alignment: .top) {
                Rectangle().frame(height: height * progress)
            }
            Rectangle()
                .fill(Signal.Palette.lime)
                .frame(width: 340, height: 3)
                .shadow(color: Signal.Palette.lime.opacity(0.8), radius: 14)
                .offset(y: height * progress)
                .opacity(step >= 1 && step < 3 ? 1 : 0)
        }
        .frame(height: height, alignment: .top)
    }

    private var countdownScene: some View {
        let number = max(1, 4 - step)
        return ZStack {
            // Der Vorspann: Rahmen mit Fadenkreuz, darin die Zahl.
            ZStack {
                Rectangle().stroke(Signal.Palette.border, lineWidth: 3)
                Rectangle().fill(Signal.Palette.line).frame(width: 2).padding(.vertical, 8)
                Rectangle().fill(Signal.Palette.line).frame(height: 2).padding(.horizontal, 8)
                Text("\(number)")
                    .font(SignalFonts.make(family: "JetBrains Mono", size: 104, weight: .bold))
                    .foregroundStyle(Signal.Palette.lime)
                    .shadow(color: Signal.Palette.lime.opacity(0.5), radius: 18)
                    .id(number)
                    .transition(.scale(scale: 1.5).combined(with: .opacity))
            }
            .frame(width: 190, height: 140)
            .opacity(step >= 1 && step <= 3 ? 1 : 0)
            .scaleEffect(step >= 4 ? 0.6 : 1)

            VStack(spacing: 30) {
                FrameMark(pieces: pieces)
                    .frame(width: 156, height: 144)
                wordmark(size: 44)
            }
        }
    }

    // MARK: Zustand der Bilder

    private var pieces: [MarkPiece] {
        switch style {
        case .stapel: return stackIn(from: 1)
        case .filmstreifen: return filmstrip
        case .auffaechern: return fanOut
        case .zeichnen: return drawn
        case .blitz: return flash
        case .abtaster: return MarkPiece.stack
        case .countdown: return step >= 4 ? MarkPiece.stack : MarkPiece.hiddenAll
        case .huepfer: return bounce
        }
    }

    /// Jedes Bild startet auf dem Platz seines Vorgängers und gleitet auf seinen eigenen.
    private func stackIn(from first: Int) -> [MarkPiece] {
        (0..<3).map { index in
            var piece = MarkPiece.hidden
            if step >= first + index {
                piece = MarkPiece()
            } else {
                piece.dx = -20
                piece.dy = -24
            }
            piece.glow = index == 2 && step >= 3 ? 1 : 0
            return piece
        }
    }

    /// Drei Bilder nebeneinander, dann rücken sie zum Stapel zusammen.
    private var filmstrip: [MarkPiece] {
        let rowDX: [CGFloat] = [-35, 0, 35]
        let rowDY: [CGFloat] = [24, 0, -24]
        return (0..<3).map { index in
            var piece = MarkPiece.hidden
            if step >= 1 + index || step >= 4 {
                piece.opacity = 1
            }
            if step < 4 {
                piece.dx = rowDX[index]
                piece.dy = rowDY[index]
                piece.scale = 0.6
            }
            piece.glow = index == 2 && step >= 1 ? 1 : 0
            return piece
        }
    }

    /// Das leuchtende Bild steht zuerst allein, die beiden anderen fächern sich dahinter auf.
    private var fanOut: [MarkPiece] {
        var front = MarkPiece()
        front.glow = step >= 1 ? 1 : 0
        front.opacity = step >= 1 ? 1 : 0
        var middle = MarkPiece.hidden
        var back = MarkPiece.hidden
        if step >= 2 { middle = MarkPiece() } else { middle.dx = 20; middle.dy = 24 }
        if step >= 3 { back = MarkPiece() } else { back.dx = 40; back.dy = 48 }
        return [back, middle, front]
    }

    /// Die Rahmen werden gezeichnet, dann füllt sich das vorderste Bild.
    private var drawn: [MarkPiece] {
        var back = MarkPiece()
        back.opacity = step >= 1 ? 1 : 0
        back.trim = step >= 1 ? 1 : 0
        var middle = MarkPiece()
        middle.opacity = step >= 2 ? 1 : 0
        middle.trim = step >= 2 ? 1 : 0
        var front = MarkPiece()
        front.opacity = step >= 3 ? 1 : 0
        front.glow = step >= 3 ? 1 : 0
        front.scale = step >= 3 ? 1 : 0.8
        return [back, middle, front]
    }

    /// Das vorderste Bild bläht sich zum Blitz über den Bildschirm und zieht sich zusammen.
    private var flash: [MarkPiece] {
        var front = MarkPiece()
        switch step {
        case 0: front.opacity = 0; front.scale = 0.3
        case 1: front.scale = 42
        default: front.glow = 1
        }
        var middle = MarkPiece.hidden
        var back = MarkPiece.hidden
        if step >= 3 { middle = MarkPiece() } else { middle.dx = -20; middle.dy = -24 }
        if step >= 3 { back = MarkPiece() } else { back.dx = -40; back.dy = -48 }
        return [back, middle, front]
    }

    /// Das vorderste Bild fällt herein und federt, die anderen springen dahinter auf.
    private var bounce: [MarkPiece] {
        var front = MarkPiece.hidden
        if step >= 1 { front = MarkPiece() } else { front.dy = -320 }
        front.glow = step >= 2 ? 1 : 0
        var middle = MarkPiece.hidden
        middle.scale = 0.5
        if step >= 2 { middle = MarkPiece() }
        var back = MarkPiece.hidden
        back.scale = 0.5
        if step >= 3 { back = MarkPiece() }
        return [back, middle, front]
    }
}

/// Zustand eines der drei Bilder. Standard ist: sichtbar und an seinem Platz im Stapel.
struct MarkPiece {
    var opacity: Double = 1
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var scale: CGFloat = 1
    /// Wie weit der Rahmen gezeichnet ist. Betrifft nur die beiden hinteren Bilder.
    var trim: CGFloat = 1
    var glow: Double = 0

    static var hidden: MarkPiece {
        var piece = MarkPiece()
        piece.opacity = 0
        return piece
    }

    /// Das fertige Logo, leuchtend.
    static var stack: [MarkPiece] {
        var front = MarkPiece()
        front.glow = 1
        return [MarkPiece(), MarkPiece(), front]
    }

    static var hiddenAll: [MarkPiece] { [hidden, hidden, hidden] }
}

/// Das Logo „Einzelbilder“: drei versetzte Bilder, das vorderste in der Signalfarbe.
/// Die Bilder 0 und 1 sind Rahmen, Bild 2 ist gefüllt. Bild 0 liegt ganz hinten.
struct FrameMark: View {
    let pieces: [MarkPiece]

    var body: some View {
        GeometryReader { proxy in
            let unit = min(proxy.size.width / 130, proxy.size.height / 120)
            ZStack(alignment: .topLeading) {
                place(pieces[0], x: 6, y: 6, unit: unit) {
                    Rectangle()
                        .trim(from: 0, to: pieces[0].trim)
                        .stroke(Signal.Palette.border, lineWidth: 9 * unit)
                }
                place(pieces[1], x: 26, y: 30, unit: unit) {
                    ZStack {
                        Rectangle().fill(Signal.Palette.background)
                        Rectangle()
                            .trim(from: 0, to: pieces[1].trim)
                            .stroke(Signal.Palette.textMuted, lineWidth: 9 * unit)
                    }
                }
                place(pieces[2], x: 46, y: 54, unit: unit) {
                    Rectangle()
                        .fill(Signal.Palette.lime)
                        .shadow(color: Signal.Palette.lime.opacity(0.55 * pieces[2].glow), radius: 26)
                }
            }
            .frame(width: 130 * unit, height: 120 * unit, alignment: .topLeading)
        }
    }

    private func place<Content: View>(
        _ piece: MarkPiece, x: CGFloat, y: CGFloat, unit: CGFloat, @ViewBuilder _ content: () -> Content
    ) -> some View {
        content()
            .frame(width: 78 * unit, height: 58 * unit)
            .scaleEffect(piece.scale)
            .opacity(piece.opacity)
            .offset(x: (x + piece.dx) * unit, y: (y + piece.dy) * unit)
    }
}
#endif
