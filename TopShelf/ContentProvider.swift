import TVServices
import FramesCore

/// Top Shelf von Frames: Liegt die App ganz oben auf dem Home-Bildschirm des Apple TV, zeigt sie darüber
/// „Weiter ansehen“. Mit breiten Bildern als Karussell, sonst als Reihe von Postern.
/// Die Daten kommen von der App über den gemeinsamen Ordner (`TopShelfSnapshot`).
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        guard let snapshot = TopShelfSnapshot.read(), !snapshot.entries.isEmpty else {
            // Ohne Daten bleibt das feste Top-Shelf-Bild der App.
            return nil
        }
        if let carousel = carousel(from: snapshot.entries) {
            return carousel
        }
        return posters(from: snapshot.entries)
    }

    private func carousel(from entries: [TopShelfSnapshot.Entry]) -> TVTopShelfCarouselContent? {
        let items = entries.compactMap { entry -> TVTopShelfCarouselItem? in
            guard let background = entry.background else { return nil }
            let item = TVTopShelfCarouselItem(identifier: entry.id)
            item.title = entry.name
            item.summary = entry.subtitle
            item.setImageURL(background, for: [.screenScale1x, .screenScale2x])
            if let link = entry.link {
                item.displayAction = TVTopShelfAction(url: link)
                item.playAction = TVTopShelfAction(url: link)
            }
            return item
        }
        guard !items.isEmpty else { return nil }
        return TVTopShelfCarouselContent(style: .actions, items: items)
    }

    private func posters(from entries: [TopShelfSnapshot.Entry]) -> TVTopShelfSectionedContent {
        let items = entries.map { entry -> TVTopShelfSectionedItem in
            let item = TVTopShelfSectionedItem(identifier: entry.id)
            item.title = entry.name
            item.imageShape = .poster
            if let poster = entry.poster {
                item.setImageURL(poster, for: [.screenScale1x, .screenScale2x])
            }
            item.playbackProgress = entry.progress ?? 0
            if let link = entry.link {
                item.displayAction = TVTopShelfAction(url: link)
                item.playAction = TVTopShelfAction(url: link)
            }
            return item
        }
        let section = TVTopShelfItemCollection(items: items)
        section.title = "Weiter ansehen"
        return TVTopShelfSectionedContent(sections: [section])
    }
}
