#if canImport(SwiftUI)
import SwiftUI
import FramesCore

/// Quellen für einen Film oder eine Folge, die beste zuerst. Nur direkte Links, also Debrid.
struct StreamsView: View {
    let route: StreamsRoute
    @Environment(AppModel.self) private var model
    @State private var streams: [SourcedStream]?
    @State private var hiddenCount = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Signal.pt(28)) {
                VStack(alignment: .leading, spacing: Signal.pt(10)) {
                    SignalEyebrow(route.subtitle ?? "Quellen")
                    Text(route.title)
                        .font(.signal(64, .bold))
                        .tracking(-0.04 * Signal.text(64))
                        .foregroundStyle(Signal.Palette.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                }

                if let streams {
                    if streams.isEmpty {
                        SignalNotice(
                            "Keine abspielbare Quelle",
                            detail: hiddenCount > 0
                                ? "Deine Addons liefern hierfür nur Torrents. Frames spielt direkte Links ab, wie sie ein Debrid-Addon liefert."
                                : "Keines deiner Addons hat hierfür einen Stream."
                        )
                    } else {
                        LazyVStack(spacing: Signal.pt(10)) {
                            ForEach(Array(streams.enumerated()), id: \.element.id) { position, item in
                                if let url = item.stream.playableURL {
                                    NavigationLink(value: PlayerRoute(
                                        url: url, headers: item.stream.requestHeaders,
                                        title: route.title, subtitle: route.subtitle
                                    )) {
                                        StreamRow(item: item, isRecommended: position == 0)
                                    }
                                    .buttonStyle(SignalCardButtonStyle(radius: 8, grows: false))
                                }
                            }
                        }
                        if hiddenCount > 0 {
                            Text("\(hiddenCount) WEITERE QUELLEN OHNE DIREKTEN LINK AUSGEBLENDET")
                                .font(.signalMono(15))
                                .foregroundStyle(Signal.Palette.textMuted)
                        }
                    }
                } else {
                    SignalNotice("Quellen werden abgefragt", isLoading: true)
                }
            }
            .padding(.horizontal, PageInsets.horizontal)
            .padding(.top, PageInsets.top)
            .padding(.bottom, Signal.pt(80))
        }
        .scrollIndicators(.hidden)
        .signalPage()
        .task(id: route) {
            guard streams == nil else { return }
            let all = await model.content.streams(type: route.type, id: route.streamId, addons: model.addons)
            let ranked = StreamRanker.ranked(all, preferences: model.settings)
            withAnimation(Signal.Motion.sheet) {
                hiddenCount = all.count - ranked.count
                streams = ranked
            }
        }
    }
}

private struct StreamRow: View {
    let item: SourcedStream
    let isRecommended: Bool

    private var detail: String {
        let text = item.stream.filename ?? item.stream.title ?? item.stream.name ?? ""
        return text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }

    var body: some View {
        let info = item.info
        HStack(spacing: Signal.pt(20)) {
            VStack(alignment: .leading, spacing: Signal.pt(6)) {
                HStack(spacing: Signal.pt(12)) {
                    Text(item.addonName)
                        .font(.signal(26, .semibold))
                        .foregroundStyle(Signal.Palette.text)
                        .lineLimit(1)
                    if isRecommended {
                        Text("EMPFOHLEN")
                            .font(.signalMono(14, .bold))
                            .foregroundStyle(Signal.Palette.background)
                            .padding(.horizontal, Signal.pt(8))
                            .padding(.vertical, Signal.pt(3))
                            .background(Signal.Palette.limeFill, in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text(detail)
                    .font(.signalMono(15))
                    .foregroundStyle(Signal.Palette.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Signal.pt(12))
            HStack(spacing: Signal.pt(8)) {
                if let resolution = info.resolution {
                    SignalBadge(resolution.label, kind: .resolution)
                }
                if let range = info.dynamicRange {
                    SignalBadge(range.label, kind: .picture)
                }
                if let audio = info.audioLabel {
                    SignalBadge(audio, kind: .audio)
                }
                if let size = info.sizeLabel {
                    SignalBadge(size)
                }
                if info.isCached == false {
                    SignalBadge("LÄDT ERST")
                }
            }
        }
        .padding(.horizontal, Signal.pt(24))
        .frame(maxWidth: .infinity, minHeight: max(56, Signal.pt(92)), alignment: .leading)
        .signalPanel(active: isRecommended)
    }
}
#endif
