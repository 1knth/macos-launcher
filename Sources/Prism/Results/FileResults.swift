import AppKit
import PrismCore

/// The Search Files route: Spotlight results with a names-only or names-and-contents mode.
final class FileResults: ResultProvider {
    private unowned let navigator: LauncherNavigator
    private let searcher = FileSearcher()
    /// Toggled with ⌘T or the header pill.
    var contentMode = false

    init(navigator: LauncherNavigator) {
        self.navigator = navigator
        searcher.onUpdate = { [weak navigator] in
            if navigator?.route == .files { navigator?.refresh(keepSelection: true) }
        }
    }

    func deactivate() { searcher.stop() }

    func toggleContentMode() {
        contentMode.toggle()
        navigator.refresh()
    }

    func items(for query: String) -> [ResultItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        searcher.search(trimmed, contents: contentMode, limit: 80)
        let section = trimmed.isEmpty ? "Recently Used" : (contentMode ? "Names & Contents" : "Files")
        let toggle = ItemAction(title: contentMode ? "Search Names Only" : "Search Names & Contents", symbol: "text.magnifyingglass",
                                shortcut: .cmd("t"), dismiss: false) { [weak self] in self?.toggleContentMode() }
        return searcher.results.map { url in
            FileResults.item(url, section: section, navigator: navigator, extraActions: [toggle]) { [weak self] in
                self?.searcher.stop()
            }
        }
    }

    /// A file row, shared with the root search's file hits. `onTrashed` runs before the list refreshes.
    static func item(_ url: URL, section: String, navigator: LauncherNavigator, extraActions: [ItemAction] = [],
                     onTrashed: @escaping () -> Void) -> ResultItem {
        let path = url.path
        let parent = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        var actions = [
            ItemAction(title: "Open", symbol: "arrow.up.forward.square", shortcut: .enter) { NSWorkspace.shared.open(url) },
            ItemAction(title: "Show in Finder", symbol: "folder", shortcut: .cmdEnter) { NSWorkspace.shared.activateFileViewerSelecting([url]) },
            ItemAction(title: "Copy Path", symbol: "doc.on.doc", shortcut: .cmdShift("c")) {
                Paster.copy(path)
                Toast.show("Copied path", symbol: "doc.on.doc")
            },
            ItemAction(title: "Copy File", symbol: "doc.on.clipboard", shortcut: .cmdOption("c")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([url as NSURL])
                Toast.show("Copied \(url.lastPathComponent)", symbol: "doc.on.clipboard")
            },
        ]
        if FileKind.isImage(url) {
            actions.append(ItemAction(title: "Copy Text in Image (OCR)", symbol: "text.viewfinder", shortcut: .cmdShift("e")) {
                OCRController.copyText(from: NSImage(contentsOf: url))
            })
        }
        if isDirectory.boolValue {
            actions.append(ItemAction(title: "Open in Terminal", symbol: "terminal", shortcut: .cmdShift("t")) {
                Shell.run("/usr/bin/open", ["-a", "Terminal", path])
            })
        }
        actions += extraActions
        actions.append(ItemAction(title: "Move to Trash", symbol: "trash", shortcut: .ctrl("x"), destructive: true, dismiss: false) { [weak navigator] in
            NSWorkspace.shared.recycle([url]) { _, error in
                DispatchQueue.main.async {
                    navigator?.flash(error == nil ? "Moved to Trash" : "Couldn’t move to Trash", symbol: "trash")
                    onTrashed()
                    navigator?.refresh(keepSelection: true)
                }
            }
        })
        return ResultItem(id: "file:\(path)", title: url.lastPathComponent, subtitle: parent, icon: .file(path), section: section, actions: actions, preview: .file(url))
    }
}
