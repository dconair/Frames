#if canImport(SwiftUI)
import SwiftUI
import FramesCore

/// Quellen für einen Film oder eine Folge, die beste zuerst. Nur direkte Links, also Debrid und Webtor.
/// Darüber Sortierung und Filter, gebaut aus dem, was die Liste wirklich enthält.
struct StreamsView: View {
    let route: StreamsRoute
    @Environment(AppModel.self) private var model
    /// Alle abspielbaren Quellen, ungefiltert.
    @State private var playable: [SourcedStream]?
    @State private var hiddenCount = 0
    @State private var showsFilters = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var firstRowFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Signal.pt(28)) {
                VStack(alignment: .leading, spacing: Signal.pt(10)) {
                    SignalEyebrow(route.item.subtitle ?? "Quellen")
                    Text(route.item.name)
                        .font(.signal(64, .bold))
                        .tracking(-0.04 * Signal.text(64))
                        .foregroundStyle(Signal.Palette.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                }

                if let playable {
                    let streams = model.settings.streamFilter.apply(
                        to: StreamRanker.ranked(playable, preferences: model.settings, sort: model.settings.streamSort)
                    )
                    if !playable.isEmpty {
                        StreamControls(playable: playable, shown: streams.count, isOpen: $showsFilters)
                    }
                    if playable.isEmpty {
                        SignalNotice(
                            "Keine abspielbare Quelle",
                            detail: hiddenCount > 0
                                ? "Deine Addons liefern hierfür nur Torrents. Frames spielt direkte Links ab, wie sie ein Debrid-Addon liefert."
                                : "Keines deiner Addons hat hierfür einen Stream."
                        )
                        #if os(tvOS)
                        // Ohne ein fokussierbares Element käme man auf dem Fernseher von dieser Seite nicht zurück.
                        Button("ZURÜCK") { dismiss() }
                            .buttonStyle(SignalButtonStyle(.primary))
                            .frame(maxWidth: .infinity)
                        #endif
                    } else if streams.isEmpty {
                        SignalNotice(
                            "Kein Treffer mit diesen Filtern",
                            detail: "\(playable.count) Quellen sind da, aber keine passt zu deiner Auswahl."
                        )
                        Button("FILTER ZURÜCKSETZEN") { resetFilter() }
                            .buttonStyle(SignalButtonStyle(.primary))
                            .frame(maxWidth: .infinity)
                    } else {
                        LazyVStack(spacing: Signal.pt(10)) {
                            ForEach(Array(streams.enumerated()), id: \.element.id) { position, item in
                                if let url = item.stream.playableURL {
                                    NavigationLink(value: PlayerRoute(
                                        url: url, headers: item.stream.requestHeaders, item: route.item,
                                        origin: StreamOrigin(item)
                                    )) {
                                        StreamRow(
                                            item: item,
                                            isRecommended: position == 0 && model.settings.streamSort == .recommended,
                                            isFirst: position == 0,
                                            runtimeMinutes: route.item.runtimeMinutes
                                        )
                                    }
                                    .buttonStyle(SignalCardButtonStyle(radius: 8, grows: false))
                                    .focused($firstRowFocused, when: position == 0)
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
            guard playable == nil else { return }
            let all: [SourcedStream]
            if let sample = TestHooks.sampleStreams {
                all = sample
            } else {
                all = await model.content.streams(type: route.item.type, id: route.item.videoId, addons: model.addons)
            }
            let ranked = StreamRanker.ranked(all, preferences: model.settings)
            withAnimation(Signal.Motion.sheet) {
                hiddenCount = all.count - ranked.count
                playable = ranked
            }
            #if os(tvOS) || os(macOS)
            // Während der Abfrage gibt es hier nichts zu fokussieren, der Fokus weicht in die Seitenleiste aus.
            // Sobald die Quellen da sind, gehört er auf die empfohlene.
            try? await Task.sleep(for: .milliseconds(150))
            firstRowFocused = true
            #endif
        }
    }

    private func resetFilter() {
        withAnimation(Signal.Motion.press) { model.settings.streamFilter = StreamFilter() }
        model.saveSettings()
    }
}

/// Die Leiste über der Liste: eine Taste, die Sortierung und Filter aufklappt, und daneben der Stand.
private struct StreamControls: View {
    let playable: [SourcedStream]
    let shown: Int
    @Binding var isOpen: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        let filter = model.settings.streamFilter
        let facets = StreamFacets(playable, selected: filter)
        VStack(alignment: .leading, spacing: Signal.pt(14)) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Signal.pt(20)) {
                    toggle(filter)
                    summary(filter)
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: Signal.pt(10)) {
                    toggle(filter)
                    summary(filter)
                }
            }
            if isOpen {
                VStack(alignment: .leading, spacing: Signal.pt(12)) {
                    group("Sortierung", StreamSort.allCases.map { sort in
                        Choice(label: sort.label, isOn: model.settings.streamSort == sort) {
                            model.settings.streamSort = sort
                        }
                    }, always: true)
                    group("Auflösung", facets.resolutions.map { value in
                        choice(value.label, \.resolutions, value)
                    })
                    group("Bild", facets.pictures.map { value in
                        choice(value.label, \.pictures, value)
                    })
                    group("Ton", facets.sounds.map { value in
                        choice(value.label, \.sounds, value)
                    })
                    group("Fassung", facets.releases.map { value in
                        choice(value.label, \.releases, value)
                    })
                    group("Quelle", facets.services.map { value in
                        choice(value.label, \.services, value)
                    })
                    group("Sprache", facets.languages.map { value in
                        choice(StreamFilter.languageLabel(value), \.languages, value)
                    })
                }
                .padding(Signal.pt(20))
                .frame(maxWidth: .infinity, alignment: .leading)
                .signalPanel()
                .transition(.opacity)
            }
        }
    }

    private func toggle(_ filter: StreamFilter) -> some View {
        Button {
            withAnimation(Signal.Motion.press) { isOpen.toggle() }
        } label: {
            Text(isOpen ? "SORTIEREN & FILTERN  ▴" : "SORTIEREN & FILTERN  ▾")
        }
        .buttonStyle(SignalChipStyle(isSelected: false))
        .accessibilityIdentifier("quellen-filter")
    }

    private func summary(_ filter: StreamFilter) -> some View {
        var parts = [model.settings.streamSort.label]
        if !filter.isEmpty { parts.append("\(filter.activeCount) FILTER") }
        parts.append(shown == playable.count ? "\(shown) QUELLEN" : "\(shown) VON \(playable.count) QUELLEN")
        return Text(parts.joined(separator: " · "))
            .font(.signalMono(15))
            .foregroundStyle(filter.isEmpty ? Signal.Palette.textMuted : Signal.Palette.lime)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityIdentifier("quellen-stand")
    }

    private struct Choice {
        var label: String
        var isOn: Bool
        var action: () -> Void
    }

    private func choice<Value: Hashable>(
        _ label: String, _ path: WritableKeyPath<StreamFilter, Set<Value>>, _ value: Value
    ) -> Choice {
        Choice(label: label, isOn: model.settings.streamFilter[keyPath: path].contains(value)) {
            if model.settings.streamFilter[keyPath: path].contains(value) {
                model.settings.streamFilter[keyPath: path].remove(value)
            } else {
                model.settings.streamFilter[keyPath: path].insert(value)
            }
        }
    }

    /// Eine Zeile mit Namen und Tasten. Gibt es nichts zu wählen, entfällt sie.
    @ViewBuilder
    private func group(_ title: String, _ choices: [Choice], always: Bool = false) -> some View {
        if always || choices.count > 1 || choices.contains(where: \.isOn) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Signal.pt(16)) {
                    groupTitle(title).frame(width: max(96, Signal.pt(170)), alignment: .leading)
                    chips(choices)
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: Signal.pt(8)) {
                    groupTitle(title)
                    SignalFlow(spacing: max(8, Signal.pt(10))) { chipButtons(choices) }
                }
            }
            #if os(tvOS) || os(macOS)
            .focusSection()
            #endif
        }
    }

    private func groupTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.signalMono(15, .bold))
            .tracking(1)
            .foregroundStyle(Signal.Palette.textMuted)
    }

    private func chips(_ choices: [Choice]) -> some View {
        HStack(spacing: max(8, Signal.pt(10))) { chipButtons(choices) }
    }

    private func chipButtons(_ choices: [Choice]) -> some View {
        ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
            Button(choice.label) {
                withAnimation(Signal.Motion.press) { choice.action() }
                model.saveSettings()
            }
            .buttonStyle(SignalChipStyle(isSelected: choice.isOn))
            .accessibilityAddTraits(choice.isOn ? .isSelected : [])
        }
    }
}

