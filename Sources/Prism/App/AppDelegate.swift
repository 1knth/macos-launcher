import AppKit

/// Launch and teardown. Builds the services, the launcher, global shortcuts and the menu bar item, then wires them.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let services = AppServices.shared
    private lazy var shortcuts = GlobalShortcuts(services: services)
    private lazy var statusMenu = StatusMenu(services: services, shortcuts: shortcuts)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusMenu.installMainMenu()
        services.start()
        let launcher = LauncherController()
        services.launcher = launcher
        services.caffeine.onChange = { [weak self] in self?.statusMenu.updateIcon() }
        PrismSettings.shared.reloadShortcuts = { [weak self] in self?.shortcuts.register() }
        PrismSettings.shared.menuChanged = { [weak self] in self?.statusMenu.build() }
        shortcuts.register()
        statusMenu.build()
        // First launch: open right away so it's obvious where Prism lives.
        if !UserDefaults.standard.bool(forKey: DefaultsKey.launchedBefore) {
            UserDefaults.standard.set(true, forKey: DefaultsKey.launchedBefore)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { launcher.show() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        services.launcher?.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeys.shared.unregisterAll()
    }
}
