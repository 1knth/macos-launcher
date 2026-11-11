import AppKit

/// The Clipboard History route. Typing filters by text, file path, source app or kind ("images", "link").
final class ClipboardResults: ResultProvider {
    private unowned let navigator: LauncherNavigator
    private let store: ClipboardStore
    private static let thumbnails = NSCache<NSString, NSImage>()

    init(store: ClipboardStore, navigator: LauncherNavigator) {
        self.store = store
        self.navigator = navigator
        store.onChange = { [weak navigator] in
            if navigator?.route == .clipboard { navigator?.refresh(keepSelection: true) }
        }
    }

    func items(for raw: String) -> [ResultItem] {
        let query = raw.trimmingCharacters(in: .whitespaces)
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Active App"
        return store.items
            .filter { matches($0, query) }
            .sorted { $0.pinned && !$1.pinned }
            .map { item(for: $0, frontApp: front) }
    }

    private func matches(_ clip: ClipItem, _ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let lowered = query.lowercased()
        if clip.kind.rawValue == lowered || (lowered == "images" && clip.kind == .image) { return true }
        if let text = clip.text, text.localizedCaseInsensitiveContains(query) { return true }
        if let paths = clip.filePaths, paths.contains(where: { $0.localizedCaseInsensitiveContains(query) }) { return true }
        return clip.sourceApp?.localizedCaseInsensitiveContains(query) == true
    }

    private func item(for clip: ClipItem, frontApp: String) -> ResultItem {
        let store = store
        var actions = [
            ItemAction(title: "Paste to \(frontApp)", symbol: "doc.on.clipboard", shortcut: .enter) {
                store.write(clip)
                Paster.pasteIntoFrontApp()
            },
            ItemAction(title: "Copy to Clipboard", symbol: "doc.on.doc", shortcut: .cmdEnter) {
                store.write(clip)
                Toast.show("Copied to clipboard", symbol: "doc.on.doc")
            },
        ]
        if clip.kind != .image {
            actions.append(ItemAction(title: "Paste as Plain Text", symbol: "textformat", shortcut: .cmdShift("v")) {
                store.write(clip, plainText: true)
                Paster.pasteIntoFrontApp()
            })
        }
        if clip.kind == .link, let text = clip.text, let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            actions.append(ItemAction(title: "Open Link", symbol: "safari", shortcut: .cmd("o")) { NSWorkspace.shared.open(url) })
        }
        if clip.kind == .image {
            actions.append(ItemAction(title: "Copy Text in Image (OCR)", symbol: "text.viewfinder", shortcut: .cmdShift("e")) {
                OCRController.copyText(from: store.image(for: clip))
            })
        }
        if clip.kind == .color, let hex = clip.text {
            actions.append(ItemAction(title: "Open in Color Wheel", symbol: "paintpalette", shortcut: .cmd("o"), dismiss: false) { [weak navigator] in
                navigator?.push(.colorWheel, query: hex.trimmingCharacters(in: .whitespacesAndNewlines))
            })
        }
        actions.append(ItemAction(title: clip.pinned ? "Unpin" : "Pin", symbol: clip.pinned ? "pin.slash" : "pin", shortcut: .cmdShift("p"), dismiss: false) { [weak navigator] in
            store.togglePin(clip)
            navigator?.refresh(keepSelection: true)
        })
        actions.append(ItemAction(title: "Delete Entry", symbol: "trash", shortcut: .ctrl("x"), destructive: true, dismiss: false) { [weak navigator] in
            store.delete(clip)
            navigator?.refresh(keepSelection: false)
        })
        actions.append(ItemAction(title: "Delete All Unpinned", symbol: "trash.slash", shortcut: .ctrlShift("x"), destructive: true, dismiss: false) { [weak navigator] in
            let alert = NSAlert()
            alert.messageText = "Delete all unpinned clipboard history?"
            alert.informativeText = "Pinned entries are kept. This can’t be undone."
            alert.addButton(withTitle: "Delete").hasDestructiveAction = true
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                store.clear()
                navigator?.refresh()
            }
        })
        return ResultItem(id: "clip:\(clip.id)", title: clip.title.isEmpty ? "(whitespace)" : clip.title, icon: icon(for: clip),
                          accessory: clip.date.relative, section: clip.pinned ? "Pinned" : "Recent", actions: actions, preview: .clip(clip))
    }

    private func icon(for clip: ClipItem) -> ItemIcon {
        switch clip.kind {
        case .text: return .symbol("text.alignleft", .gray)
        case .link: return .symbol("link", .blue)
        case .color: return NSColor(hex: clip.text ?? "").map { .color($0) } ?? .symbol("paintpalette", .pink)
        case .file: return .file(clip.filePaths?.first ?? "/")
        case .image:
            let key = clip.id.uuidString as NSString
            if let cached = Self.thumbnails.object(forKey: key) { return .image(cached) }
            guard let image = store.image(for: clip) else { return .symbol("photo", .purple) }
            Self.thumbnails.setObject(image, forKey: key)
            return .image(image)
        }
    }
}
