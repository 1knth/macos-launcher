import AppKit
import PrismCore

/// The Emoji route: recently used first, then the whole catalog, or fuzzy matches by name and keyword.
final class EmojiResults: ResultProvider {
    private let frecency: Frecency

    init(frecency: Frecency) { self.frecency = frecency }

    func items(for raw: String) -> [ResultItem] {
        let query = raw.trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            let ids = Set(EmojiCatalog.all.map(Self.usageKey))
            let recent = frecency.top(12, among: ids).compactMap { id in EmojiCatalog.all.first { Self.usageKey($0) == id } }
            return recent.map { item($0, section: "Recently Used") } + EmojiCatalog.all.map { item($0, section: "All Emoji") }
        }
        return EmojiCatalog.all
            .compactMap { entry -> (EmojiEntry, Double)? in
                Fuzzy.score(query, entry.name, keywords: EmojiCatalog.keywords[entry.character] ?? [])
                    .map { (entry, $0 + frecency.boost(Self.usageKey(entry))) }
            }
            .filter { $0.1 >= 0.5 }
            .sorted { $0.1 > $1.1 }
            .prefix(150)
            .map { item($0.0, section: "Results") }
    }

    private static func usageKey(_ entry: EmojiEntry) -> String { "emoji:\(entry.character)" }

    private func item(_ entry: EmojiEntry, section: String) -> ResultItem {
        let id = Self.usageKey(entry)
        return ResultItem(
            // The same emoji can appear under Recently Used and All Emoji; row IDs must stay unique.
            id: section == "Recently Used" ? "recent-\(id)" : id, title: entry.name, icon: .emoji(entry.character), section: section,
            actions: [
                ItemAction(title: "Paste Emoji", symbol: "doc.on.clipboard", shortcut: .enter) {
                    Paster.copy(entry.character)
                    Paster.pasteIntoFrontApp()
                },
                ItemAction(title: "Copy Emoji", symbol: "doc.on.doc", shortcut: .cmdEnter) {
                    Paster.copy(entry.character)
                    Toast.show("Copied \(entry.character)", symbol: "face.smiling")
                },
            ],
            usageKey: id
        )
    }
}