private struct StreamRow: View {
    let item: SourcedStream
    let isRecommended: Bool
    let isFirst: Bool
    let runtimeMinutes: Int?

    private var detail: String {
        let text = item.stream.filename ?? item.stream.title ?? item.stream.name ?? ""
        return text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }

    var body: some View {
        let info = item.info
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Signal.pt(20)) {
                title
                Spacer(minLength: Signal.pt(12))
                badges(info)
            }
            // Auf dem iPhone ist die Zeile zu schmal, dort rücken die Angaben unter den Namen.
            VStack(alignment: .leading, spacing: 8) {
                title
                SignalFlow(spacing: max(6, Signal.pt(8))) { badgeList(info) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
        }
        .padding(.horizontal, Signal.pt(24))
        .frame(maxWidth: .infinity, minHeight: max(56, Signal.pt(92)), alignment: .leading)
        .signalPanel(active: isFirst)
    }

    private var title: some View {
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
                            .fixedSize()
                    }
                }
                Text(detail)
                    .font(.signalMono(15))
                    .foregroundStyle(Signal.Palette.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
    }

    private func badges(_ info: StreamInfo) -> some View {
        HStack(spacing: Signal.pt(8)) { badgeList(info) }
            .fixedSize()
    }

    @ViewBuilder
    private func badgeList(_ info: StreamInfo) -> some View {
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
                if let bitrate = info.bitrateLabel(runtimeMinutes: runtimeMinutes) {
                    SignalBadge(bitrate)
                }
                if let service = info.service {
                    SignalBadge(service.label)
                }
                if info.isCached == false {
                    SignalBadge("LÄDT ERST")
                }
    }
}

private extension View {
    /// Bindet den Fokus nur an die Zeile, für die die Bedingung gilt.
    @ViewBuilder
    func focused(_ binding: FocusState<Bool>.Binding, when condition: Bool) -> some View {
        if condition {
            focused(binding)
        } else {
            self
        }
    }
}
#endif
