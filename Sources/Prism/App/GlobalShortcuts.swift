import AppKit
import Carbon

/// The system-wide shortcuts, registered from defaults or the user's custom bindings in Settings.
final class GlobalShortcuts {
    /// Name and keys of every shortcut that registered, for the status menu.
    private(set) var active: [(name: String, keys: String)] = []
    private let services: AppServices

    init(services: AppServices) { self.services = services }

    func register() {
        let hotKeys = HotKeys.shared
        let settings = PrismSettings.shared
        hotKeys.unregisterAll()
        active.removeAll()
        settings.shortcuts.removeAll()
        let services = services
        func add(_ name: String, _ binding: HotKeys.Binding, fallback: HotKeys.Binding? = nil, _ action: @escaping () -> Void) {
            let custom = settings.saved(name)
            var selected = custom ?? binding
            var registered = hotKeys.register(selected, action)
            if !registered, custom == nil, let fallback {
                selected = fallback
                registered = hotKeys.register(fallback, action)
            }
            if registered { active.append((name, selected.display)) }
            settings.shortcuts.append(.init(name: name, binding: selected, active: registered))
        }
        // ⌥Space is taken while Raycast or Alfred run; fall back to ⌘⇧Space.
        add("Open Prism", key(kVK_Space, optionKey, "Space"), fallback: key(kVK_Space, cmdKey | shiftKey, "Space")) { services.launcher?.toggle() }
        add("Clipboard History", key(kVK_ANSI_V, cmdKey | optionKey, "V")) { services.launcher?.show(.clipboard) }
        // Clippy uses ⌃⇧T; if it's still running, use ⌃⌥T instead.
        add("Capture Text (OCR)", key(kVK_ANSI_T, controlKey | shiftKey, "T"), fallback: key(kVK_ANSI_T, controlKey | optionKey, "T")) { services.captureText() }
        add("Pick Color", key(kVK_ANSI_P, controlKey | optionKey, "P")) { services.pickColor() }
        add("Search Emoji", key(kVK_ANSI_E, controlKey | optionKey | cmdKey, "E")) { services.launcher?.show(.emoji) }
        guard UserDefaults.standard.object(forKey: DefaultsKey.windowShortcuts) as? Bool ?? true else { return }
        let windowKeys: [(Int, String, WindowAction)] = [
            (kVK_LeftArrow, "←", .leftHalf), (kVK_RightArrow, "→", .rightHalf), (kVK_UpArrow, "↑", .topHalf),
            (kVK_DownArrow, "↓", .bottomHalf), (kVK_Return, "↩", .maximize), (kVK_ANSI_C, "C", .center),
            (kVK_Delete, "⌫", .restore), (kVK_ANSI_D, "D", .leftThird), (kVK_ANSI_F, "F", .centerThird), (kVK_ANSI_G, "G", .rightThird),
        ]
        for (code, label, action) in windowKeys {
            add("Window: \(action.title)", key(code, controlKey | optionKey, label)) { WindowManager.perform(action) }
        }
    }

    func keys(for name: String) -> String? { active.first { $0.name == name }?.keys }

    private func key(_ code: Int, _ modifiers: Int, _ label: String) -> HotKeys.Binding {
        HotKeys.Binding(keyCode: UInt32(code), modifiers: UInt32(modifiers), label: label)
    }
}
