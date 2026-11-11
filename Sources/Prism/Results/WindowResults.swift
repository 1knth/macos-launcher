import AppKit
import PrismCore

/// The Switch Windows route, over a snapshot of every window taken when the route opens.
final class WindowResults: ResultProvider {
    private var windows: [WindowEntry] = []

    func activate() { windows = WindowList.all() }

    func items(for query: String) -> [ResultItem] {
        let ranked = windows.compactMap { entry -> (WindowEntry, Double)? in
            Fuzzy.score(query, entry.title, keywords: [entry.appName]).map { (entry, $0) }
        }
        // With no query keep the window server's front-to-back order.
        let ordered = query.isEmpty ? ranked : ranked.sorted { $0.1 > $1.1 }
        return ordered.map { entry, _ in
            ResultItem(
                id: "win.\(entry.id)", title: entry.title, subtitle: entry.title == entry.appName ? nil : entry.appName,
                icon: entry.appPath.map { .file($0) } ?? .symbol("macwindow", .cyan), section: "Windows",
                actions: [
                    ItemAction(title: "Switch to Window", symbol: "macwindow", shortcut: .enter) {
                        AppActivator.focus(windowID: entry.id, pid: entry.pid)
                    },
                    ItemAction(title: "Quit \(entry.appName)", symbol: "xmark.circle", shortcut: .ctrl("q")) {
                        NSRunningApplication(processIdentifier: entry.pid)?.terminate()
                    },
                ]
            )
        }
    }
}
