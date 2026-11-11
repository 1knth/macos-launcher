import AppKit

/// A clickable item from the frontmost app's menu bar.
struct MenuEntry {
    let element: AXUIElement
    let title: String
    let path: String
    let shortcut: String?
}

enum MenuBarItems {
    static func items(of app: NSRunningApplication) -> [MenuEntry] {
        guard Accessibility.trusted else { return [] }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        guard let bar: AXUIElement = attribute(root, kAXMenuBarAttribute) else { return [] }
        var output: [MenuEntry] = []
        // Skip the Apple menu; it's the same in every app.
        for top in children(bar).dropFirst() {
            let name: String = attribute(top, kAXTitleAttribute) ?? ""
            for menu in children(top) { walk(menu, path: [name], into: &output, depth: 0) }
        }
        return output
    }

    private static func walk(_ menu: AXUIElement, path: [String], into output: inout [MenuEntry], depth: Int) {
        guard depth < 4, output.count < 2000 else { return }
        for item in children(menu) {
            let title: String = attribute(item, kAXTitleAttribute) ?? ""
            guard !title.isEmpty else { continue }
            let submenus = children(item)
            if !submenus.isEmpty {
                for submenu in submenus { walk(submenu, path: path + [title], into: &output, depth: depth + 1) }
                continue
            }
            guard (attribute(item, kAXEnabledAttribute) as Bool?) ?? true else { continue }
            output.append(MenuEntry(element: item, title: title, path: path.joined(separator: " › "), shortcut: shortcut(item)))
        }
    }

    private static func shortcut(_ item: AXUIElement) -> String? {
        guard let key: String = attribute(item, kAXMenuItemCmdCharAttribute), !key.isEmpty else { return nil }
        let modifiers: Int = attribute(item, kAXMenuItemCmdModifiersAttribute) ?? 0
        // Bits: 1 shift, 2 option, 4 control, 8 no command.
        var text = ""
        if modifiers & 4 != 0 { text += "⌃" }
        if modifiers & 2 != 0 { text += "⌥" }
        if modifiers & 1 != 0 { text += "⇧" }
        if modifiers & 8 == 0 { text += "⌘" }
        return text + key
    }

    static func press(_ entry: MenuEntry) {
        AXUIElementPerformAction(entry.element, kAXPressAction as CFString)
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) ?? []
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
