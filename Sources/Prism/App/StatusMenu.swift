import AppKit

/// The menu bar item, and the app menu that gives the accessory app ⌘, ⌘Q and the Edit commands.
final class StatusMenu: NSObject {
    private var status: NSStatusItem?
    private let services: AppServices
    private let shortcuts: GlobalShortcuts

    init(services: AppServices, shortcuts: GlobalShortcuts) {
        self.services = services
        self.shortcuts = shortcuts
    }

    func build() {
        if status == nil { status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength) }
        updateIcon()
        let menu = NSMenu()
        func item(_ title: String, _ shortcut: String?, _ action: Selector) {
            let entry = NSMenuItem(title: shortcut.map { "\(title)    \($0)" } ?? title, action: action, keyEquivalent: "")
            entry.target = self
            menu.addItem(entry)
        }
        item("Open Prism", shortcuts.keys(for: "Open Prism"), #selector(openLauncher))
        item("Clipboard History", shortcuts.keys(for: "Clipboard History"), #selector(openClipboard))
        item("Capture Text (OCR)", shortcuts.keys(for: "Capture Text (OCR)"), #selector(captureText))
        item("Pick Color", shortcuts.keys(for: "Pick Color"), #selector(pickColor))
        item("Color Wheel", nil, #selector(openWheel))
        menu.addItem(.separator())
        let shortcutsItem = NSMenuItem(title: "Keyboard Shortcuts", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (name, keys) in shortcuts.active {
            let entry = NSMenuItem(title: "\(name)    \(keys)", action: nil, keyEquivalent: "")
            entry.isEnabled = false
            submenu.addItem(entry)
        }
        shortcutsItem.submenu = submenu
        menu.addItem(shortcutsItem)
        item("Settings…", "⌘,", #selector(openSettings))
        item("Keep Awake", nil, #selector(toggleAwake))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Prism", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        status?.menu = menu
    }

    func updateIcon() {
        let awake = services.caffeine.active
        let image = NSImage(systemSymbolName: awake ? "cup.and.saucer.fill" : "sparkle.magnifyingglass", accessibilityDescription: "Prism")
        image?.isTemplate = true
        status?.button?.image = image
        status?.button?.toolTip = awake ? "Prism — keeping your Mac awake" : "Prism"
    }

    /// Accessory apps still need an Edit menu for ⌘C/⌘V/⌘A/⌘Z in the search field.
    func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Prism", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        edit.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    @objc private func openSettings() { SettingsController.shared.show() }
    @objc private func openLauncher() { services.launcher?.show(.root) }
    @objc private func openClipboard() { services.launcher?.show(.clipboard) }
    @objc private func openWheel() { services.launcher?.show(.colorWheel) }
    @objc private func captureText() { services.captureText() }
    @objc private func pickColor() { services.pickColor() }
    @objc private func toggleAwake() { services.caffeine.toggle() }
}
