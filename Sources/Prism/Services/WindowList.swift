import AppKit

/// A normal window of a regular app, on any Space.
struct WindowEntry {
    let id: CGWindowID
    let pid: pid_t
    let appName: String
    let appPath: String?
    let title: String
}

enum WindowList {
    /// Every normal window front to back, across Spaces. Titles need Screen Recording access;
    /// without it rows fall back to the app name.
    static func all() -> [WindowEntry] {
        let own = ProcessInfo.processInfo.processIdentifier
        let apps = Dictionary(NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != own }
            .map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        var entries: [WindowEntry] = []
        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, let app = apps[pid],
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width > 100, bounds.height > 100,
                  let id = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            let name = app.localizedName ?? "Window"
            let title = (info[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? name
            entries.append(WindowEntry(id: id, pid: pid, appName: name, appPath: app.bundleURL?.path, title: title))
        }
        return entries
    }
}
