import AppKit
import PrismCore

/// The Transform Text route. Works on the selected text when opened from it, otherwise the clipboard's text.
final class TransformResults: ResultProvider {
    private var source = ""
    private var fromSelection = false
    /// Set just before pushing the route to transform text other than the clipboard's.
    var pendingSource: String?

    func activate() {
        fromSelection = pendingSource != nil
        source = pendingSource ?? NSPasteboard.general.string(forType: .string) ?? ""
        pendingSource = nil
    }

    func items(for query: String) -> [ResultItem] {
        let source = source
        guard !source.isEmpty else { return [] }
        return TextTransform.allCases.compactMap { transform in
            guard Fuzzy.score(query, transform.title) != nil, let output = transform.apply(source) else { return nil }
            let preview = output.replacingOccurrences(of: "\n", with: " ⏎ ")
            return ResultItem(
                id: "transform.\(transform.title)", title: transform.title, subtitle: String(preview.prefix(80)),
                icon: .symbol(transform.symbol, .green), section: fromSelection ? "Selected Text" : "Clipboard Text",
                actions: [
                    ItemAction(title: fromSelection ? "Replace Selection" : "Paste Result", symbol: "doc.on.clipboard", shortcut: .enter) {
                        Paster.copy(output)
                        Paster.pasteIntoFrontApp()
                    },
                    ItemAction(title: "Copy Result", symbol: "doc.on.doc", shortcut: .cmdEnter) {
                        Paster.copy(output)
                        Toast.show("Copied", symbol: "textformat")
                    },
                ]
            )
        }
    }
}
