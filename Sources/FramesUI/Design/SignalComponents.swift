#if canImport(SwiftUI)
import SwiftUI

// MARK: Logo

/// Das Zeichen „Einzelbilder“: drei versetzte Rahmen, der vorderste in Signalfarbe.
public struct FramesLogo: View {
    public init() {}

    public var body: some View {
        Canvas { context, size in
            let unit = min(size.width / 130, size.height / 120)
            func frame(_ x: CGFloat, _ y: CGFloat) -> Path {
                Path(CGRect(x: x * unit, y: y * unit, width: 78 * unit, height: 58 * unit))
            }
            context.stroke(frame(6, 6), with: .color(Signal.Palette.border), lineWidth: 9 * unit)
            context.fill(frame(26, 30), with: .color(Signal.Palette.background))
            context.stroke(frame(26, 30), with: .color(Signal.Palette.textMuted), lineWidth: 9 * unit)
            context.fill(frame(46, 54), with: .color(Signal.Palette.lime))
        }
        .aspectRatio(130.0 / 120.0, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Zeichen und Wortmarke „frames“.
public struct FramesWordmark: View {
    private let size: CGFloat

    public init(size: CGFloat = 32) {
        self.size = size
    }

    public var body: some View {
        HStack(spacing: Signal.pt(size * 0.32)) {
            FramesLogo().frame(height: Signal.text(size) * 1.06)
            Text("frames")
                .font(.signal(size, .bold))
                .tracking(-0.03 * Signal.text(size))
                .foregroundStyle(Signal.Palette.text)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Frames")
    }
}

// MARK: Flächen

private struct SignalPanel: ViewModifier {
    var active: Bool
    var radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                if active {
                    shape.fill(Signal.Palette.panelActive)
                } else {
                    shape.fill(Signal.Palette.panel)
                }
            }
            // Lichtkante oben, wie in der Farbvariante „Limette plus Farbcodes“.
            .overlay(alignment: .top) {
                shape.stroke(Color.white.opacity(0.1), lineWidth: 1)
                    .mask(alignment: .top) { Rectangle().frame(height: radius + 1) }
            }
            .overlay { shape.stroke(Signal.Palette.line, lineWidth: 1) }
    }
}

extension View {
    /// Fläche mit Verlauf, Rahmen und Lichtkante.
    public func signalPanel(active: Bool = false, radius: CGFloat = 8) -> some View {
        modifier(SignalPanel(active: active, radius: radius))
    }

    /// Fokusrahmen in Limette mit Lichtschein.
    public func signalFocusRing(_ focused: Bool, radius: CGFloat = 8, inset: CGFloat = 6) -> some View {
        self
            .overlay {
                RoundedRectangle(cornerRadius: radius + inset, style: .continuous)
                    .stroke(Signal.Palette.lime, lineWidth: 3)
                    .padding(-inset)
                    .opacity(focused ? 1 : 0)
            }
            .shadow(color: Signal.Palette.lime.opacity(focused ? 0.45 : 0), radius: focused ? 24 : 0)
    }
}

// MARK: Text

/// Kleine Zeile in Mono-Versalien über Titeln, etwa „EINSTELLUNGEN // WIEDERGABE“.
public struct SignalEyebrow: View {
    private let text: String
    private let color: Color

    public init(_ text: String, color: Color = Signal.Palette.lime) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text.uppercased())
            .font(.signalMono(17, .medium))
            .tracking(1)
            .foregroundStyle(color)
    }
}

public struct SignalPageHeader: View {
    private let eyebrow: String
    private let title: String

