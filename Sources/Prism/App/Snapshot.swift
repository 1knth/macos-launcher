import AppKit
import SwiftUI

/// Development aid: `Prism --snapshot out.png <route> [query]` renders the launcher offscreen.
enum Snapshot {
    static func run(_ arguments: [String]) {
        let output = arguments[0]
        if arguments.count > 1, arguments[1] == "settings" {
            let pane = arguments.count > 2 ? SettingsPane(rawValue: arguments[2]) ?? .general : .general
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 560), styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: arguments.contains("--light") ? .aqua : .darkAqua)
            let view = NSHostingView(rootView: PrismSettingsView(pane: pane).background(Color(nsColor: .windowBackgroundColor)))
            view.frame = window.contentLayoutRect
            window.contentView = view
            RunLoop.main.run(until: Date().addingTimeInterval(1.0))
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output))
            exit(0)
        }
        if arguments.count > 1, arguments[1] == "ocr" {
            let view = SelectionView(frame: CGRect(x: 0, y: 0, width: 900, height: 560))
            view.start = CGPoint(x: 220, y: 340)
            view.end = CGPoint(x: 620, y: 220)
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            NSColor.systemTeal.setFill()
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output))
            exit(0)
        }
        let routes: [String: Route] = ["usage": .usage, "google": .google, "root": .root, "files": .files, "clipboard": .clipboard, "emoji": .emoji, "wheel": .colorWheel, "colors": .colors, "chat": .chat]
        let services = AppServices.shared
        services.apps.reload()
        let state = LauncherState()
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        state.refresh()
        if let route = routes[arguments.count > 1 ? arguments[1] : "root"], route != .root { state.push(route) }
        if arguments.count > 2 { state.query = arguments[2] }
        if arguments.count > 3 { state.selection = Int(arguments[3]) ?? 0 }
        if arguments.contains("--actions") { state.showActions = true }
        if arguments.contains("--open-chat"), let first = state.chat.conversations.first { state.chat.select(first.id) }
        // Let Spotlight queries and async previews settle.
        RunLoop.main.run(until: Date().addingTimeInterval(2.5))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: LauncherView.size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: arguments.contains("--light") ? .aqua : .darkAqua)
        let view = NSHostingView(rootView: LauncherView(state: state).background(Color(nsColor: .windowBackgroundColor)))
        view.frame = window.contentLayoutRect
        window.contentView = view
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output))
        exit(0)
    }
}
