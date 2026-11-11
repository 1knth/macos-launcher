import AppKit
import PrismCore

/// Actions on text selected in the frontmost app, shown at the top of an empty root search.
/// The text is read once per open, before the launcher takes focus.
final class SelectionResults {
    private unowned let navigator: LauncherNavigator
    private let transform: TransformResults
    let translator = Translator()
    private(set) var text = ""

    init(transform: TransformResults, navigator: LauncherNavigator) {
        self.transform = transform
        self.navigator = navigator
        translator.onFinish = { [weak navigator] in
            if navigator?.route == .root { navigator?.refresh(keepSelection: true) }
        }
    }

    /// Call while the previous app still has focus.
    func capture() {
        text = SelectedText.capture()
        if !text.isEmpty { translator.translate(text) }
    }

    func items() -> [ResultItem] {
        let text = text
        let translator = translator
        guard !text.isEmpty else { return [] }
        let short = text.count > 40 ? String(text.prefix(40)) + "…" : text
        let oneLine = short.replacingOccurrences(of: "\n", with: " ")
        let section = "Selected Text · “\(oneLine)”"
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var items: [ResultItem] = []

        if let result = Calculator.evaluate(trimmed) {
            items.append(ResultItem(
                id: "sel.calc", title: "= \(result.display)", icon: .symbol("equal", .orange), accessory: "Calculate", section: section,
                actions: [
                    ItemAction(title: "Replace with Answer", symbol: "arrow.left.arrow.right", shortcut: .enter) { SelectedText.replace(with: result.copy) },
                    ItemAction(title: "Copy Answer", symbol: "doc.on.doc", shortcut: .cmdEnter) { Paster.copy(result.copy) },
                ]
            ))
        }
        if let url = WebSearch.directURL(trimmed) {
            items.append(ResultItem(
                id: "sel.url", title: "Open \(url.host ?? url.absoluteString)", icon: .symbol("safari.fill", .blue), section: section,
                actions: [ItemAction(title: "Open in Browser", symbol: "safari", shortcut: .enter) { NSWorkspace.shared.open(url) }]
            ))
        }
        let path = NSString(string: trimmed).expandingTildeInPath
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~"), FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            items.append(ResultItem(
                id: "sel.path", title: "Open \(url.lastPathComponent)", icon: .file(path), section: section,
                actions: [
                    ItemAction(title: "Open", symbol: "arrow.up.forward.square", shortcut: .enter) { NSWorkspace.shared.open(url) },
                    ItemAction(title: "Show in Finder", symbol: "folder", shortcut: .cmdEnter) { NSWorkspace.shared.activateFileViewerSelecting([url]) },
                ]
            ))
        }
        if case .idle = translator.status {} else {
            let subtitle: String
            switch translator.status {
            case .done(let result): subtitle = result.replacingOccurrences(of: "\n", with: " ")
            case .failed: subtitle = "Unavailable. Add the language in System Settings › General › Language & Region › Translation Languages."
            default: subtitle = "Translating…"
            }
            var actions: [ItemAction] = []
            if case .done(let result) = translator.status {
                actions = [
                    ItemAction(title: "Replace with Translation", symbol: "arrow.left.arrow.right", shortcut: .enter) { SelectedText.replace(with: result) },
                    ItemAction(title: "Copy Translation", symbol: "doc.on.doc", shortcut: .cmdEnter) { Paster.copy(result) },
                ]
            }
            items.append(ResultItem(
                id: "sel.translate", title: "Translate to \(translator.targetName)", subtitle: subtitle,
                icon: .symbol("translate", .blue), section: section, actions: actions
            ))
        }
        items.append(ResultItem(
            id: "sel.transform", title: "Transform Text", subtitle: "Case, lines, Base64, JSON…", icon: .symbol("textformat", .green), section: section,
            actions: [ItemAction(title: "Show Transforms", symbol: "textformat", shortcut: .enter, dismiss: false) { [weak self] in
                self?.transform.pendingSource = text
                self?.navigator.push(.transform)
            }]
        ))
        items.append(ResultItem(
            id: "sel.search", title: "Search Google", icon: .symbol("magnifyingglass", .blue), section: section,
            actions: [ItemAction(title: "Search Google", symbol: "safari", shortcut: .enter) {
                WebSearch.openGoogle(trimmed)
            }]
        ))
        if !trimmed.contains("\n"), trimmed.split(separator: " ").count <= 3,
           let url = URL(string: "dict://\(trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed)") {
            items.append(ResultItem(
                id: "sel.define", title: "Look Up in Dictionary", icon: .symbol("character.book.closed.fill", .brown), section: section,
                actions: [ItemAction(title: "Look Up", symbol: "book", shortcut: .enter) { NSWorkspace.shared.open(url) }]
            ))
        }
        items.append(ResultItem(
            id: "sel.files", title: "Search Files", icon: .symbol("doc.text.magnifyingglass", .blue), section: section,
            actions: [ItemAction(title: "Search Files", symbol: "doc.text.magnifyingglass", shortcut: .enter, dismiss: false) { [weak navigator] in
                navigator?.push(.files, query: String(trimmed.prefix(80)))
            }]
        ))
        items.append(ResultItem(
            id: "sel.copy", title: "Copy Text", icon: .symbol("doc.on.doc", .gray), section: section,
            actions: [ItemAction(title: "Copy", symbol: "doc.on.doc", shortcut: .enter) {
                Paster.copy(text)
                Toast.show("Copied", symbol: "doc.on.doc")
            }]
        ))
        return items
    }
}