    public init(eyebrow: String, title: String) {
        self.eyebrow = eyebrow
        self.title = title
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Signal.pt(10)) {
            SignalEyebrow(eyebrow)
            Text(title)
                .font(.signal(84, .bold))
                .tracking(-0.05 * Signal.text(84))
                .foregroundStyle(Signal.Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Badges

/// Technik-Badge. Die Farbe sagt, worum es geht: Limette Auflösung, Violett Bild, Türkis Ton.
public struct SignalBadge: View {
    public enum Kind {
        case resolution, picture, audio, neutral

        var color: Color {
            switch self {
            case .resolution: return Signal.Palette.lime
            case .picture: return Signal.Palette.violet
            case .audio: return Signal.Palette.cyan
            case .neutral: return Signal.Palette.text
            }
        }
    }

    private let text: String
    private let kind: Kind

    public init(_ text: String, kind: Kind = .neutral) {
        self.text = text
        self.kind = kind
    }

    public var body: some View {
        Text(text.uppercased())
            .font(.signalMono(15, .medium))
            .foregroundStyle(kind.color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Signal.pt(9))
            .padding(.vertical, Signal.pt(4))
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(kind == .neutral ? Signal.Palette.border : kind.color.opacity(0.6), lineWidth: 1)
            }
    }
}

// MARK: Tasten

/// Taste im Signal-Stil. `primary` ist die gefüllte Limetten-Taste, `secondary` die mit Rahmen.
public struct SignalButtonStyle: ButtonStyle {
    public enum Kind {
        case primary, secondary
    }

    private let kind: Kind

    public init(_ kind: Kind = .secondary) {
        self.kind = kind
    }

    public func makeBody(configuration: Configuration) -> some View {
        Face(kind: kind, configuration: configuration)
    }

    private struct Face: View {
        let kind: Kind
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            let active = isFocused || isHovered
            let filled = kind == .primary || configuration.isPressed
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            configuration.label
                .font(.signalMono(18, kind == .primary ? .bold : .medium))
                .foregroundStyle(filled ? Signal.Palette.background : Signal.Palette.text)
                .padding(.horizontal, Signal.pt(26))
                .frame(minHeight: max(40, Signal.pt(60)))
                .background {
                    if filled {
                        shape.fill(Signal.Palette.limeFill)
                    } else {
                        shape.fill(active ? Signal.Palette.panelActive : Color.clear)
                    }
                }
                .overlay { shape.stroke(filled ? Color.clear : Signal.Palette.border, lineWidth: 1) }
                .signalFocusRing(active, radius: 8, inset: 4)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .animation(Signal.Motion.press, value: configuration.isPressed)
                .animation(Signal.Motion.focus, value: active)
                .trackHover($isHovered)
        }
    }
}

/// Für Kacheln und Listenzeilen: Fokus zeigt Rahmen und Lichtschein, Kacheln wachsen zusätzlich.
public struct SignalCardButtonStyle: ButtonStyle {
    private let radius: CGFloat
    private let grows: Bool

    public init(radius: CGFloat = 6, grows: Bool = true) {
        self.radius = radius
        self.grows = grows
    }

    public func makeBody(configuration: Configuration) -> some View {
        Card(radius: radius, grows: grows, configuration: configuration)
    }

    private struct Card: View {
        let radius: CGFloat
        let grows: Bool
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused
        @State private var isHovered = false

        var body: some View {
            let active = isFocused || isHovered
            configuration.label
                .signalFocusRing(active, radius: radius)
                .scaleEffect(active && grows ? Signal.Motion.focusScale : 1)
                .opacity(configuration.isPressed ? 0.8 : 1)
                .animation(Signal.Motion.focus, value: active)
                .trackHover($isHovered)
        }
    }
}

extension View {
    /// Mauszeiger zählt auf Mac und iPad wie Fokus. Auf dem Fernseher gibt es keinen.
    @ViewBuilder
    func trackHover(_ isHovered: Binding<Bool>) -> some View {
        #if os(tvOS)
        self
        #else
        self.onHover { isHovered.wrappedValue = $0 }
        #endif
    }
}

// MARK: Auswahl

/// Segmentierte Auswahl wie bei den Skip-Intervallen: 5 S | 10 S | 20 S.
public struct SignalSegments<Value: Hashable>: View {
    private let options: [(Value, String)]
    @Binding private var selection: Value

