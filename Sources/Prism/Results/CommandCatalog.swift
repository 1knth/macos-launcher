import AppKit
import PrismCore
import SwiftUI

/// A root-search entry that runs one thing.
struct Command {
    let id: String
    let title: String
    var subtitle: String?
    let symbol: String
    let color: Color
    var keywords: [String] = []
    var accessory = "Command"
    var dismiss = true
    let run: () -> Void
}

/// Every built-in command: navigation into other routes, system actions, generators, folders,
/// System Settings panes and window layouts. Rebuilt per search so titles reflect current state
/// ("Keep Awake" vs "Stop Keeping Awake").
final class CommandCatalog {
    private unowned let navigator: LauncherNavigator
    private let services: AppServices

    init(services: AppServices, navigator: LauncherNavigator) {
        self.services = services
        self.navigator = navigator
    }

    func all() -> [Command] {
        let s = services
        var list: [Command] = [
            Command(id: "nav.chat", title: "Ask AI", subtitle: "Chat with GPT-6 Luna", symbol: "sparkles", color: .indigo, keywords: ["chat", "gpt", "luna", "question", "assistant"], dismiss: false) { [weak navigator] in navigator?.push(.chat) },
            Command(id: "usage.limits", title: "AI Usage Limits", subtitle: "Subscription usage and reset times", symbol: "chart.bar", color: .orange, keywords: ["claude", "gpt", "chatgpt", "codex", "usage", "limits", "quota", "tokens"], dismiss: false) { [weak navigator] in navigator?.push(.usage) },
            Command(id: "settings.wallpaper", title: "Wallpaper", subtitle: "Change desktop wallpaper", symbol: "photo", color: .cyan, keywords: ["background", "desktop", "wallpaper", "settings"]) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension") { NSWorkspace.shared.open(url) }
            },
            Command(id: "nav.google", title: "Search Google", symbol: "magnifyingglass", color: .blue, keywords: ["g", "web", "browser"], dismiss: false) { [weak navigator] in navigator?.push(.google) },
            Command(id: "nav.files", title: "Search Files", subtitle: "Spotlight", symbol: "doc.text.magnifyingglass", color: .blue, keywords: ["find", "finder", "documents"], dismiss: false) { [weak navigator] in navigator?.push(.files) },
            Command(id: "nav.clipboard", title: "Clipboard History", symbol: "clipboard", color: .orange, keywords: ["paste", "copy", "history"], dismiss: false) { [weak navigator] in navigator?.push(.clipboard) },
            Command(id: "nav.emoji", title: "Search Emoji & Symbols", symbol: "face.smiling", color: .yellow, keywords: ["emoji", "emoticon"], dismiss: false) { [weak navigator] in navigator?.push(.emoji) },
            Command(id: "nav.wheel", title: "Color Wheel", symbol: "paintpalette", color: .pink, keywords: ["colour", "picker", "hex"], dismiss: false) { [weak navigator] in navigator?.push(.colorWheel) },
            Command(id: "nav.colors", title: "Saved Colors", symbol: "swatchpalette", color: .purple, keywords: ["colour", "palette", "history"], dismiss: false) { [weak navigator] in navigator?.push(.colors) },
            Command(id: "nav.windows", title: "Switch Windows", subtitle: "All Spaces", symbol: "macwindow.on.rectangle", color: .cyan, keywords: ["window", "switcher", "alt tab", "spaces", "focus"], dismiss: false) { [weak navigator] in navigator?.push(.windows) },
            Command(id: "nav.menu", title: "Search Menu Items", subtitle: NSWorkspace.shared.frontmostApplication?.localizedName, symbol: "filemenu.and.selection", color: .gray, keywords: ["menu bar", "commands", "actions"], dismiss: false) { [weak navigator] in navigator?.push(.menuItems) },
            Command(id: "nav.transform", title: "Transform Clipboard Text", subtitle: "Case, lines, Base64, JSON…", symbol: "textformat", color: .green, keywords: ["uppercase", "lowercase", "camel", "snake", "base64", "json", "url encode", "sort lines", "word count"], dismiss: false) { [weak navigator] in navigator?.push(.transform) },
            Command(id: "ocr.capture", title: "Capture Text from Screen", subtitle: "OCR", symbol: "text.viewfinder", color: .teal, keywords: ["ocr", "scan", "recognize", "clippy"]) { s.captureText() },
            Command(id: "color.pick", title: "Pick Color", subtitle: "Eyedropper", symbol: "eyedropper", color: .pink, keywords: ["colour", "dropper", "sample"], dismiss: false) { s.pickColor() },
            Command(id: "sys.awake", title: s.caffeine.active ? "Stop Keeping Awake" : "Keep Awake", subtitle: s.caffeine.active ? "Active" : nil, symbol: "cup.and.saucer.fill", color: .brown, keywords: ["caffeinate", "amphetamine", "sleep", "coffee"]) { s.caffeine.toggle() },
            Command(id: "sys.lock", title: "Lock Screen", symbol: "lock.fill", color: .gray, keywords: ["lock"]) { SystemActions.lockScreen() },
            Command(id: "sys.sleep", title: "Sleep", symbol: "moon.fill", color: .indigo) { Shell.run("/usr/bin/pmset", ["sleepnow"]) },
            Command(id: "sys.displaysleep", title: "Sleep Displays", symbol: "display", color: .indigo) { Shell.run("/usr/bin/pmset", ["displaysleepnow"]) },
            Command(id: "sys.trash", title: "Empty Trash", symbol: "trash.fill", color: .red, keywords: ["bin"]) { Shell.appleScript("tell application \"Finder\" to empty trash") },
            Command(id: "sys.dark", title: "Toggle System Appearance", subtitle: "Light / Dark", symbol: "circle.lefthalf.filled", color: .black, keywords: ["dark mode", "light mode", "theme"]) {
                Shell.appleScript("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
            },
            Command(id: "sys.mute", title: "Toggle Mute", symbol: "speaker.slash.fill", color: .gray, keywords: ["sound", "volume", "audio"]) {
                Shell.appleScript("set volume output muted not (output muted of (get volume settings))")
            },
            Command(id: "sys.hidden", title: "Toggle Hidden Files", subtitle: "Finder", symbol: "eye.slash", color: .blue, keywords: ["dotfiles", "show"]) { SystemActions.toggleHiddenFiles() },
            Command(id: "sys.finder", title: "Restart Finder", symbol: "arrow.clockwise", color: .blue, keywords: ["relaunch"]) { Shell.run("/usr/bin/killall", ["Finder"]) },
            Command(id: "sys.eject", title: "Eject All Disks", symbol: "eject.fill", color: .gray, keywords: ["unmount", "drive"]) {
                Shell.appleScript("tell application \"Finder\" to eject (every disk whose ejectable is true)")
            },
            Command(id: "sys.screensaver", title: "Start Screen Saver", symbol: "sparkles.tv", color: .purple) { Shell.run("/usr/bin/open", ["-a", "ScreenSaverEngine"]) },
            Command(id: "sys.restart", title: "Restart", symbol: "restart", color: .red, keywords: ["reboot"]) { Shell.appleScript("tell application \"loginwindow\" to «event aevtrrst»") },
            Command(id: "sys.shutdown", title: "Shut Down", symbol: "power", color: .red, keywords: ["power off", "turn off"]) { Shell.appleScript("tell application \"loginwindow\" to «event aevtrsdn»") },
            Command(id: "sys.logout", title: "Log Out", symbol: "rectangle.portrait.and.arrow.right", color: .red, keywords: ["sign out"]) { Shell.appleScript("tell application \"loginwindow\" to «event aevtrlgo»") },
            Command(id: "gen.uuid", title: "Generate UUID", symbol: "number", color: .mint, keywords: ["guid", "id", "random"]) {
                let value = UUID().uuidString.lowercased()
                Paster.copy(value)
                Toast.show("Copied \(value.prefix(13))…", symbol: "number")
            },
            Command(id: "gen.password", title: "Generate Password", symbol: "key.fill", color: .yellow, keywords: ["random", "secure"]) {
                Paster.copy(Generators.password())
                Toast.show("Copied a 20-character password", symbol: "key.fill", tint: .systemYellow)
            },
            Command(id: "gen.lorem", title: "Copy Lorem Ipsum", symbol: "text.quote", color: .gray, keywords: ["placeholder", "dummy text"]) {
                Paster.copy(Generators.lorem)
                Toast.show("Copied lorem ipsum", symbol: "text.quote")
            },
            Command(id: "fun.coin", title: "Flip a Coin", symbol: "circle.circle", color: .yellow, keywords: ["heads", "tails", "random"], dismiss: false) { [weak navigator] in
                navigator?.flash(Bool.random() ? "🪙  Heads" : "🪙  Tails", symbol: "circle.circle")
            },
            Command(id: "fun.dice", title: "Roll a Die", subtitle: "or type “roll 2d6”", symbol: "dice.fill", color: .red, keywords: ["random", "d6", "d20"], dismiss: false) { [weak navigator] in
                navigator?.flash("🎲  You rolled \(Int.random(in: 1...6))", symbol: "dice.fill")
            },
            Command(id: "link.downloads", title: "Downloads", symbol: "arrow.down.circle.fill", color: .blue, keywords: ["folder"], accessory: "Folder") { NSWorkspace.shared.open(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]) },
            Command(id: "link.desktop", title: "Desktop", symbol: "menubar.dock.rectangle", color: .blue, keywords: ["folder"], accessory: "Folder") { NSWorkspace.shared.open(FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]) },
            Command(id: "link.documents", title: "Documents", symbol: "doc.fill", color: .blue, keywords: ["folder"], accessory: "Folder") { NSWorkspace.shared.open(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) },
            Command(id: "link.home", title: "Home Folder", symbol: "house.fill", color: .blue, keywords: ["folder", "~"], accessory: "Folder") { NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory())) },
            Command(id: "prism.login", title: LoginItem.enabled ? "Don’t Open Prism at Login" : "Open Prism at Login", symbol: "power.circle", color: .indigo, keywords: ["startup", "launch"], accessory: "Settings") { LoginItem.toggle() },
            Command(id: "prism.pauseclip", title: s.clipboard.paused ? "Resume Clipboard History" : "Pause Clipboard History", symbol: s.clipboard.paused ? "play.fill" : "pause.fill", color: .orange, keywords: ["private", "incognito"], accessory: "Settings") {
                s.clipboard.paused.toggle()
                Toast.show(s.clipboard.paused ? "Clipboard history paused" : "Clipboard history resumed", symbol: s.clipboard.paused ? "pause.fill" : "play.fill", tint: .systemOrange)
            },
            Command(id: "prism.literal", title: OCRController.literalMode ? "OCR: Use Spelling Correction" : "OCR: Literal Text Mode", subtitle: "Better for code", symbol: "textformat.abc", color: .teal, keywords: ["ocr", "spelling"], accessory: "Settings", dismiss: false) { [weak navigator] in
                OCRController.literalMode.toggle()
                navigator?.flash(OCRController.literalMode ? "OCR keeps text literally" : "OCR corrects spelling", symbol: "textformat.abc")
                navigator?.refresh(keepSelection: true)
            },
            Command(id: "prism.forgetlearned", title: "Reset Learned Searches", subtitle: "Forget which result each query means", symbol: "arrow.uturn.backward.circle", color: .gray, keywords: ["abbreviations", "aliases", "learning"], accessory: "Settings", dismiss: false) { [weak navigator] in
                s.learned.reset()
                navigator?.flash("Learned searches cleared", symbol: "arrow.uturn.backward.circle")
            },
            Command(id: "prism.reload", title: "Reload Applications", symbol: "arrow.triangle.2.circlepath", color: .gray, keywords: ["refresh", "index"], accessory: "Settings", dismiss: false) { [weak navigator] in
                s.apps.reload()
                navigator?.flash("Reindexing applications", symbol: "arrow.triangle.2.circlepath")
            },
            Command(id: "prism.settings", title: "Prism Settings", subtitle: "Shortcuts and permissions · ⌘,", symbol: "gearshape", color: .gray, keywords: ["preferences", "rebind", "access", "permissions"], accessory: "Settings") { SettingsController.shared.show() },
            Command(id: "prism.accessibility", title: "Grant Accessibility Access", subtitle: Accessibility.trusted ? "Granted" : "Needed for paste & windows", symbol: "hand.raised.fill", color: .blue, keywords: ["permission"], accessory: "Settings") {
                if !Accessibility.ensureTrusted(), let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
            },
            Command(id: "prism.position", title: "Reset Prism Window Position", symbol: "arrow.down.right.and.arrow.up.left", color: .gray, keywords: ["center", "move"], accessory: "Settings", dismiss: false) { [weak navigator] in
                s.launcher?.resetPosition()
                navigator?.flash("Window position reset", symbol: "arrow.down.right.and.arrow.up.left")
            },
            Command(id: "prism.quit", title: "Quit Prism", symbol: "xmark.circle.fill", color: .gray, accessory: "Settings") { NSApp.terminate(nil) },
        ]
        let panes: [(String, String, String, Color, [String])] = [
            ("Wi-Fi Settings", "com.apple.wifi-settings-extension", "wifi", .blue, ["network", "internet"]),
            ("Bluetooth Settings", "com.apple.BluetoothSettings", "dot.radiowaves.left.and.right", .blue, ["airpods", "headphones"]),
            ("Displays Settings", "com.apple.Displays-Settings.extension", "display", .blue, ["monitor", "resolution"]),
            ("Sound Settings", "com.apple.Sound-Settings.extension", "speaker.wave.2.fill", .pink, ["audio", "output"]),
            ("Privacy & Security", "com.apple.settings.PrivacySecurity.extension", "hand.raised.fill", .blue, ["permissions"]),
            ("Battery Settings", "com.apple.Battery-Settings.extension", "battery.100", .green, ["power", "energy"]),
            ("Keyboard Settings", "com.apple.Keyboard-Settings.extension", "keyboard", .gray, ["shortcuts"]),
        ]
        for (title, pane, symbol, color, keywords) in panes {
            list.append(Command(id: "pane.\(pane)", title: title, symbol: symbol, color: color, keywords: keywords + ["settings", "preferences"], accessory: "System Settings") {
                if let url = URL(string: "x-apple.systempreferences:\(pane)") { NSWorkspace.shared.open(url) }
            })
        }
        for action in WindowAction.allCases {
            list.append(Command(id: "window.\(action.rawValue)", title: action.title, symbol: action.symbol, color: .cyan, keywords: ["window", "snap", "resize", "move"], accessory: "Window") {
                // The launcher is a non-activating panel, so the previously focused app is still frontmost.
                WindowManager.perform(action)
            })
        }
        return list
    }

    func item(for command: Command, section: String) -> ResultItem {
        ResultItem(
            id: command.id, title: command.title, subtitle: command.subtitle, icon: .symbol(command.symbol, command.color),
            accessory: command.accessory, section: section,
            actions: [ItemAction(title: command.dismiss ? "Run Command" : "Open Command", symbol: "return", shortcut: .enter, dismiss: command.dismiss, run: command.run)],
            usageKey: command.id
        )
    }
}
