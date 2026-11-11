import AppKit
import PrismCore

/// The Search Menu Items route, over the frontmost app's menu bar read when the route opens.
final class MenuItemResults: ResultProvider {
    private var entries: [MenuEntry] = []
    private var appName = ""

    func activate() {
        // The launcher is a non-activating panel, so the app the user was in is still frontmost.
        let app = NSWorkspace.shared.frontmostApplication
        appName = app?.localizedName ?? ""
        entries = app.map(MenuBarItems.items) ?? []
    }

    func items(for query: String) -> [ResultItem] {
        let ranked = entries.compactMap { entry -> (MenuEntry, Double)? in
            Fuzzy.score(query, entry.title, keywords: [entry.path]).map { (entry, $0) }
        }
        let ordered = query.isEmpty ? ranked : ranked.sorted { $0.1 > $1.1 }
        return ordered.prefix(200).enumerated().map { index, pair in
            let entry = pair.0
            return ResultItem(
                id: "menu.\(index).\(entry.path).\(entry.title)", title: entry.title, subtitle: entry.path,
                icon: .symbol("filemenu.and.selection", .gray), accessory: entry.shortcut, section: appName,
                actions: [ItemAction(title: "Choose Menu Item", symbol: "return", shortcut: .enter) {
                    // Give the panel a moment to close so the menu acts on the app, not on us.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { MenuBarItems.press(entry) }
                }]
            )
        }
    }
}