    public init(_ options: [(Value, String)], selection: Binding<Value>) {
        self.options = options
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: Signal.pt(8)) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button {
                    withAnimation(Signal.Motion.press) { selection = option.0 }
                } label: {
                    Text(option.1)
                }
                .buttonStyle(SegmentStyle(isSelected: option.0 == selection))
            }
        }
    }

    private struct SegmentStyle: ButtonStyle {
        let isSelected: Bool

        func makeBody(configuration: Configuration) -> some View {
            Segment(isSelected: isSelected, configuration: configuration)
        }
    }

    private struct Segment: View {
        let isSelected: Bool
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var isFocused
        @State private var isHovered = false

        var body: some View {
            let active = isFocused || isHovered
            let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
            configuration.label
                .font(.signalMono(19, isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? Signal.Palette.background : Signal.Palette.text)
                .padding(.horizontal, Signal.pt(18))
                .frame(minWidth: Signal.pt(84), minHeight: max(36, Signal.pt(56)))
                .background {
                    if isSelected {
                        shape.fill(Signal.Palette.limeFill)
                    } else {
                        shape.fill(active ? Signal.Palette.panelActive : Color.clear)
                    }
                }
                .overlay { shape.stroke(isSelected ? Color.clear : Signal.Palette.border, lineWidth: 1) }
                .signalFocusRing(active, radius: 6, inset: 4)
                .animation(Signal.Motion.focus, value: active)
                .trackHover($isHovered)
        }
    }
}

/// Kleine An-Aus-Taste für Sortierung und Filter. Gewählt ist sie in Limette gefüllt.
public struct SignalChipStyle: ButtonStyle {
    private let isSelected: Bool

    public init(isSelected: Bool) {
        self.isSelected = isSelected
    }

    public func makeBody(configuration: Configuration) -> some View {
        Chip(isSelected: isSelected, configuration: configuration)
    }

    private struct Chip: View {
        let isSelected: Bool
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused
        @State private var isHovered = false

        var body: some View {
            let active = isFocused || isHovered
            let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
            configuration.label
                .font(.signalMono(16, isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? Signal.Palette.background : Signal.Palette.text)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, Signal.pt(16))
                .frame(minHeight: max(34, Signal.pt(48)))
                .background {
                    if isSelected {
                        shape.fill(Signal.Palette.limeFill)
                    } else {
                        shape.fill(active ? Signal.Palette.panelActive : Color.clear)
                    }
                }
                .overlay { shape.stroke(isSelected ? Color.clear : Signal.Palette.border, lineWidth: 1) }
                .signalFocusRing(active, radius: 6, inset: 4)
                .opacity(configuration.isPressed ? 0.8 : 1)
                .animation(Signal.Motion.focus, value: active)
                .trackHover($isHovered)
        }
    }
}

/// Reiht Elemente wie Wörter auf und bricht in die nächste Zeile um, wenn die Breite nicht reicht.
public struct SignalFlow: Layout {
    private let spacing: CGFloat

    public init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.width, height: rows.height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews, width: bounds.width)
        for (index, origin) in rows.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), anchor: .topLeading, proposal: .unspecified
            )
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (origins: [CGPoint], width: CGFloat, height: CGFloat) {
        var origins = [CGPoint]()
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (origins, widest, y + rowHeight)
    }
}

// MARK: Zustände

/// Ladeanzeige und Hinweise für leere oder fehlgeschlagene Inhalte.
public struct SignalNotice: View {
    private let title: String
    private let detail: String?
    private let isLoading: Bool

    public init(_ title: String, detail: String? = nil, isLoading: Bool = false) {
        self.title = title
        self.detail = detail
        self.isLoading = isLoading
    }

    public var body: some View {
        VStack(spacing: Signal.pt(14)) {
            if isLoading {
                ProgressView().tint(Signal.Palette.lime)
            }
            Text(title.uppercased())
                .font(.signalMono(17, .bold))
                .tracking(1)
                .foregroundStyle(Signal.Palette.text)
            if let detail {
                Text(detail)
                    .font(.signal(21))
                    .foregroundStyle(Signal.Palette.textSoft)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Signal.pt(48))
    }
}
#endif
