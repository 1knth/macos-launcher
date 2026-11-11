import AppKit

/// Hardware key codes the launcher handles directly (from Carbon's `kVK_*`).
enum KeyCode {
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let delete: UInt16 = 51
    static let escape: UInt16 = 53
    static let pageUp: UInt16 = 116
    static let pageDown: UInt16 = 121
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126

    static func isReturn(_ code: UInt16) -> Bool { code == returnKey || code == keypadEnter }
}

/// A keyboard shortcut for an item action, shown as keycaps and matched against key events.
struct KeyCombo: Equatable {
    /// Lowercased character, "\r" for Return or "⌫" for Delete.
    let key: String
    let modifiers: NSEvent.ModifierFlags

    static let enter = KeyCombo(key: "\r", modifiers: [])
    static let cmdEnter = KeyCombo(key: "\r", modifiers: .command)
    static func cmd(_ key: String) -> KeyCombo { KeyCombo(key: key, modifiers: .command) }
    static func cmdShift(_ key: String) -> KeyCombo { KeyCombo(key: key, modifiers: [.command, .shift]) }
    static func cmdOption(_ key: String) -> KeyCombo { KeyCombo(key: key, modifiers: [.command, .option]) }
    static func ctrl(_ key: String) -> KeyCombo { KeyCombo(key: key, modifiers: .control) }
    static func ctrlShift(_ key: String) -> KeyCombo { KeyCombo(key: key, modifiers: [.control, .shift]) }

    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    func matches(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(Self.relevantModifiers)
        guard flags == modifiers else { return false }
        return Self.key(for: event) == key
    }

    static func key(for event: NSEvent) -> String {
        if KeyCode.isReturn(event.keyCode) { return "\r" }
        if event.keyCode == KeyCode.delete { return "⌫" }
        return event.charactersIgnoringModifiers?.lowercased() ?? ""
    }

    /// Individual keycap labels, e.g. ["⌘", "⇧", "C"].
    var caps: [String] {
        var result: [String] = []
        if modifiers.contains(.control) { result.append("⌃") }
        if modifiers.contains(.option) { result.append("⌥") }
        if modifiers.contains(.shift) { result.append("⇧") }
        if modifiers.contains(.command) { result.append("⌘") }
        result.append(key == "\r" ? "↩" : key.uppercased())
        return result
    }
}
